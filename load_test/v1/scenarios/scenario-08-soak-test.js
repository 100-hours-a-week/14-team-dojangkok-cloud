/**
 * 시나리오 8: 내구성(Soak) 테스트
 *
 * 장시간 일정 부하를 유지하여 메모리 누수, 커넥션 풀 고갈, 로그 디스크 증가 등
 * 시간이 지남에 따라 나타나는 문제를 탐지합니다.
 *
 * 30분 ~ 1시간 이상 실행을 권장합니다.
 * 환경변수 SOAK_DURATION으로 지속 시간을 조절할 수 있습니다.
 *
 * 주의: 토큰 만료(30분)보다 긴 테스트를 실행할 경우,
 *       토큰 풀에 여러 토큰을 준비하거나,
 *       서버 측에서 테스트 토큰의 만료 시간을 늘려야 합니다.
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
  getLifestyle,
  listHomeNotes,
  getChecklist,
  createHomeNote,
  updateHomeNoteTitle,
  toggleChecklistItem,
  deleteHomeNote,
} from '../helpers.js';

const soakDuration = __ENV.SOAK_DURATION || '50m';

export const options = {
  scenarios: {
    soak_test: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '5m', target: 50 },            // ramp-up
        { duration: soakDuration, target: 50 },     // 장시간 유지 (기본 50분)
        { duration: '5m', target: 0 },              // ramp-down
      ],
      gracefulRampDown: '1m',
    },
  },
  thresholds: {
    ...THRESHOLDS,
    http_req_duration: ['p(95)<3000', 'p(99)<5000'],
    http_req_failed: ['rate<0.02'],
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

  const action = Math.random();

  if (action < 0.4) {
    group('Soak - 탐색', () => {
      getProfile(token);
      sleep(0.5);
      getLifestyle(token);
      sleep(0.5);
      const page = listHomeNotes(token, null);
      if (page && page.items && page.items.length > 0) {
        const idx = Math.floor(Math.random() * page.items.length);
        getChecklist(token, page.items[idx].home_note_id);
      }
    });
  } else if (action < 0.7) {
    group('Soak - 체크리스트', () => {
      const note = createHomeNote(token, `내구성 ${Date.now()}`);
      if (note && note.home_note_id) {
        const cl = getChecklist(token, note.home_note_id);
        if (cl && cl.checklist_items && cl.checklist_items.length > 0) {
          const items = cl.checklist_items;
          for (let i = 0; i < Math.min(3, items.length); i++) {
            toggleChecklistItem(token, note.home_note_id, items[i].checklist_item_id, true);
            sleep(0.3);
          }
        }
        deleteHomeNote(token, note.home_note_id);
      }
    });
  } else {
    group('Soak - CRUD', () => {
      const note = createHomeNote(token, `내구성CRUD ${Date.now()}`);
      if (note && note.home_note_id) {
        sleep(0.5);
        updateHomeNoteTitle(token, note.home_note_id, `수정됨 ${Date.now()}`);
        sleep(0.5);
        listHomeNotes(token, null);
        sleep(0.5);
        deleteHomeNote(token, note.home_note_id);
      }
    });
  }

  sleep(2 + Math.random() * 3);
}
