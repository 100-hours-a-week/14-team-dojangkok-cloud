/**
 * 시나리오 4a: 집 노트 파일 업로드 풀 사이클
 *
 * 흐름: (인증) → 집 노트 생성 → Presigned URL 발급 → S3 실제 업로드
 *       → 업로드 완료 처리 → 집 노트에 파일 첨부 → 정리(삭제)
 *
 * 기존 시나리오 4를 대체. 실제 S3 업로드까지 수행하는 풀 사이클.
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
  deleteHomeNote,
  getFilePresignedUrls,
  uploadToS3,
  completeFileUploadV2,
  attachFilesToHomeNote,
} from '../helpers.js';

// init 단계에서 바이너리 파일 로드
const testImageData = open('../test-files/test-image.jpg', 'b');
const testPdfData = open('../test-files/test-doc.pdf', 'b');

export const options = {
  scenarios: {
    home_note_file_upload: {
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
    'http_req_duration{name:POST /home-notes/{id}/files/presigned-urls}': ['p(95)<3000'],
    'http_req_duration{name:PUT S3 presigned-upload}': ['p(95)<10000'],
    'http_req_duration{name:POST /home-notes/files/complete}': ['p(95)<2000'],
    'http_req_duration{name:POST /home-notes/{id}/files}': ['p(95)<2000'],
  },
};

// 업로드 프리셋: 각 VU가 라운드 로빈으로 사용
const UPLOAD_PRESETS = [
  // 단일 이미지
  [{ file_type: 'IMAGE', content_type: 'image/jpeg', file_name: 'room_photo.jpg', size_bytes: testImageData.byteLength }],
  // 이미지 + PDF
  [
    { file_type: 'IMAGE', content_type: 'image/jpeg', file_name: 'room_photo.jpg', size_bytes: testImageData.byteLength },
    { file_type: 'PDF', content_type: 'application/pdf', file_name: 'contract.pdf', size_bytes: testPdfData.byteLength },
  ],
  // 이미지 2장
  [
    { file_type: 'IMAGE', content_type: 'image/jpeg', file_name: 'room1.jpg', size_bytes: testImageData.byteLength },
    { file_type: 'IMAGE', content_type: 'image/jpeg', file_name: 'room2.jpg', size_bytes: testImageData.byteLength },
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

  // Step 1: 집 노트 생성
  const noteData = createHomeNote(token, `파일테스트 ${vuId}-${Date.now()}`);
  if (!noteData || !noteData.home_note_id) {
    return;
  }
  sleep(0.5);

  try {
    // Step 2: 업로드할 파일 세트 선택
    const preset = UPLOAD_PRESETS[vuId % UPLOAD_PRESETS.length];

    // Step 3: Presigned URL 발급 (homeNoteId 포함 경로)
    const presignedData = getFilePresignedUrls(token, noteData.home_note_id, preset);
    if (!presignedData || !presignedData.file_items || presignedData.file_items.length === 0) {
      return;
    }
    sleep(0.3);

    // Step 4: S3에 실제 파일 업로드
    const fileAssetIds = [];
    for (const item of presignedData.file_items) {
      // 응답에 content_type이 없으므로 file_key로 판별
      const isPdf = item.file_key && item.file_key.startsWith('pdf/');
      const fileData = isPdf ? testPdfData : testImageData;
      const contentType = isPdf ? 'application/pdf' : 'image/jpeg';
      const uploaded = uploadToS3(item.presigned_url, contentType, fileData);
      if (!uploaded) {
        return;
      }
      fileAssetIds.push(item.file_asset_id);
    }
    sleep(0.3);

    // Step 5: 업로드 완료 처리
    const completeItems = presignedData.file_items.map((item) => ({
      file_asset_id: item.file_asset_id,
      metadata: (item.file_key && item.file_key.startsWith('pdf/'))
        ? { width: 0, height: 0 }
        : { width: 1080, height: 1920 },
    }));
    completeFileUploadV2(token, completeItems);
    sleep(0.3);

    // Step 6: 집 노트에 파일 첨부
    attachFilesToHomeNote(token, noteData.home_note_id, fileAssetIds);
    sleep(0.5);
  } finally {
    // Step 7: 정리 (에러 발생 시에도 실행)
    deleteHomeNote(token, noteData.home_note_id);
    sleep(0.5);
  }
}
