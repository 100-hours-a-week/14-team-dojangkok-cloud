/**
 * 시나리오 7: 매물 게시글 CRUD + 파일 업로드 플로우 [NEW - v2 전용]
 *
 * 흐름: (인증) → 매물 게시글 생성 → Presigned URL 발급 → S3 실제 업로드
 *       → 업로드 완료 처리 → 매물에 이미지 첨부 → (50%) 파일 1건 삭제
 *       → 상세 조회 → 내용 수정 → 거래 상태 변경(TRADING)
 *       → 나의 매물 목록 조회(거래중/숨김/거래완료) → 숨김 처리 → 숨김 해제 → 삭제
 *
 * 매물 판매자가 매물을 등록하고 관리하는 전체 라이프사이클을 시뮬레이션합니다.
 * property_type 다양성: STUDIO / MULTI_ROOM / OFFICETEL 를 VU별로 순환합니다.
 *
 * 주요 측정 대상:
 *   - POST /property-posts 매물 생성 응답 시간
 *   - POST /property-posts/files/presigned-urls Presigned URL 발급 응답 시간
 *   - PUT S3 presigned-upload 실제 파일 업로드 응답 시간
 *   - POST /property-posts/files/complete 업로드 완료 처리 응답 시간
 *   - POST /property-posts/{id}/files 파일 첨부 응답 시간
 *   - DELETE /property-posts/files/{id} 첨부 파일 개별 삭제 응답 시간
 *   - GET /property-posts/{id} 상세 조회 응답 시간
 *   - PATCH /property-posts/{id} 수정 응답 시간
 *   - PATCH /property-posts/{id}/deal-status 거래 상태 변경 응답 시간
 *   - GET /property-posts/trading 거래 중 목록 조회 응답 시간
 *   - GET /property-posts/hidden 숨김 매물 목록 조회 응답 시간
 *   - GET /property-posts/completed 거래 완료 매물 목록 조회 응답 시간
 *   - PATCH /property-posts/{id}/post-status 노출 상태 변경 응답 시간
 *   - DELETE /property-posts/{id} 삭제 응답 시간
 *
 * 인증: tokens.json 또는 ACCESS_TOKENS 환경변수로 토큰 풀 사용 (권장)
 *       ACCESS_TOKEN 환경변수로 단일 토큰 사용 (fallback)
 */
import { sleep } from 'k6';
import { THRESHOLDS } from '../../config.js';
import { initTokenPool, getToken } from '../../token-pool.js';
import {
  initToken,
  createPropertyPost,
  getPropertyPost,
  updatePropertyPost,
  deletePropertyPost,
  getPropertyPostPresignedUrls,
  uploadToS3,
  completePropertyPostFileUpload,
  attachFilesToPropertyPost,
  updatePropertyPostDealStatus,
  updatePropertyPostVisibility,
  listTradingPropertyPosts,
  listHiddenPropertyPosts,
  listCompletedPropertyPosts,
  deletePropertyPostFile,
} from '../../helpers.js';

// init 단계에서 매물 사진 이미지 5장 모두 로드
const PROPERTY_IMAGES = [
  open('../../test-files/property-1.jpg', 'b'),
  open('../../test-files/property-2.jpg', 'b'),
  open('../../test-files/property-3.jpg', 'b'),
  open('../../test-files/property-4.jpg', 'b'),
  open('../../test-files/property-5.jpg', 'b'),
];

export const options = {
  scenarios: {
    property_post_crud: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 150 },
        { duration: '6m', target: 150 },
        { duration: '2m', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    ...THRESHOLDS,
    'http_req_duration{name:POST /property-posts}': ['p(95)<3000'],
    'http_req_duration{name:POST /property-posts/files/presigned-urls}': ['p(95)<3000'],
    'http_req_duration{name:PUT S3 presigned-upload}': ['p(95)<10000'],
    'http_req_duration{name:POST /property-posts/files/complete}': ['p(95)<2000'],
    'http_req_duration{name:POST /property-posts/{id}/files}': ['p(95)<2000'],
    'http_req_duration{name:DELETE /property-posts/files/{id}}': ['p(95)<1500'],
    'http_req_duration{name:GET /property-posts/{id}}': ['p(95)<1500'],
    'http_req_duration{name:PATCH /property-posts/{id}}': ['p(95)<1500'],
    'http_req_duration{name:PATCH /property-posts/{id}/deal-status}': ['p(95)<1000'],
    'http_req_duration{name:GET /property-posts/trading}': ['p(95)<2000'],
    'http_req_duration{name:GET /property-posts/hidden}': ['p(95)<2000'],
    'http_req_duration{name:GET /property-posts/completed}': ['p(95)<2000'],
    'http_req_duration{name:PATCH /property-posts/{id}/post-status}': ['p(95)<1000'],
    'http_req_duration{name:DELETE /property-posts/{id}}': ['p(95)<2000'],
  },
};

