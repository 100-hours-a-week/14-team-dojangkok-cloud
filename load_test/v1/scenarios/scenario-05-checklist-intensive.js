/**
 * 시나리오 5: 체크리스트 집중 사용 플로우
 *
 * 흐름: (인증) → 집 노트 생성 → 체크리스트 조회 → 항목 개별 토글(반복)
 *       → 체크리스트 전체 수정 → 재조회
 *
 * 사용자가 실제 집을 보면서 체크리스트를 하나씩 체크하는 시나리오입니다.
 * 짧은 간격으로 반복되는 PATCH 요청이 서버에 주는 부하를 측정합니다.
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
  getChecklist,
  toggleChecklistItem,
  updateChecklist,
  deleteHomeNote,
} from '../helpers.js';

export const options = {
  scenarios: {
    checklist_intensive: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 300 },
        { duration: '6m', target: 300 },
        { duration: '2m', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    ...THRESHOLDS,
    'http_req_duration{name:GET /home-notes/{id}/checklists}': ['p(95)<1500'],
    'http_req_duration{name:PATCH /checklists/items/{id}}': ['p(95)<800'],
    'http_req_duration{name:PUT /home-notes/{id}/checklists}': ['p(95)<2000'],
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
  const vuId = __VU;

  // Step 1: 집 노트 생성
  const noteData = createHomeNote(token, `체크리스트테스트 ${vuId}-${Date.now()}`);
  if (!noteData || !noteData.home_note_id) {
    return;
  }

  const homeNoteId = noteData.home_note_id;
  sleep(1);

  // Step 2: 체크리스트 조회
  const checklistData = getChecklist(token, homeNoteId);
  sleep(1);

  if (!checklistData || !checklistData.checklist_items || checklistData.checklist_items.length === 0) {
    deleteHomeNote(token, homeNoteId);
    return;
  }

  const items = checklistData.checklist_items;

  // Step 3: 항목 개별 토글 (하나씩 체크)
  for (let i = 0; i < items.length; i++) {
    toggleChecklistItem(token, homeNoteId, items[i].checklist_item_id, true);
    sleep(0.3 + Math.random() * 1.2);
  }

  sleep(2);

  // Step 4: 일부 항목 체크 해제
  const uncheckedCount = Math.min(3, Math.floor(items.length / 3));
  for (let i = 0; i < uncheckedCount; i++) {
    const randomIdx = Math.floor(Math.random() * items.length);
    toggleChecklistItem(token, homeNoteId, items[randomIdx].checklist_item_id, false);
    sleep(0.5);
  }

  // Step 5: 체크리스트 전체 수정 (일괄 저장)
  const updatedItems = items.map((item, idx) => ({
    checklist_item_id: item.checklist_item_id,
    content: item.content,
    is_completed: idx < Math.floor(items.length * 0.7),
  }));

  updateChecklist(token, homeNoteId, updatedItems);
  sleep(1);

  // Step 6: 최종 확인
  getChecklist(token, homeNoteId);
  sleep(1);

  // Step 7: 정리
  deleteHomeNote(token, homeNoteId);
  sleep(0.5);
}
