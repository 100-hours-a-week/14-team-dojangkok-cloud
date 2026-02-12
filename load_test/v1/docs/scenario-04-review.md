# 시나리오 4: 파일 업로드 - 점검 기록

## 목적

사용자가 **파일을 업로드하는 전체 파이프라인**(Presigned URL 발급 → S3 업로드 → 완료 처리 → 첨부/생성)의 부하를 측정한다.
S3 외부 서비스와의 연동이 포함되어 있어 네트워크 I/O와 서버 후처리 성능을 함께 확인하는 시나리오이다.

두 가지 하위 시나리오로 구성된다:
- **04a**: 집 노트 파일 업로드 풀 사이클 (150 VU)
- **04b**: 쉬운 계약서 파일 업로드 풀 사이클, OCR 포함 (10 VU)

---

## 시나리오 04a: 집 노트 파일 업로드

### 테스트 흐름

```
집 노트 생성 → sleep(0.5s) → Presigned URL 발급 → sleep(0.3s)
→ [S3 파일 업로드 × 1~2개] → sleep(0.3s) → 업로드 완료 처리 → sleep(0.3s)
→ 집 노트에 파일 첨부 → sleep(0.5s) → 집 노트 삭제 → sleep(0.5s)
```

### API 호출 상세

| 순서 | API | 메서드 | 설명 |
|------|-----|--------|------|
| 1 | `/api/v1/home-notes` | POST | 집 노트 생성 |
| 2 | `/api/v1/home-notes/{id}/files/presigned-urls` | POST | Presigned URL 발급 |
| 3 | S3 Presigned URL | PUT | S3에 파일 직접 업로드 (1~2건) |
| 4 | `/api/v1/home-notes/files/complete` | POST | 업로드 완료 처리 |
| 5 | `/api/v1/home-notes/{id}/files` | POST | 집 노트에 파일 첨부 |
| 6 | `/api/v1/home-notes/{id}` | DELETE | 집 노트 삭제 (테스트 데이터 정리) |

### 업로드 프리셋

VU ID 기반으로 라운드 로빈 선택:

| 프리셋 | 파일 구성 | S3 업로드 횟수 |
|--------|-----------|----------------|
| 1 | 이미지 1장 (JPEG) | 1회 |
| 2 | 이미지 1장 + PDF 1건 | 2회 |
| 3 | 이미지 2장 | 2회 |

### 부하 프로파일 (ramping-vus)

| 단계 | 시간 | VU 수 | 설명 |
|------|------|-------|------|
| Ramp-up | 2분 | 0 → 150 | 점진적 증가 |
| Steady | 6분 | 150 | 최대 부하 유지 |
| Ramp-down | 2분 | 150 → 0 | 점진적 감소 |

총 테스트 시간: **10분**, gracefulRampDown: 30s

### 성공 기준 (thresholds)

| 지표 | 기준 |
|------|------|
| 전체 http_req_duration p(95) | < 3000ms |
| 전체 http_req_duration p(99) | < 5000ms |
| http_req_failed rate | < 5% |
| POST /home-notes/{id}/files/presigned-urls p(95) | < 3000ms |
| PUT S3 presigned-upload p(95) | < 10000ms |
| POST /home-notes/files/complete p(95) | < 2000ms |
| POST /home-notes/{id}/files p(95) | < 2000ms |

---

## 시나리오 04b: 쉬운 계약서 파일 업로드

### 테스트 흐름

```
Presigned URL 발급 → sleep(0.3s) → [S3 파일 업로드 × 1~2개] → sleep(0.3s)
→ 업로드 완료 처리 → sleep(0.3s) → 쉬운 계약서 생성 (OCR) → sleep(2s)
→ 쉬운 계약서 목록 조회 → sleep(1s) → 쉬운 계약서 상세 조회 → sleep(1s)
→ 쉬운 계약서 삭제 → sleep(2s)
```

### API 호출 상세

| 순서 | API | 메서드 | 설명 |
|------|-----|--------|------|
| 1 | `/api/v1/easy-contracts/files/presigned-urls` | POST | Presigned URL 발급 |
| 2 | S3 Presigned URL | PUT | S3에 파일 직접 업로드 (1~2건) |
| 3 | `/api/v1/easy-contracts/files/complete` | POST | 업로드 완료 처리 |
| 4 | `/api/v1/easy-contracts` | POST | 쉬운 계약서 생성 (OCR 처리 포함) |
| 5 | `/api/v1/easy-contracts` | GET | 쉬운 계약서 목록 조회 |
| 6 | `/api/v1/easy-contracts/{id}` | GET | 쉬운 계약서 상세 조회 |
| 7 | `/api/v1/easy-contracts/{id}` | DELETE | 쉬운 계약서 삭제 (테스트 데이터 정리) |

