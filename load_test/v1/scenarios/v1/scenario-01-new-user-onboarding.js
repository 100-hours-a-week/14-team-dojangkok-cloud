/**
 * 시나리오 1: 신규 사용자 온보딩 플로우
 *
 * 흐름: (인증) → 닉네임 설정 → 라이프스타일 등록
 *
 * 신규 가입자가 앱에 처음 진입하여 초기 설정을 완료하는 과정을 시뮬레이션합니다.
 * 이 시나리오는 가입 이벤트(마케팅 캠페인 등)로 신규 유입이 몰릴 때의 부하를 측정합니다.
 *
 * 인증: tokens.json 또는 ACCESS_TOKENS 환경변수로 토큰 풀 사용 (권장)
 *       ACCESS_TOKEN 환경변수로 단일 토큰 사용 (fallback)
 */
import { sleep } from 'k6';
import { THRESHOLDS } from '../config.js';
import { initTokenPool, getToken } from '../token-pool.js';
import {
  initToken,
  setNickname,
  createLifestyle,
} from '../helpers.js';

export const options = {
  scenarios: {
    new_user_onboarding: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 100 },
        { duration: '6m', target: 100 },
        { duration: '2m', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    ...THRESHOLDS,
    'http_req_duration{name:PATCH /members/nickname}': ['p(95)<1000'],
    'http_req_duration{name:POST /lifestyles}': ['p(95)<5000'],
  },
};

const LIFESTYLE_PRESETS = [
  ['반려동물 고양이 한 마리', '채광', '비흡연'],
  ['반려동물 강아지 한 마리', '주차 필수', '조용한 환경'],
  ['1인 가구', '역세권', '편의시설 근처'],
  ['신혼부부', '넓은 거실', '학교 근처'],
  ['자취생', '월세 저렴', '교통 편리'],
];

// setup()은 테스트 시작 시 1회만 실행되며, 반환값이 모든 VU에 공유됩니다.
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

  // Step 1: 닉네임 설정
  const nickname = `u${vuId}_${iterId}`;
  setNickname(token, nickname);
  sleep(0.5);

  // Step 2: 라이프스타일 등록
  const lifestyleItems = LIFESTYLE_PRESETS[vuId % LIFESTYLE_PRESETS.length];
  createLifestyle(token, lifestyleItems);
  sleep(2);
}
