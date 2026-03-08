/**
 * 시나리오 6: 혼합 현실적 부하 테스트 (종합 시나리오)
 *
 * 실제 서비스의 트래픽 비율을 반영하여 여러 사용자 유형을 동시에 시뮬레이션합니다.
 *
 * 트래픽 비율:
 *   - 기존 사용자 탐색 (60%): 가장 빈번한 패턴
 *   - 체크리스트 사용 (20%): 집을 보러 간 사용자
 *   - 집 노트 생성/수정 (12%): 새 매물 기록
 *   - 신규 가입 (5%): 신규 유입
 *   - 파일 업로드 (3%): 사진/문서 첨부
 *
 * 인증: tokens.json 또는 ACCESS_TOKENS 환경변수로 토큰 풀 사용 (권장)
 *       ACCESS_TOKEN 환경변수로 단일 토큰 사용 (fallback)
 */
import { sleep, group } from 'k6';
import { THRESHOLDS } from '../config.js';
import { initTokenPool, getToken } from '../token-pool.js';
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
  getChecklistTemplate,
  getChecklist,
  toggleChecklistItem,
  getFilePresignedUrls,
  uploadToS3,
  completeFileUploadV2,
  attachFilesToHomeNote,
} from '../helpers.js';

// init 단계에서 바이너리 파일 로드 (업로드 흐름용)
const testImageData = open('../test-files/test-image.jpg', 'b');

export const options = {
  scenarios: {
    browse_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 600 },
        { duration: '6m', target: 600 },
        { duration: '2m', target: 0 },
      ],
      exec: 'browseFlow',
      gracefulRampDown: '30s',
    },
    checklist_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 180 },
        { duration: '6m', target: 180 },
        { duration: '2m', target: 0 },
      ],
      exec: 'checklistFlow',
      gracefulRampDown: '30s',
    },
    crud_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 120 },
        { duration: '6m', target: 120 },
        { duration: '2m', target: 0 },
      ],
      exec: 'crudFlow',
      gracefulRampDown: '30s',
    },
    new_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 45 },
        { duration: '6m', target: 45 },
        { duration: '2m', target: 0 },
      ],
      exec: 'onboardingFlow',
      gracefulRampDown: '30s',
    },
    upload_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 30 },
        { duration: '6m', target: 30 },
        { duration: '2m', target: 0 },
      ],
      exec: 'uploadFlow',
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    ...THRESHOLDS,
    'http_req_duration{name:GET /members/me}': ['p(95)<1000'],
    'http_req_duration{name:GET /home-notes}': ['p(95)<2000'],
    'http_req_duration{name:GET /home-notes/{id}/checklists}': ['p(95)<1500'],
    'http_req_duration{name:POST /home-notes}': ['p(95)<3000'],
    'http_req_duration{name:PATCH /checklists/items/{id}}': ['p(95)<1000'],
    'http_req_duration{name:PUT S3 presigned-upload}': ['p(95)<10000'],
  },
};

export function setup() {
  const poolInfo = initTokenPool();
  if (poolInfo.usePool) {
    return poolInfo;
  }
  return { usePool: false, token: initToken() };
}

// ── 기존 사용자 탐색 (60%) ──
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

// ── 체크리스트 집중 사용 (20%) ──
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

// ── 집 노트 CRUD (12%) ──
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
    setNickname(token, `newuser_${Date.now()}`);
    sleep(0.5);

    createLifestyle(token, ['채광', '역세권', '조용한 환경']);
    sleep(2);

    getChecklistTemplate(token);
  });
  sleep(1);
}

// ── 파일 업로드 (3%) ──
export function uploadFlow(data) {
  const token = getToken(data);
  if (!token) { sleep(5); return; }
  sleep(0.5);

  const noteData = createHomeNote(token, `사진첨부 ${Date.now()}`);
  if (!noteData || !noteData.home_note_id) return;

  try {
    group('업로드 - 풀 사이클', () => {
      const preset = [
        { file_type: 'IMAGE', content_type: 'image/jpeg', file_name: 'photo1.jpg', size_bytes: testImageData.byteLength }
      ];

      const presignedData = getFilePresignedUrls(token, noteData.home_note_id, preset);
      if (presignedData && presignedData.file_items && presignedData.file_items.length > 0) {
        const item = presignedData.file_items[0];
        
        // S3 실제 업로드 시뮬레이션
        const uploaded = uploadToS3(item.presigned_url, 'image/jpeg', testImageData);
        
        if (uploaded) {
          // 완료 처리
          const completeItems = [{
            file_asset_id: item.file_asset_id,
            metadata: { width: 1080, height: 1920 },
          }];
          completeFileUploadV2(token, completeItems);
          
          // 집 노트에 첨부
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

export default function () {}

