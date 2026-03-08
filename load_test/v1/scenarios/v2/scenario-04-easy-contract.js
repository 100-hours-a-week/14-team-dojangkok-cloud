/**
 * 시나리오 4: 쉬운 계약서 파일 업로드 풀 사이클
 *
 * 흐름: (인증) → Presigned URL 발급 → S3 실제 업로드
 *       → 업로드 완료 처리 → 쉬운 계약서 생성(OCR) → 목록/상세 조회 → 삭제
 *
 * 쉬운 계약서는 핵심 기능이므로 S3 업로드와 OCR 처리를 포함한 풀 사이클 테스트.
 * OCR 외부 서비스 rate limit(2초/1건)을 고려하여 VU 수를 최소한으로 설정.
 *
 * 쉬운 계약서 생성 API 포맷 (v2):
 *   { "files": [{ "doc_type": "CONTRACT"|"REGISTRY", "file_asset_ids": [id] }] }
 *
 * 테스트 파일: /test-files/ 디렉토리에 준비 필요
 *   - test-contract.jpg    (계약서 이미지)
 *   - test-registry-1.jpg  (등기부등본 이미지 1/3)
 *   - test-registry-2.jpg  (등기부등본 이미지 2/3)
 *   - test-registry-3.jpg  (등기부등본 이미지 3/3)
 *
 * 인증: tokens.json 또는 ACCESS_TOKENS 환경변수로 토큰 풀 사용 (권장)
 *       ACCESS_TOKEN 환경변수로 단일 토큰 사용 (fallback)
 */
import { sleep } from 'k6';
import { THRESHOLDS } from '../../config.js';
import { initTokenPool, getToken } from '../../token-pool.js';
import {
  initToken,
  getEasyContractPresignedUrls,
  uploadToS3,
  completeEasyContractFileUpload,
  createEasyContract,
  listEasyContracts,
  getEasyContract,
} from '../../helpers.js';

// init 단계에서 바이너리 파일 로드
const testContractImg = open('../../test-files/test-contract.jpg', 'b');
const testRegistryImg1 = open('../../test-files/test-registry-1.jpg', 'b');
const testRegistryImg2 = open('../../test-files/test-registry-2.jpg', 'b');
const testRegistryImg3 = open('../../test-files/test-registry-3.jpg', 'b');

export const options = {
  scenarios: {
    easy_contract_file_upload: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 1 },
        { duration: '6m', target: 1 },
        { duration: '2m', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    ...THRESHOLDS,
    'http_req_duration{name:POST /easy-contracts/files/presigned-urls}': ['p(95)<3000'],
    'http_req_duration{name:PUT S3 presigned-upload}': ['p(95)<10000'],
    'http_req_duration{name:POST /easy-contracts/files/complete}': ['p(95)<2000'],
    'http_req_duration{name:POST /easy-contracts}': ['p(95)<60000'], // OCR 처리로 응답 시간 김
    'http_req_duration{name:GET /easy-contracts}': ['p(95)<2000'],
    'http_req_duration{name:GET /easy-contracts/{id}}': ['p(95)<2000'],
  },
};

/**
 * 업로드 프리셋: 각 VU가 라운드 로빈으로 다른 문서 조합을 테스트
 * _doc_type: 서버 요청 시 doc_type으로 매핑되는 내부 필드 (Presigned URL 요청에는 미포함)
 */
