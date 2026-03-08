/**
 * 시나리오 9: 스파이크 테스트
 *
 * 갑작스러운 트래픽 급증(마케팅 이벤트, 푸시 알림 발송 등)에 대한 시스템 내성을 측정합니다.
 * 짧은 시간 내에 부하가 급격히 증가했다가 감소하는 패턴을 시뮬레이션합니다.
 *
 * v1 대비 변경 사항:
 *   - 매물 게시글 목록 조회 추가 (앱 하단 탭 진입 패턴)
 *   - 매물 검색/필터링 추가 (50% 확률)
 *   - 매물 상세 조회 추가 (검색 결과 진입 패턴)
 *
 * 인증: tokens.json 또는 ACCESS_TOKENS 환경변수로 토큰 풀 사용 (권장)
 *       ACCESS_TOKEN 환경변수로 단일 토큰 사용 (fallback)
 */
import { sleep } from 'k6';
import { THRESHOLDS } from '../../config.js';
import { initTokenPool, getToken } from '../../token-pool.js';
import {
  initToken,
  getProfile,
  listHomeNotes,
  getChecklist,
  getLifestyle,
  createHomeNote,
  deleteHomeNote,
  listPropertyPosts,
  searchPropertyPosts,
  getPropertyPost,
} from '../../helpers.js';

export const options = {
  scenarios: {
    spike: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 10 },   // 정상 수준
        { duration: '1m', target: 300 },  // 급격한 스파이크
        { duration: '4m', target: 300 },  // 스파이크 유지
        { duration: '1m', target: 10 },   // 급격한 감소
        { duration: '2m', target: 0 },    // 종료
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<10000'],
    http_req_failed: ['rate<0.15'],
  },
};

const SEARCH_PRESETS = [
  {},
  { rent_type: ['MONTHLY'] },
  { property_type: ['STUDIO'] },
  { is_verified: true },
];

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

  // 집 노트 탐색 플로우
  getProfile(token);
  sleep(0.3);

  getLifestyle(token);
  sleep(0.3);

  const page = listHomeNotes(token, null);
  sleep(0.5);

  if (page && page.items && page.items.length > 0 && Math.random() > 0.5) {
    const idx = Math.floor(Math.random() * page.items.length);
    getChecklist(token, page.items[idx].home_note_id);
  }

  // 10% 확률로 집 노트 생성 (쓰기 부하)
  if (Math.random() < 0.1) {
    const note = createHomeNote(token, `스파이크테스트 ${Date.now()}`);
    if (note && note.home_note_id) {
      try {
        sleep(0.5);
      } finally {
        deleteHomeNote(token, note.home_note_id);
      }
    }
  }

  sleep(0.5);

  // [NEW] 매물 게시판 탐색 (60% 확률로 진입)
  if (Math.random() < 0.6) {
    const propPage = listPropertyPosts(token, null);
    sleep(0.5);

    // 50% 확률로 검색/필터 사용
    if (Math.random() < 0.5) {
      const filter = SEARCH_PRESETS[__VU % SEARCH_PRESETS.length];
      const searchResult = searchPropertyPosts(token, filter, null);
      sleep(0.5);

      // 검색 결과에서 상세 조회
      const items = (searchResult && searchResult.property_post_items)
        || (propPage && propPage.property_post_items);
      if (items && items.length > 0) {
        const idx = Math.floor(Math.random() * items.length);
        getPropertyPost(token, items[idx].property_post_id);
        sleep(0.5);
      }
    }
  }

  sleep(1);
}