// 매물 유형 프리셋 — property_type 다양성 보장 (STUDIO / MULTI_ROOM / OFFICETEL)
const POST_PRESETS = [
  {
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
    address_main: '서울시 마포구 서교동 123-4',
    address_detail: '',
    price_main: 200000000,
    price_monthly: 0,
    content: '전세 투룸. 주차 가능. 학교 근처.',
    property_type: 'MULTI_ROOM',
    rent_type: 'JEONSE',
    exclusive_area_m2: 33.0,
    is_basement: false,
    floor: 3,
    maintenance_fee: 50000,
  },
  {
    address_main: '서울시 서초구 서초대로 100',
    address_detail: '오피스텔',
    price_main: 150000000,
    price_monthly: 600000,
    content: '강남역 도보 5분. 신축 오피스텔. 반전세.',
    property_type: 'OFFICETEL',
    rent_type: 'JEONSE_MONTHLY',
    exclusive_area_m2: 26.4,
    is_basement: false,
    floor: 12,
    maintenance_fee: 120000,
  },
];

/**
 * 매 iteration마다 property-1~5.jpg 중 최소 1장, 최대 5장을 랜덤 선택합니다.
 * 인덱스를 섞어 순서도 무작위로 만듭니다.
 */
function pickRandomImages() {
  const count = 1 + Math.floor(Math.random() * PROPERTY_IMAGES.length); // 1~5
  const indices = [0, 1, 2, 3, 4].sort(() => Math.random() - 0.5).slice(0, count);
  return indices.map((i) => ({
    fileData: PROPERTY_IMAGES[i],
    fileItem: {
      file_type: 'IMAGE',
      content_type: 'image/jpeg',
      file_name: `property-${i + 1}.jpg`,
      size_bytes: PROPERTY_IMAGES[i].byteLength,
    },
  }));
}

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

  const preset = POST_PRESETS[vuId % POST_PRESETS.length];

  // Step 1: 매물 게시글 생성
  const postData = createPropertyPost(token, {
    ...preset,
    easy_contract_id: null,
    title: `${preset.address_main.split(' ')[2] || '매물'} 테스트 ${vuId}-${iterId}`,
  });

  if (!postData || !postData.property_post_id) {
    return;
  }

  const postId = postData.property_post_id;

  try {
    sleep(0.5);

    // Step 2~5: 이미지 파일 랜덤 선택 후 업로드 (최소 1장, 최대 5장)
    const selectedImages = pickRandomImages();
    const fileItems = selectedImages.map((s) => s.fileItem);

    // Step 2: Presigned URL 발급
    const presignedData = getPropertyPostPresignedUrls(token, fileItems);
    if (presignedData && presignedData.file_items && presignedData.file_items.length > 0) {
      sleep(0.3);

      // Step 3: S3에 실제 이미지 업로드 (각 파일에 해당하는 이미지 데이터 사용)
      const fileAssetIds = [];
      for (let i = 0; i < presignedData.file_items.length; i++) {
        const item = presignedData.file_items[i];
        const fileData = selectedImages[i].fileData;
        const uploaded = uploadToS3(item.presigned_url, 'image/jpeg', fileData);
        if (uploaded) {
          fileAssetIds.push(item.file_asset_id);
        }
      }
      sleep(0.3);

      if (fileAssetIds.length > 0) {
        // Step 4: 업로드 완료 처리
        const completeItems = presignedData.file_items
          .filter((item) => fileAssetIds.includes(item.file_asset_id))
          .map((item) => ({
            file_asset_id: item.file_asset_id,
            metadata: { width: 1080, height: 1920 },
          }));
        completePropertyPostFileUpload(token, completeItems);
        sleep(0.3);

        // Step 5: 매물에 이미지 첨부
        attachFilesToPropertyPost(token, postId, fileAssetIds);
        sleep(0.5);

        // Step 5-1: 이미지가 2장 이상인 경우 첫 번째 파일 삭제 (파일 교체 패턴)
        if (fileAssetIds.length >= 2) {
          deletePropertyPostFile(token, fileAssetIds[0]);
          sleep(0.3);
        }
      }
    }

    // Step 6: 매물 상세 조회 (업로드 결과 확인)
    getPropertyPost(token, postId);
    sleep(1);

    // Step 7: 매물 내용 수정
    updatePropertyPost(token, postId, {
      title: `${preset.address_main.split(' ')[2] || '매물'} 테스트 ${vuId}-${iterId} (수정됨)`,
      price_main: preset.price_main,
      price_monthly: preset.price_monthly,
      content: `${preset.content} (수정된 내용)`,
    });
    sleep(1);

    // Step 8: 거래 상태 '거래 중' 설정 후 나의 매물 - 거래중 목록 확인
    updatePropertyPostDealStatus(token, postId, 'TRADING');
    sleep(0.5);
    listTradingPropertyPosts(token, null);
    sleep(1);

    // Step 9: 숨김 처리 → 숨김 목록 확인 → 게시 복구
    updatePropertyPostVisibility(token, postId, true);
    sleep(0.5);
    listHiddenPropertyPosts(token, null);
    sleep(0.5);
    updatePropertyPostVisibility(token, postId, false);
    sleep(0.5);

    // Step 10: 나의 매물 - 거래완료 목록 조회 (다른 사용자들의 완료 매물 확인 패턴)
    listCompletedPropertyPosts(token, null);
    sleep(0.5);
  } finally {
    // Step 11: 매물 삭제 (테스트 데이터 정리)
    deletePropertyPost(token, postId);
    sleep(1);
  }
}
