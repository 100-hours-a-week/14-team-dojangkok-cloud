/**
 * 시나리오 2: 기존 사용자 탐색 플로우
 *
 * 흐름: (인증) → 프로필 조회 → 라이프스타일 확인 → 집 노트 목록 조회(페이지네이션)
 *       → 체크리스트 조회 → [NEW] 매물 게시글 목록 조회 → [NEW] 매물 검색/필터링
 *       → [NEW] 매물 상세 조회
 *
 * v1 대비 변경 사항:
 *   - 매물 게시글 목록 조회 추가 (앱 하단 탭 진입)
 *   - 매물 검색/필터링 추가 (rent_type, property_type 기반)
 *   - 검색 결과에서 매물 상세 조회 추가
 *
 * 이미 가입된 사용자가 앱에 재접속하여 집 노트와 매물 게시판을 모두 탐색하는 패턴.
 * 전체 트래픽의 대부분을 차지하므로 가장 높은 VU 수로 테스트합니다.
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
  getLifestyle,
  listHomeNotes,
  getChecklist,
  listPropertyPosts,
  searchPropertyPosts,
  getPropertyPost,
} from '../../helpers.js';

export const options = {
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
    'http_req_duration{name:GET /property-posts}': ['p(95)<2000'],
    'http_req_duration{name:POST /property-posts/searches}': ['p(95)<2000'],
    'http_req_duration{name:GET /property-posts/{id}}': ['p(95)<1500'],
  },
};

// 검색 필터 프리셋: VU별로 다양한 조건으로 탐색
const SEARCH_PRESETS = [
  {},                                                               // 필터 없음 (전체 조회)
  { rent_type: ['MONTHLY'] },                                      // 월세만
  { rent_type: ['JEONSE'] },                                       // 전세만
  { rent_type: ['JEONSE_MONTHLY'] },                              // 반전세만
  { property_type: ['STUDIO'] },                                  // 원룸/스튜디오
  { property_type: ['MULTI_ROOM'] },                              // 투룸+
  { is_verified: true },                                           // 인증 매물
  { rent_type: ['MONTHLY'], property_type: ['STUDIO'] },          // 월세 원룸
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
  const vuId = __VU;

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

  // Step 6: [NEW] 매물 게시판 탐색 (70% 확률 — 하단 탭 진입 패턴 반영)
  // 모든 세션에서 방문하지 않으므로 확률 적용
  if (Math.random() < 0.7) {
    const propPage = listPropertyPosts(token, null);
    sleep(1.5);

    // Step 7: [NEW] 매물 검색/필터링 (탭 진입 사용자의 60%가 검색 사용)
    if (Math.random() < 0.6) {
      const searchFilter = SEARCH_PRESETS[vuId % SEARCH_PRESETS.length];
      const searchResult = searchPropertyPosts(token, searchFilter, null);
      sleep(2);

      // Step 8: [NEW] 검색 결과에서 매물 상세 조회
      const items = (searchResult && searchResult.property_post_items && searchResult.property_post_items.length > 0)
        ? searchResult.property_post_items
        : (propPage && propPage.property_post_items);
      if (items && items.length > 0) {
        const randomIndex = Math.floor(Math.random() * items.length);
        getPropertyPost(token, items[randomIndex].property_post_id);
        sleep(1.5);
      }
    } else {
      // 검색 없이 목록에서 바로 상세 진입
      const items = propPage && propPage.property_post_items;
      if (items && items.length > 0) {
        const randomIndex = Math.floor(Math.random() * items.length);
        getPropertyPost(token, items[randomIndex].property_post_id);
        sleep(1.5);
      }
    }
  }

  sleep(1);
}
