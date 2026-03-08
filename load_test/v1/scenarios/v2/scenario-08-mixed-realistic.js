/**
 * 시나리오 8: 혼합 현실적 부하 테스트 (종합 시나리오)
 *
 * 실제 서비스의 트래픽 비율을 반영하여 여러 사용자 유형을 동시에 시뮬레이션합니다.
 *
 * 트래픽 비율 (v2 — 매물 게시판 추가):
 *   - 기존 사용자 탐색 (38%): 집 노트 + 매물 탐색 혼합
 *   - 매물 게시판 탐색 (22%): 매물 목록/검색/상세/스크랩 위주
 *   - 체크리스트 사용 (17%): 집을 보러 간 사용자
 *   - 집 노트 CRUD (11%): 새 매물 기록
 *   - 신규 가입 (5%): 신규 유입
 *   - 파일 업로드 (4%): 사진/문서 첨부
 *   - 매물 게시 (3%): 매물 등록 + 상태 관리
 *
 * v1 대비 변경 사항:
 *   - property_browse_users 시나리오 추가 (매물 탐색)
 *   - property_post_users 시나리오 추가 (매물 등록/관리)
 *   - browse_users 비율 조정 (60% → 38%)
 *
 * 인증: tokens.json 또는 ACCESS_TOKENS 환경변수로 토큰 풀 사용 (권장)
 *       ACCESS_TOKEN 환경변수로 단일 토큰 사용 (fallback)
 */
import { sleep, group } from 'k6';
import { THRESHOLDS } from '../../config.js';
import { initTokenPool, getToken } from '../../token-pool.js';
import {
  initToken,
  getProfile,
  setNickname,
  getLifestyle,
  createLifestyle,
  listHomeNotes,
  createHomeNote,
  updateHomeNoteTitle,
  deleteHomeNote,
  getChecklist,
  toggleChecklistItem,
  getFilePresignedUrls,
  uploadToS3,
  completeFileUploadV2,
  attachFilesToHomeNote,
  listPropertyPosts,
  getPropertyPost,
  createPropertyPost,
  updatePropertyPost,
  deletePropertyPost,
  searchPropertyPosts,
  countPropertyPosts,
  addPropertyPostBookmark,
  removePropertyPostBookmark,
  listBookmarkedPropertyPosts,
  updatePropertyPostDealStatus,
} from '../../helpers.js';

// init 단계에서 매물/집노트 공용 테스트 이미지 5장 로드
const PROPERTY_IMAGES = [
  open('../../test-files/property-1.jpg', 'b'),
  open('../../test-files/property-2.jpg', 'b'),
  open('../../test-files/property-3.jpg', 'b'),
  open('../../test-files/property-4.jpg', 'b'),
  open('../../test-files/property-5.jpg', 'b'),
];

export const options = {
  scenarios: {
    // 기존 사용자 탐색 (38%) — 집 노트 + 간헐적 매물 탐색
    browse_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 380 },
        { duration: '6m', target: 380 },
        { duration: '2m', target: 0 },
      ],
      exec: 'browseFlow',
      gracefulRampDown: '30s',
    },
    // 매물 게시판 탐색 (22%) [NEW]
    property_browse_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 220 },
        { duration: '6m', target: 220 },
        { duration: '2m', target: 0 },
      ],
      exec: 'propertyBrowseFlow',
      gracefulRampDown: '30s',
    },
    // 체크리스트 집중 사용 (17%)
    checklist_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 170 },
        { duration: '6m', target: 170 },
        { duration: '2m', target: 0 },
      ],
      exec: 'checklistFlow',
      gracefulRampDown: '30s',
    },
    // 집 노트 CRUD (11%)
    crud_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 110 },
        { duration: '6m', target: 110 },
        { duration: '2m', target: 0 },
      ],
      exec: 'crudFlow',
      gracefulRampDown: '30s',
    },
    // 신규 가입 (5%)
    new_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 50 },
        { duration: '6m', target: 50 },
        { duration: '2m', target: 0 },
      ],
      exec: 'onboardingFlow',
      gracefulRampDown: '30s',
    },
    // 파일 업로드 (4%)
    upload_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 40 },
        { duration: '6m', target: 40 },
        { duration: '2m', target: 0 },
      ],
      exec: 'uploadFlow',
      gracefulRampDown: '30s',
    },
    // 매물 등록/관리 (3%) [NEW]
    property_post_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 30 },
        { duration: '6m', target: 30 },
        { duration: '2m', target: 0 },
      ],
      exec: 'propertyPostFlow',
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    ...THRESHOLDS,
    'http_req_duration{name:GET /members/me}': ['p(95)<1000'],
    'http_req_duration{name:GET /home-notes}': ['p(95)<2000'],
    'http_req_duration{name:GET /home-notes/{id}/checklists}': ['p(95)<1500'],
    'http_req_duration{name:POST /home-notes}': ['p(95)<3000'],
    'http_req_duration{name:PATCH /checklists/items/{id}}': ['p(95)<1500'],
    'http_req_duration{name:PUT S3 presigned-upload}': ['p(95)<10000'],
    'http_req_duration{name:GET /property-posts}': ['p(95)<2000'],
    'http_req_duration{name:POST /property-posts/searches}': ['p(95)<2000'],
    'http_req_duration{name:GET /property-posts/{id}}': ['p(95)<1500'],
    'http_req_duration{name:POST /property-posts}': ['p(95)<3000'],
    'http_req_duration{name:PATCH /property-posts/{id}}': ['p(95)<1500'],
    'http_req_duration{name:PATCH /property-posts/{id}/deal-status}': ['p(95)<1000'],
    'http_req_duration{name:DELETE /property-posts/{id}}': ['p(95)<2000'],
    'http_req_duration{name:POST /property-posts/files/presigned-urls}': ['p(95)<3000'],
    'http_req_duration{name:POST /property-posts/files/complete}': ['p(95)<2000'],
    'http_req_duration{name:POST /property-posts/{id}/files}': ['p(95)<2000'],
    'http_req_duration{name:POST /property-posts/{id}/bookmarks}': ['p(95)<1000'],
    'http_req_duration{name:DELETE /property-posts/{id}/bookmarks}': ['p(95)<1000'],
  },
};

