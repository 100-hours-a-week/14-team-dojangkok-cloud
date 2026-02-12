/**
 * 시나리오 3: 집 노트 CRUD 플로우
 *
 * 흐름: (인증) → 집 노트 생성 → 제목 수정 → 체크리스트 조회 → 체크리스트 항목 토글(여러 개)
 *       → 집 노트 목록 확인 → 집 노트 삭제
 *
 * 사용자가 집을 보러 다니며 노트를 작성하고 체크리스트를 활용하는 핵심 비즈니스 흐름입니다.
 * 쓰기 작업이 포함되어 있어 DB 부하를 측정하는 데 중요합니다.
 *
 * 인증: tokens.json 또는 ACCESS_TOKENS 환경변수로 토큰 풀 사용 (권장)
 *       ACCESS_TOKEN 환경변수로 단일 토큰 사용 (fallback)
 */
import { sleep } from 'k6';
import { THRESHOLDS } from '../config.js';
import { initTokenPool, getToken } from '../token-pool.js';
import {
  initToken,
  createHomeNote,
  updateHomeNoteTitle,
  getChecklist,
  toggleChecklistItem,
  listHomeNotes,
  deleteHomeNote,
} from '../helpers.js';

export const options = {
  scenarios: {
    home_note_crud: {
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
    'http_req_duration{name:POST /home-notes}': ['p(95)<3000'],
    'http_req_duration{name:PATCH /home-notes/{id}}': ['p(95)<1500'],
    'http_req_duration{name:GET /home-notes/{id}/checklists}': ['p(95)<1500'],
    'http_req_duration{name:PATCH /checklists/items/{id}}': ['p(95)<1000'],
    'http_req_duration{name:DELETE /home-notes/{id}}': ['p(95)<2000'],
  },
};

const ROOM_NAMES = [
  '강남역 오피스텔', '천호동 원룸', '잠실 투룸', '홍대 빌라',
  '성수동 복층', '마포 아파트', '판교 원룸', '광화문 오피스텔',
  '역삼동 쓰리룸', '합정 빌라', '건대 원룸', '신촌 투룸',
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
  const iterId = __ITER;

  // Step 1: 집 노트 생성
  const roomName = ROOM_NAMES[Math.floor(Math.random() * ROOM_NAMES.length)];
  const title = `${roomName} ${vuId}-${iterId}`;
  const noteData = createHomeNote(token, title);

  if (!noteData || !noteData.home_note_id) {
    return;
  }

  const homeNoteId = noteData.home_note_id;

  try {
    sleep(1);

    // Step 2: 제목 수정
    const updatedTitle = `${title} (수정됨)`;
    updateHomeNoteTitle(token, homeNoteId, updatedTitle);
    sleep(0.5);

    // Step 3: 체크리스트 조회
    const checklistData = getChecklist(token, homeNoteId);
    sleep(1);

    // Step 4: 체크리스트 항목 토글
    if (checklistData && checklistData.checklist_items) {
      const items = checklistData.checklist_items;
      const itemsToToggle = Math.min(items.length, 5);

      for (let i = 0; i < itemsToToggle; i++) {
        toggleChecklistItem(token, homeNoteId, items[i].checklist_item_id, true);
        sleep(0.5);
      }
    }
    sleep(1);

    // Step 5: 목록으로 돌아가 확인
    listHomeNotes(token, null);
    sleep(2);
  } finally {
    // Step 6: 집 노트 삭제 (테스트 데이터 정리 겸 삭제 부하 측정)
    // 에러가 발생해도 반드시 실행되어 데이터를 정리합니다.
    deleteHomeNote(token, homeNoteId);
    sleep(1);
  }
}
