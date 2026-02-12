/**
 * 시나리오 4b: 쉬운 계약서 파일 업로드 풀 사이클
 *
 * 흐름: (인증) → Presigned URL 발급 → S3 실제 업로드
 *       → 업로드 완료 처리 → 쉬운 계약서 생성 (OCR) → 정리(삭제)
 *
 * OCR Rate Limit (2초/1건) 고려하여 VU 수를 낮게 설정.
 *
 * 인증: tokens.json 또는 ACCESS_TOKENS 환경변수로 토큰 풀 사용 (권장)
 *       ACCESS_TOKEN 환경변수로 단일 토큰 사용 (fallback)
 */
import { sleep } from 'k6';
import { THRESHOLDS } from '../config.js';
import { initTokenPool, getToken } from '../token-pool.js';
import {
  initToken,
  getEasyContractPresignedUrls,
  uploadToS3,
  completeEasyContractFileUpload,
  createEasyContract,
  listEasyContracts,
  getEasyContract,
  deleteEasyContract,
} from '../helpers.js';

// init 단계에서 바이너리 파일 로드
const testImageData = open('../test-files/test-image.jpg', 'b');
const testPdfData = open('../test-files/test-doc.pdf', 'b');

export const options = {
  scenarios: {
    easy_contract_file_upload: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 10 },
        { duration: '6m', target: 10 },
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
  },
};

// 쉬운 계약서용 업로드 프리셋 (계약서 이미지/PDF)
const UPLOAD_PRESETS = [
  // 단일 이미지
  [{ file_type: 'IMAGE', content_type: 'image/jpeg', file_name: 'contract_photo.jpg', size_bytes: testImageData.byteLength }],
  // PDF 1건
  [{ file_type: 'PDF', content_type: 'application/pdf', file_name: 'contract.pdf', size_bytes: testPdfData.byteLength }],
  // 이미지 2장
  [
    { file_type: 'IMAGE', content_type: 'image/jpeg', file_name: 'contract_p1.jpg', size_bytes: testImageData.byteLength },
    { file_type: 'IMAGE', content_type: 'image/jpeg', file_name: 'contract_p2.jpg', size_bytes: testImageData.byteLength },
  ],
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

  // Step 1: 업로드할 파일 세트 선택
  const preset = UPLOAD_PRESETS[vuId % UPLOAD_PRESETS.length];

  // Step 2: Presigned URL 발급 (쉬운 계약서 전용 경로)
  const presignedData = getEasyContractPresignedUrls(token, preset);
  if (!presignedData || !presignedData.file_items || presignedData.file_items.length === 0) {
    sleep(2);
    return;
  }
  sleep(0.3);

  // Step 3: S3에 실제 파일 업로드
  const fileAssetIds = [];
  for (const item of presignedData.file_items) {
    // 응답에 content_type이 없으므로 file_key로 판별
    const isPdf = item.file_key && item.file_key.startsWith('pdf/');
    const fileData = isPdf ? testPdfData : testImageData;
    const contentType = isPdf ? 'application/pdf' : 'image/jpeg';
    const uploaded = uploadToS3(item.presigned_url, contentType, fileData);
    if (!uploaded) {
      sleep(2);
      return;
    }
    fileAssetIds.push(item.file_asset_id);
  }
  sleep(0.3);

  // Step 4: 업로드 완료 처리 (쉬운 계약서 전용 경로)
  const completeItems = presignedData.file_items.map((item) => ({
    file_asset_id: item.file_asset_id,
    metadata: (item.file_key && item.file_key.startsWith('pdf/'))
      ? { width: 0, height: 0 }
      : { width: 1080, height: 1920 },
  }));
  completeEasyContractFileUpload(token, completeItems);
  sleep(0.3);

  // Step 5: 쉬운 계약서 생성 (OCR 포함 — 응답 시간 길 수 있음)
  const contractData = createEasyContract(token, fileAssetIds);
  if (!contractData || !contractData.easy_contract_id) {
    return;
  }
  const easyContractId = contractData.easy_contract_id;
  sleep(2);

  // Step 6: 목록 및 상세 조회 (시나리오 09의 로직 통합)
  listEasyContracts(token, null);
  sleep(1);
  getEasyContract(token, easyContractId);
  sleep(1);

  // Step 7: 정리 — 생성된 계약서 삭제
  deleteEasyContract(token, easyContractId);
  sleep(2); // OCR rate limit 대비 간격
}