export function setup() {
  const poolInfo = initTokenPool();
  if (poolInfo.usePool) {
    return poolInfo;
  }
  return { usePool: false, token: initToken() };
}

// ── 기존 사용자 탐색 (38%) ──
export function browseFlow(data) {
  const token = getToken(data);
  if (!token) { sleep(5); return; }

  group('탐색 - 프로필/라이프스타일', () => {
    getProfile(token);
    sleep(0.3);
    getLifestyle(token);
  });
  sleep(1);

  group('탐색 - 집 노트 목록', () => {
    const page = listHomeNotes(token, null);
    sleep(2);

    if (page && page.hasNext && page.next_cursor) {
      listHomeNotes(token, page.next_cursor);
    }
  });
  sleep(1);

  group('탐색 - 체크리스트 열람', () => {
    const page = listHomeNotes(token, null);
    if (page && page.items && page.items.length > 0) {
      const idx = Math.floor(Math.random() * page.items.length);
      getChecklist(token, page.items[idx].home_note_id);
    }
  });
  sleep(2);
}

// ── 매물 게시판 탐색 (22%) [NEW] ──
const PROPERTY_SEARCH_PRESETS = [
  {},
  { rent_type: ['MONTHLY'] },
  { rent_type: ['JEONSE'] },
  { rent_type: ['JEONSE_MONTHLY'] },
  { property_type: ['STUDIO'] },
  { property_type: ['MULTI_ROOM'] },
  { is_verified: true },
  { rent_type: ['MONTHLY'], property_type: ['STUDIO'] },
];

export function propertyBrowseFlow(data) {
  const token = getToken(data);
  if (!token) { sleep(5); return; }

  const filter = PROPERTY_SEARCH_PRESETS[__VU % PROPERTY_SEARCH_PRESETS.length];

  group('매물 탐색 - 목록 조회', () => {
    const page = listPropertyPosts(token, null);
    sleep(1.5);

    if (page && page.hasNext && page.next_cursor) {
      listPropertyPosts(token, page.next_cursor);
      sleep(1);
    }
  });

  group('매물 탐색 - 검색/필터링', () => {
    countPropertyPosts(token, filter);
    sleep(0.5);
    const result = searchPropertyPosts(token, filter, null);
    sleep(2);

    if (result && result.property_post_items && result.property_post_items.length > 0) {
      const idx = Math.floor(Math.random() * result.property_post_items.length);
      const postId = result.property_post_items[idx].property_post_id;

      group('매물 탐색 - 상세 조회 및 스크랩', () => {
        getPropertyPost(token, postId);
        sleep(1.5);

        // 40% 확률로 스크랩 추가 후 바로 해제
        if (Math.random() < 0.4) {
          addPropertyPostBookmark(token, postId);
          sleep(0.5);
          listBookmarkedPropertyPosts(token, null);
          sleep(1);
          removePropertyPostBookmark(token, postId);
          sleep(0.5);
        }
      });
    }
  });
  sleep(1);
}

// ── 체크리스트 집중 사용 (17%) ──
export function checklistFlow(data) {
  const token = getToken(data);
  if (!token) { sleep(5); return; }
  sleep(0.5);

  const noteData = createHomeNote(token, `현장점검 ${Date.now()}`);
  if (!noteData || !noteData.home_note_id) return;

  const homeNoteId = noteData.home_note_id;

  try {
    group('체크리스트 - 조회 및 토글', () => {
      const cl = getChecklist(token, homeNoteId);
      sleep(1);

      if (cl && cl.checklist_items) {
        const count = Math.min(cl.checklist_items.length, 8);
        for (let i = 0; i < count; i++) {
          toggleChecklistItem(token, homeNoteId, cl.checklist_items[i].checklist_item_id, true);
          sleep(0.5 + Math.random());
        }
      }
    });
    sleep(1);
  } finally {
    deleteHomeNote(token, homeNoteId);
    sleep(0.5);
  }
}

