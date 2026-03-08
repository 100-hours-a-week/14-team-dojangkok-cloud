/**
 * 시나리오 6: 매물 게시판 탐색 플로우 [NEW - v2 전용]
 *
 * 흐름: (인증) → 매물 게시글 목록 조회(페이지네이션) → 검색 결과 개수 조회
 *       → 매물 검색/필터링 → 매물 상세 조회 → 스크랩 추가/목록 조회/삭제
 *
 * 매물 게시판이 v2에서 새로 추가된 핵심 피처입니다.
 * 실제 사용자가 매물 목록을 탐색하고 관심 매물을 저장하는 패턴을 집중적으로 측정합니다.
 *
 * 주요 측정 대상:
 *   - GET /property-posts 목록 조회 응답 시간 (페이지네이션 포함)
 *   - POST /property-posts/searches 검색/필터링 응답 시간
 *   - POST /property-posts/searches/counts 개수 조회 응답 시간
 *   - GET /property-posts/{id} 상세 조회 응답 시간
 *   - POST/DELETE /property-posts/{id}/bookmarks 스크랩 추가/삭제 응답 시간
 *   - GET /property-posts/bookmarks 스크랩 목록 조회 응답 시간
 *
 * 인증: tokens.json 또는 ACCESS_TOKENS 환경변수로 토큰 풀 사용 (권장)
 *       ACCESS_TOKEN 환경변수로 단일 토큰 사용 (fallback)
 */
import { sleep } from 'k6';
import { THRESHOLDS } from '../../config.js';
import { initTokenPool, getToken } from '../../token-pool.js';
import {
  initToken,
  listPropertyPosts,
  searchPropertyPosts,
  countPropertyPosts,
  getPropertyPost,
  addPropertyPostBookmark,
  removePropertyPostBookmark,
  listBookmarkedPropertyPosts,
} from '../../helpers.js';

export const options = {
  scenarios: {
    property_post_browse: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 400 },
        { duration: '6m', target: 400 },
        { duration: '2m', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    ...THRESHOLDS,
    'http_req_duration{name:GET /property-posts}': ['p(95)<2000'],
    'http_req_duration{name:POST /property-posts/searches/counts}': ['p(95)<1500'],
    'http_req_duration{name:POST /property-posts/searches}': ['p(95)<2000'],
    'http_req_duration{name:GET /property-posts/{id}}': ['p(95)<1500'],
    'http_req_duration{name:POST /property-posts/{id}/bookmarks}': ['p(95)<1000'],
    'http_req_duration{name:DELETE /property-posts/{id}/bookmarks}': ['p(95)<1000'],
    'http_req_duration{name:GET /property-posts/bookmarks}': ['p(95)<2000'],
  },
};

// 검색 필터 프리셋: 다양한 조건으로 매물 탐색
const SEARCH_PRESETS = [
  {},                                                                    // 필터 없음 (전체)
  { rent_type: ['MONTHLY'] },                                           // 월세
  { rent_type: ['JEONSE'] },                                            // 전세
  { property_type: ['STUDIO'] },                                       // 원룸/스튜디오
  { is_verified: true },                                                 // 인증 매물
  { rent_type: ['MONTHLY'], property_type: ['STUDIO'] },               // 월세 원룸
  { rent_type: ['JEONSE'], property_type: ['STUDIO'] },                // 전세 원룸
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

  // Step 1: 매물 게시글 목록 조회 (메인 피드 진입)
  const firstPage = listPropertyPosts(token, null);
  sleep(2);

  // Step 2: 페이지네이션 (스크롤 다운)
  if (firstPage && firstPage.hasNext && firstPage.next_cursor) {
    listPropertyPosts(token, firstPage.next_cursor);
    sleep(1.5);
  }

  // Step 3: 검색 필터 조건으로 매물 개수 사전 조회 (검색 UI 진입 시)
  const searchFilter = SEARCH_PRESETS[vuId % SEARCH_PRESETS.length];
  countPropertyPosts(token, searchFilter);
  sleep(0.5);

  // Step 4: 매물 검색/필터링 실행
  const searchResult = searchPropertyPosts(token, searchFilter, null);
  sleep(2);

  // Step 5: 검색 결과 페이지네이션
  if (searchResult && searchResult.hasNext && searchResult.next_cursor) {
    searchPropertyPosts(token, searchFilter, searchResult.next_cursor);
    sleep(1.5);
  }

  // Step 6: 매물 상세 조회 (목록 또는 검색 결과에서 진입)
  const candidates = (searchResult && searchResult.property_post_items && searchResult.property_post_items.length > 0)
    ? searchResult.property_post_items
    : (firstPage && firstPage.property_post_items);

  let viewedPostId = null;
  if (candidates && candidates.length > 0) {
    const idx = Math.floor(Math.random() * candidates.length);
    viewedPostId = candidates[idx].property_post_id;
    getPropertyPost(token, viewedPostId);
    sleep(2);
  }

  // Step 7: 스크랩 추가 → 목록 확인 → 삭제 (50% 확률)
  if (viewedPostId && Math.random() < 0.5) {
    addPropertyPostBookmark(token, viewedPostId);
    sleep(0.5);

    listBookmarkedPropertyPosts(token, null);
    sleep(1);

    removePropertyPostBookmark(token, viewedPostId);
    sleep(0.5);
  }

  sleep(1);
}
