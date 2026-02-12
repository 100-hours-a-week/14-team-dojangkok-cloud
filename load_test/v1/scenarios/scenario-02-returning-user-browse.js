/**
 * 시나리오 2: 기존 사용자 탐색 플로우
 *
 * 흐름: (인증) → 프로필 조회 → 라이프스타일 확인 → 집 노트 목록 조회(페이지네이션)
 *       → 체크리스트 조회
 *
 * 이미 가입된 사용자가 앱에 재접속하여 기존 데이터를 열람하는 가장 일반적인 패턴입니다.
 * 전체 트래픽의 대부분을 차지하므로 가장 높은 VU 수로 테스트합니다.
 *
 * 인증: tokens.json 또는 ACCESS_TOKENS 환경변수로 토큰 풀 사용 (권장)
 *       ACCESS_TOKEN 환경변수로 단일 토큰 사용 (fallback)
 */
import { sleep } from 'k6';
import { THRESHOLDS } from '../config.js';
import { initTokenPool, getToken } from '../token-pool.js';
import {
  initToken,
  getProfile,
  getLifestyle,
  listHomeNotes,
  getChecklist,
} from '../helpers.js';

export const options = {
  // DNS를 통한 도메인 연결 (hosts 매핑 제거)
  scenarios: {
    returning_user_browse: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 800 },
        { duration: '6m', target: 800 },
        { duration: '2m', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    ...THRESHOLDS,
    'http_req_duration{name:GET /members/me}': ['p(95)<1000'],
    'http_req_duration{name:GET /lifestyles}': ['p(95)<1000'],
    'http_req_duration{name:GET /home-notes}': ['p(95)<2000'],
    'http_req_duration{name:GET /home-notes/{id}/checklists}': ['p(95)<1500'],
  },
};

export function setup() {
  const poolInfo = initTokenPool();
  if (poolInfo.usePool) {
    return poolInfo;
  }
  return { usePool: false, token: initToken() };
}

export default function (data) {
  const token = getToken(data);
  if (!token) {
    sleep(5);
    return;
  }

  // Step 1: 프로필 조회 (앱 초기 화면 로드)
  getProfile(token);
  sleep(0.3);

  // Step 2: 라이프스타일 확인
  getLifestyle(token);
  sleep(1);

  // Step 3: 집 노트 목록 조회 (메인 화면)
  const firstPage = listHomeNotes(token, null);
  sleep(2);

  // Step 4: 페이지네이션 - 다음 페이지 로드 (스크롤)
  if (firstPage && firstPage.hasNext && firstPage.next_cursor) {
    listHomeNotes(token, firstPage.next_cursor);
    sleep(1.5);
  }

  // Step 5: 특정 집 노트의 체크리스트 조회 (상세 진입)
  if (firstPage && firstPage.items && firstPage.items.length > 0) {
    const randomIndex = Math.floor(Math.random() * firstPage.items.length);
    const homeNoteId = firstPage.items[randomIndex].home_note_id;
    getChecklist(token, homeNoteId);
    sleep(2);
  }

  sleep(1);
}