// ── 집 노트 CRUD (11%) ──
// browseFlow에서 체크리스트 열람 시 listHomeNotes를 다시 호출하는 것은
// 실제 앱에서 목록 화면으로 돌아왔을 때 새로고침하는 패턴을 반영합니다.
export function crudFlow(data) {
  const token = getToken(data);
  if (!token) { sleep(5); return; }
  sleep(0.5);

  const titles = ['역삼동 투룸', '강남 오피스텔', '합정 빌라', '성수 복층'];
  const title = titles[Math.floor(Math.random() * titles.length)];

  group('CRUD - 생성 및 수정', () => {
    const note = createHomeNote(token, `${title} ${Date.now()}`);
    if (!note || !note.home_note_id) return;

    try {
      sleep(1);
      updateHomeNoteTitle(token, note.home_note_id, `${title} (수정)`);
      sleep(0.5);

      listHomeNotes(token, null);
      sleep(2);
    } finally {
      deleteHomeNote(token, note.home_note_id);
    }
  });
  sleep(1);
}

// ── 신규 가입 (5%) ──
export function onboardingFlow(data) {
  const token = getToken(data);
  if (!token) { sleep(5); return; }
  sleep(1);

  group('온보딩 - 초기 설정', () => {
    setNickname(token, `nu${String(Date.now()).slice(-8)}`);
    sleep(0.5);

    createLifestyle(token, ['채광', '역세권', '조용한 환경']);
  });
  sleep(1);
}

// ── 파일 업로드 (4%) ──
export function uploadFlow(data) {
  const token = getToken(data);
  if (!token) { sleep(5); return; }
  sleep(0.5);

  const noteData = createHomeNote(token, `사진첨부 ${Date.now()}`);
  if (!noteData || !noteData.home_note_id) return;

  try {
    group('업로드 - 풀 사이클', () => {
      const imgIdx = Math.floor(Math.random() * PROPERTY_IMAGES.length);
      const imgData = PROPERTY_IMAGES[imgIdx];
      const preset = [
        { file_type: 'IMAGE', content_type: 'image/jpeg', file_name: `photo${imgIdx + 1}.jpg`, size_bytes: imgData.byteLength },
      ];

      const presignedData = getFilePresignedUrls(token, noteData.home_note_id, preset);
      if (presignedData && presignedData.file_items && presignedData.file_items.length > 0) {
        const item = presignedData.file_items[0];
        const uploaded = uploadToS3(item.presigned_url, 'image/jpeg', imgData);

        if (uploaded) {
          const completeItems = [{ file_asset_id: item.file_asset_id, metadata: { width: 1080, height: 1920 } }];
          completeFileUploadV2(token, completeItems);
          attachFilesToHomeNote(token, noteData.home_note_id, [item.file_asset_id]);
        }
      }
    });
    sleep(1);
  } finally {
    deleteHomeNote(token, noteData.home_note_id);
    sleep(0.5);
  }
}

// ── 매물 등록/관리 (3%) [NEW] ──
export function propertyPostFlow(data) {
  const token = getToken(data);
  if (!token) { sleep(5); return; }
  sleep(0.5);

  const POST_PRESETS = [
    {
      title: '역세권 원룸',
      easy_contract_id: null,
      address_main: '서울시 강동구 천호대로 888',
      address_detail: '101동 1001호',
      price_main: 50000000,
      price_monthly: 500000,
      content: '풀옵션 원룸입니다. 역에서 도보 3분 거리.',
      property_type: 'STUDIO',
      rent_type: 'MONTHLY',
      exclusive_area_m2: 19.5,
      is_basement: false,
      floor: 5,
      maintenance_fee: 70000,
    },
    {
      title: '조용한 투룸',
      easy_contract_id: null,
      address_main: '서울시 마포구 서교동 123-4',
      address_detail: '',
      price_main: 200000000,
      price_monthly: 0,
      content: '전세 투룸. 주차 가능.',
      property_type: 'MULTI_ROOM',
      rent_type: 'JEONSE',
      exclusive_area_m2: 33.0,
      is_basement: false,
      floor: 3,
      maintenance_fee: 50000,
    },
  ];

  const preset = POST_PRESETS[__VU % POST_PRESETS.length];

  group('매물 등록 - 생성 및 관리', () => {
    const postData = createPropertyPost(token, { ...preset, title: `${preset.title} ${Date.now()}` });
    if (!postData || !postData.property_post_id) return;

    const postId = postData.property_post_id;

    try {
      sleep(1);

      // 상세 조회
      getPropertyPost(token, postId);
      sleep(0.5);

      // 내용 수정
      updatePropertyPost(token, postId, {
        title: `${preset.title} (수정됨)`,
        price_main: preset.price_main,
        price_monthly: preset.price_monthly,
        content: `${preset.content} (수정)`,
      });
      sleep(0.5);

      // 거래 상태 변경 (TRADING 유지)
      updatePropertyPostDealStatus(token, postId, 'TRADING');
      sleep(0.5);
    } finally {
      deletePropertyPost(token, postId);
      sleep(0.5);
    }
  });
  sleep(1);
}

export default function () {}
