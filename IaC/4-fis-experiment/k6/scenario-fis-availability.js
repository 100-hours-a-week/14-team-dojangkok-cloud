/**
 * FIS 실험용 가용성 측정 시나리오
 *
 * V3 scenario-chaos-availability.js 기반, 독립 실행 가능하도록 수정:
 * - helpers.js/config.js/token-pool.js 의존 제거
 * - ACCESS_TOKEN 환경변수로 단일 토큰 사용
 * - BASE_URL 환경변수로 ALB DNS 지정
 *
 * 실행:
 *   BASE_URL=http://<ALB_DNS> ACCESS_TOKEN=<token> k6 run scenario-fis-availability.js
 *   또는 인증 없이 health check만:
 *   BASE_URL=http://<ALB_DNS> k6 run scenario-fis-availability.js
 */
import { sleep } from 'k6';
import http from 'k6/http';
import { Counter, Trend } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost';
const ACCESS_TOKEN = __ENV.ACCESS_TOKEN || '';
const DURATION = __ENV.DURATION || '20m';
const VUS = parseInt(__ENV.VUS || '30');

// Status code counters
const s401 = new Counter('chaos_status_401');
const s403 = new Counter('chaos_status_403');
const s404 = new Counter('chaos_status_404');
const s502 = new Counter('chaos_status_502');
const s503 = new Counter('chaos_status_503');
const s504 = new Counter('chaos_status_504');
const connErr = new Counter('chaos_conn_errors');

function track(res) {
  if (!res || res.error_code) { connErr.add(1); return res; }
  if (res.status === 401) s401.add(1);
  if (res.status === 403) s403.add(1);
  if (res.status === 404) s404.add(1);
  if (res.status === 502) s502.add(1);
  if (res.status === 503) s503.add(1);
  if (res.status === 504) s504.add(1);
  return res;
}

function headers() {
  const h = { 'Content-Type': 'application/json' };
  if (ACCESS_TOKEN) h['Authorization'] = `Bearer ${ACCESS_TOKEN}`;
  return h;
}

// API calls
function healthCheck() {
  return track(http.get(`${BASE_URL}/actuator/health`, {
    tags: { name: 'GET /actuator/health' },
  }));
}

function getProfile() {
  return track(http.get(`${BASE_URL}/api/v1/members/me`, {
    headers: headers(),
    tags: { name: 'GET /members/me' },
  }));
}

function listHomeNotes() {
  return track(http.get(`${BASE_URL}/api/v1/home-notes`, {
    headers: headers(),
    tags: { name: 'GET /home-notes' },
  }));
}

function searchPropertyPosts() {
  return track(http.post(`${BASE_URL}/api/v2/property-posts/searches`,
    JSON.stringify({}), {
    headers: headers(),
    tags: { name: 'POST /property-posts/searches' },
  }));
}

// k6 config
export const options = {
  scenarios: {
    fis_traffic: {
      executor: 'constant-vus',
      vus: VUS,
      duration: DURATION,
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(99)<5000'],
    chaos_status_502: ['count<20'],
    chaos_status_503: ['count<20'],
    chaos_status_504: ['count<50'],
    chaos_conn_errors: ['count<10'],
  },
};

function pickAction() {
  if (!ACCESS_TOKEN) return 'health';
  const r = Math.random() * 100;
  if (r < 30) return 'health';
  if (r < 55) return 'profile';
  if (r < 80) return 'homeNotes';
  return 'propertySearch';
}

export default function () {
  const action = pickAction();

  switch (action) {
    case 'health':
      healthCheck();
      break;
    case 'profile':
      getProfile();
      break;
    case 'homeNotes':
      listHomeNotes();
      break;
    case 'propertySearch':
      searchPropertyPosts();
      break;
  }

  sleep(0.5 + Math.random());
}
