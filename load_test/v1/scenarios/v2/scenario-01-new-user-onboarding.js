/**
 * 시나리오 1: 신규 사용자 온보딩 플로우
 *
 * 흐름: (인증) → 닉네임 설정 → 프로필 조회 → 라이프스타일 등록 → 라이프스타일 조회
 *
 * 신규 가입자가 앱에 처음 진입하여 초기 설정을 완료하는 과정을 시뮬레이션합니다.
 * 이 시나리오는 가입 이벤트(마케팅 캠페인 등)로 신규 유입이 몰릴 때의 부하를 측정합니다.
 *
 * 라이프스타일 등록(POST /lifestyles)은 서버 내부적으로 AI 체크리스트 생성 작업을
 * 비동기 큐에 등록하고 즉시 응답을 반환합니다. 따라서 이 시나리오의 핵심 측정 대상은
 * 동시 다발적인 라이프스타일 등록이 AI 큐 등록 속도에 미치는 영향입니다.
 *
 * AI 체크리스트 생성 완료까지 실제로 3~5분이 소요되므로, 완료 여부 검증은
 * 이 시나리오에서 다루지 않습니다. (장시간 테스트인 시나리오 8에서 별도 검증)
 *
 * 주의: 단일 계정으로 테스트 시 동일 계정의 라이프스타일을 반복 등록하게 되며,
 *       매 호출마다 새로운 AI 작업이 큐에 쌓입니다.
 *
 * 주의: 회원 탈퇴(DELETE /members/me)는 테스트 계정 보호를 위해 의도적으로 제외합니다.
 *
 * v1 대비 변경 사항: 없음 (온보딩 플로우 동일)
 *
 * 인증: tokens.json 또는 ACCESS_TOKENS 환경변수로 토큰 풀 사용 (권장)
 *       ACCESS_TOKEN 환경변수로 단일 토큰 사용 (fallback)
 */
import { sleep } from 'k6';
import { THRESHOLDS } from '../../config.js';
import { initTokenPool, getToken } from '../../token-pool.js';
import {
  initToken,
  setNickname,
  getProfile,
  createLifestyle,
  getLifestyle,
} from '../../helpers.js';

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
    'http_req_duration{name:GET /members/me}': ['p(95)<1000'],
    'http_req_duration{name:POST /lifestyles}': ['p(95)<5000'],
    'http_req_duration{name:GET /lifestyles}': ['p(95)<1000'],
  },
};

const LIFESTYLE_PRESETS = [
  ['반려동물 고양이 한 마리', '채광', '비흡연'],
  ['반려동물 강아지 한 마리', '주차 필수', '조용한 환경'],
  ['1인 가구', '역세권', '편의시설 근처'],
  ['신혼부부', '넓은 거실', '학교 근처'],
  ['자취생', '월세 저렴', '교통 편리'],
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

  // Step 1: 닉네임 설정
  const nickname = `u${vuId}_${iterId}`;
  setNickname(token, nickname);
  sleep(0.3);

  // Step 2: 프로필 조회 — 닉네임이 정상 반영됐는지 앱이 확인하는 동작
  getProfile(token);
  sleep(0.5);

  // Step 3: 라이프스타일 등록
  // 서버 내부적으로 AI 체크리스트 생성 작업을 비동기 큐에 등록하고 즉시 응답 반환.
  // 동시 다발적 등록이 AI 큐 등록 속도에 미치는 영향이 핵심 측정 대상.
  const lifestyleItems = LIFESTYLE_PRESETS[vuId % LIFESTYLE_PRESETS.length];
  createLifestyle(token, lifestyleItems);
  sleep(0.5);

  // Step 4: 라이프스타일 조회 — 저장 반영 확인
  getLifestyle(token);
  sleep(1);
}