const UPLOAD_PRESETS = [
  // 계약서 이미지 1장
  {
    file_items: [
      { file_type: 'IMAGE', content_type: 'image/jpeg', file_name: 'contract.jpg', size_bytes: testContractImg.byteLength, _doc_type: 'CONTRACT' },
    ],
  },
  // 등기부등본 이미지 3장
  {
    file_items: [
      { file_type: 'IMAGE', content_type: 'image/jpeg', file_name: 'registry-1.jpg', size_bytes: testRegistryImg1.byteLength, _doc_type: 'REGISTRY' },
      { file_type: 'IMAGE', content_type: 'image/jpeg', file_name: 'registry-2.jpg', size_bytes: testRegistryImg2.byteLength, _doc_type: 'REGISTRY' },
      { file_type: 'IMAGE', content_type: 'image/jpeg', file_name: 'registry-3.jpg', size_bytes: testRegistryImg3.byteLength, _doc_type: 'REGISTRY' },
    ],
  },
  // 계약서 이미지 + 등기부등본 이미지 3장
  {
    file_items: [
      { file_type: 'IMAGE', content_type: 'image/jpeg', file_name: 'contract.jpg', size_bytes: testContractImg.byteLength, _doc_type: 'CONTRACT' },
      { file_type: 'IMAGE', content_type: 'image/jpeg', file_name: 'registry-1.jpg', size_bytes: testRegistryImg1.byteLength, _doc_type: 'REGISTRY' },
      { file_type: 'IMAGE', content_type: 'image/jpeg', file_name: 'registry-2.jpg', size_bytes: testRegistryImg2.byteLength, _doc_type: 'REGISTRY' },
      { file_type: 'IMAGE', content_type: 'image/jpeg', file_name: 'registry-3.jpg', size_bytes: testRegistryImg3.byteLength, _doc_type: 'REGISTRY' },
    ],
  },
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

  // Step 1: 업로드 프리셋 선택
  const preset = UPLOAD_PRESETS[vuId % UPLOAD_PRESETS.length];
  // Presigned URL 요청용 file_items (_doc_type 필드 제외)
  const fileItemsForRequest = preset.file_items.map(({ _doc_type, ...rest }) => rest);

  // Step 2: Presigned URL 발급
  const presignedData = getEasyContractPresignedUrls(token, fileItemsForRequest);
  if (!presignedData || !presignedData.file_items || presignedData.file_items.length === 0) {
    sleep(2);
    return;
  }
  sleep(0.3);

  // Step 3: S3에 실제 파일 업로드
  const registryFiles = [testRegistryImg1, testRegistryImg2, testRegistryImg3];
  let registryIdx = 0;
  for (let i = 0; i < presignedData.file_items.length; i++) {
    const item = presignedData.file_items[i];
    let fileData;
    if (preset.file_items[i]._doc_type === 'REGISTRY') {
      fileData = registryFiles[registryIdx++];
    } else {
      fileData = testContractImg;
    }
    const uploaded = uploadToS3(item.presigned_url, 'image/jpeg', fileData);
    if (!uploaded) {
      sleep(2);
      return;
    }
  }
  sleep(0.3);

  // Step 4: 업로드 완료 처리
  const completeItems = presignedData.file_items.map((item) => ({
    file_asset_id: item.file_asset_id,
    metadata: { width: 1080, height: 1920 },
  }));
  completeEasyContractFileUpload(token, completeItems);
  sleep(0.3);

  // Step 5: 쉬운 계약서 생성 (OCR 포함 — 응답 시간 길 수 있음)
  // doc_type별로 file_asset_ids 묶기
  const filesByDocType = {};
  preset.file_items.forEach(({ _doc_type }, i) => {
    if (!filesByDocType[_doc_type]) filesByDocType[_doc_type] = [];
    filesByDocType[_doc_type].push(presignedData.file_items[i].file_asset_id);
  });
  const files = Object.entries(filesByDocType).map(([doc_type, file_asset_ids]) => ({ doc_type, file_asset_ids }));

  const contractData = createEasyContract(token, files);
  if (!contractData || !contractData.easy_contract_id) {
    sleep(2);
    return;
  }
  const easyContractId = contractData.easy_contract_id;
  sleep(2);

  // Step 6: 목록 및 상세 조회
  // OCR 처리는 비동기로 수 분 소요 — 이 시점에서는 PROCESSING 상태일 수 있음
  // 삭제 로직 없음: PROCESSING 중인 계약서를 즉시 삭제하는 것은 비현실적이므로 제거.
  // 테스트 후 생성된 계약서는 수동으로 정리 필요.
  listEasyContracts(token, null);
  sleep(1);
  getEasyContract(token, easyContractId);
  sleep(2); // OCR rate limit 대비 간격
}