### 업로드 프리셋

| 프리셋 | 파일 구성 | S3 업로드 횟수 |
|--------|-----------|----------------|
| 1 | 이미지 1장 (JPEG) | 1회 |
| 2 | PDF 1건 | 1회 |
| 3 | 이미지 2장 | 2회 |

### 부하 프로파일 (ramping-vus)

| 단계 | 시간 | VU 수 | 설명 |
|------|------|-------|------|
| Ramp-up | 2분 | 0 → 10 | 점진적 증가 |
| Steady | 6분 | 10 | 최대 부하 유지 |
| Ramp-down | 2분 | 10 → 0 | 점진적 감소 |

총 테스트 시간: **10분**, gracefulRampDown: 30s

> OCR Rate Limit (2초/1건)을 고려하여 VU 수를 10으로 제한

### 성공 기준 (thresholds)

| 지표 | 기준 |
|------|------|
| 전체 http_req_duration p(95) | < 3000ms |
| 전체 http_req_duration p(99) | < 5000ms |
| http_req_failed rate | < 5% |
| POST /easy-contracts/files/presigned-urls p(95) | < 3000ms |
| PUT S3 presigned-upload p(95) | < 10000ms |
| POST /easy-contracts/files/complete p(95) | < 2000ms |
| POST /easy-contracts p(95) | < 60000ms |

---

## 특이사항

- **S3 외부 의존**: Presigned URL 발급 후 S3에 직접 업로드하므로 AWS S3 네트워크 지연이 응답 시간에 포함
- **바이너리 파일 전송**: k6 `open(file, 'b')`으로 테스트 이미지/PDF를 바이너리(ArrayBuffer)로 로드하여 S3에 PUT
- **OCR 처리 (04b)**: 쉬운 계약서 생성 시 서버에서 OCR 처리 수행 → 1건당 22~76초 소요, `timeout: '120s'` 설정
- **데이터 자동 정리**: 04a는 finally 블록에서 집 노트 삭제, 04b는 계약서 삭제 수행
- **실행 방식**: `run-04ab.sh`로 04a → 30초 대기 → 토큰 재발급 → 04b 순차 실행
- **Presigned URL 응답 필드**: 집 노트용은 `data.success_file_items`, 쉬운 계약서용은 `data.file_items` (필드명 상이)
- Rate Limit **비활성화 상태** (단일 토큰 사용으로 인한 제약)

## 테스트 파일

| 파일 | 용도 |
|------|------|
| `test-files/test-image.jpg` | 이미지 업로드 테스트용 |
| `test-files/test-doc.pdf` | PDF 업로드 테스트용 |

## 실행 조건

### 실행 명령

```bash
# 04a → 04b 순차 실행 (권장)
./run-04ab.sh

# 개별 실행
ACCESS_TOKEN=<토큰> k6 run scenarios/scenario-04a-home-note-file-upload.js
ACCESS_TOKEN=<토큰> k6 run scenarios/scenario-04b-easy-contract-file-upload.js
```

## 수정 이력 (테스트 중 발견)

### API 경로 수정

| 항목 | 수정 전 (잘못된 경로) | 수정 후 (올바른 경로) |
|------|----------------------|---------------------|
| 집 노트 Presigned URL | POST `/file-assets/presigned-urls` | POST `/home-notes/{homeNoteId}/files/presigned-urls` |
| 쉬운 계약서 Presigned URL | POST `/file-assets/presigned-urls` | POST `/easy-contracts/files/presigned-urls` |
| 쉬운 계약서 업로드 완료 | POST `/home-notes/files/complete` | POST `/easy-contracts/files/complete` |

### 응답 필드 및 k6 호환성 수정

| 항목 | 수정 전 | 수정 후 | 원인 |
|------|---------|---------|------|
| 집 노트 Presigned URL 응답 | `data.file_items` | `data.success_file_items` | 서버 응답 필드명 상이 |
| 파일 크기 참조 | `testImageData.length` | `testImageData.byteLength` | k6의 `open(file, 'b')`가 ArrayBuffer 반환 |
| Content-Type 판별 | `item.content_type` 비교 | `item.file_key.startsWith('pdf/')` | 서버 응답에 content_type 필드 없음 |
