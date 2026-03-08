/**
 * 시나리오 7: 스파이크 테스트
 *
 * 갑작스러운 트래픽 급증(마케팅 이벤트, 푸시 알림 발송 등)에 대한 시스템 내성을 측정합니다.
 * 짧은 시간 내에 부하가 급격히 증가했다가 감소하는 패턴을 시뮬레이션합니다.
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
  listHomeNotes,
  getChecklist,
  getLifestyle,
  createHomeNote,
  deleteHomeNote,
} from '../helpers.js';

export const options = {
  scenarios: {
    spike: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 10 },
        { duration: '1m', target: 300 },
        { duration: '4m', target: 300 },
        { duration: '1m', target: 10 },
        { duration: '2m', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<10000'],
    http_req_failed: ['rate<0.15'],
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

  sleep(1);
}
