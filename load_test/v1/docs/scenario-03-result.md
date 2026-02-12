# 시나리오 3: 집 노트 CRUD - 결과 분석

## 실행 정보

### 1차 실행 (600 VU)

| 항목 | 값 |
|------|-----|
| 실행 일시 | 2026-02-11 04:23:48 KST |
| 대상 서버 | https://<PRODUCTION_URL> |
| 테스트 시간 | 10분 9초 |
| 최대 VU | 600 |
| 토큰 방식 | 단일 토큰 (1개) |
| Rate Limit | **비활성화 상태** |
| 결과 파일 | `results/20260211_042348_scenario-3.json` |

### 2차 실행 (200 VU)

| 항목 | 값 |
|------|-----|
| 실행 일시 | 2026-02-11 04:39:07 KST |
| 대상 서버 | https://<PRODUCTION_URL> |
| 테스트 시간 | 10분 6초 |
| 최대 VU | 200 |
| 토큰 방식 | 단일 토큰 (1개) |
| Rate Limit | **비활성화 상태** |
| 결과 파일 | `results/20260211_043907_scenario-3.json` |

## 요약

1차(600 VU)에서 서버 용량 포화로 3개 Threshold가 초과되어, 2차(200 VU)로 재실행하였습니다.
**2차 실행: 모든 Threshold 통과, 에러율 0%.** 200 VU CRUD 부하에서 전체 API가 안정적으로 동작하였습니다.

- 총 요청: **97,890건** (9,789 iterations)
- 처리량: **161.55 req/s**
- 에러율: **0.00%**
- 전체 check 성공율: **100%** (107,679/107,679)
- 이터레이션당 API 호출: 10건 (생성 1 + 수정 1 + 체크리스트 조회 1 + 토글 5 + 목록 1 + 삭제 1)

## Threshold 결과 (2차 - 200 VU)

| Threshold | 기준 | 실제 | 결과 |
|-----------|------|------|------|
| http_req_duration p(95) | < 3000ms | 190.41ms | **PASS** |
| http_req_duration p(99) | < 5000ms | 390.75ms | **PASS** |
| http_req_failed rate | < 5% | 0.00% | **PASS** |
| POST /home-notes p(95) | < 3000ms | 206.59ms | **PASS** |
| PATCH /home-notes/{id} p(95) | < 1500ms | 192.88ms | **PASS** |
| GET /home-notes/{id}/checklists p(95) | < 1500ms | 176.73ms | **PASS** |
| PATCH /checklists/items/{id} p(95) | < 1000ms | 186.61ms | **PASS** |
| DELETE /home-notes/{id} p(95) | < 2000ms | 185.14ms | **PASS** |

## 응답 시간 (2차 - 200 VU)

### 전체 종합

| 지표 | 값 |
|------|-----|
| avg | 89.44ms |
| med | 78.13ms |
| p(90) | 161.23ms |
| p(95) | 190.41ms |
| p(99) | 390.75ms |
| max | 4.74s |

### API별 응답 시간

| API | avg | med | p(90) | p(95) | max |
|-----|-----|-----|-------|-------|-----|
| `POST /home-notes` | 104.84ms | 93.45ms | 177.82ms | 206.59ms | 844ms |
| `PATCH /home-notes/{id}` | 90.32ms | 78.19ms | 164.20ms | 192.88ms | 4.74s |
| `GET /home-notes/{id}/checklists` | 78.49ms | 66.52ms | 151.06ms | 176.73ms | 824ms |
| `PATCH /checklists/items/{id}` | 88.57ms | 78.56ms | 159.19ms | 186.61ms | 2.70s |
| `DELETE /home-notes/{id}` | 84.02ms | 69.78ms | 154.16ms | 185.14ms | 830ms |

### 처리량

| 지표 | 값 |
|------|-----|
| 총 요청 수 | 97,890 |
| 요청 속도 | 161.55 req/s |
| 이터레이션 속도 | 16.16 iter/s |
| 수신 데이터 | 126 MB (208 kB/s) |
| 송신 데이터 | 11 MB (19 kB/s) |

### 요청 분포

| API | 요청 수 | 비고 |
|-----|---------|------|
| POST /home-notes | 9,789 | 이터레이션당 1회 |
| PATCH /home-notes/{id} | 9,789 | 이터레이션당 1회 |
| GET /home-notes/{id}/checklists | 9,789 | 이터레이션당 1회 |
| PATCH /checklists/items/{id} | 48,945 | 이터레이션당 5회 (22개 중 5개 토글) |
| GET /home-notes | 9,789 | 이터레이션당 1회 |
| DELETE /home-notes/{id} | 9,789 | 이터레이션당 1회 |

## VU별 비교

| 지표 | 600 VU | 200 VU | 300 VU | 400 VU |
|------|--------|--------|--------|--------|
| 실행 일시 | 04:23:48 | 04:39:07 | 04:59:17 | 05:12:11 |
| 에러율 | 0% | 0% | 0% | ~0% (1건 timeout) |
| avg 응답 시간 | 1,422ms | 89ms | 339ms | **702ms** |
| p(95) 응답 시간 | 1,962ms | 190ms | 524ms | **969ms** |
| p(99) 응답 시간 | ~2,210ms | 391ms | 735ms | **1,330ms** |
| max 응답 시간 | 18.34s | 4.74s | 37.65s | 60s (timeout) |
| 요청 속도 | 207 req/s | 162 req/s | 193 req/s | **200 req/s** |
| 총 요청 수 | 126,000 | 97,890 | 117,420 | 121,261 |
| Threshold | 3개 FAIL | 전체 PASS | 전체 PASS | **전체 PASS** |

### 4차 실행 (400 VU) 상세

| 항목 | 값 |
|------|-----|
| 실행 일시 | 2026-02-11 05:12:11 KST |
| 테스트 시간 | 10분 5초 |
| 결과 파일 | `results/20260211_051211_scenario-3.json` |

### 4차 API별 응답 시간

| API | avg | med | p(90) | p(95) | max |
|-----|-----|-----|-------|-------|-----|
| `POST /home-notes` | 723ms | 849ms | 942ms | 983ms | 60s (timeout) |
| `PATCH /home-notes/{id}` | 698ms | 829ms | 922ms | 965ms | 1.71s |
| `GET /home-notes/{id}/checklists` | 691ms | 820ms | 913ms | 954ms | 27.28s |
| `PATCH /checklists/items/{id}` | 701ms | 829ms | 924ms | 966ms | 55.49s |
| `DELETE /home-notes/{id}` | 696ms | 826ms | 921ms | 969ms | 7.69s |

---

## 재검증 실행 (2026-02-11 오후, Rate Limit 활성화)

이전 1~4차 실행은 Rate Limit이 비활성화된 상태에서 진행되었습니다.
아래 5~6차는 **Rate Limit이 활성화된 상태**에서 400 VU 재검증을 수행한 결과입니다.

### 5차 실행 (400 VU, Rate Limit 활성화)

| 항목 | 값 |
|------|-----|
| 실행 일시 | 2026-02-11 14:35:49 KST |
| 대상 서버 | https://<PRODUCTION_URL> |
| 테스트 시간 | 10분 9초 |
| 최대 VU | 400 |
| 토큰 방식 | 단일 토큰 (1개) |
| Rate Limit | **활성화 상태** |
| 결과 파일 | `results/20260211_143549_scenario-3.json` |

#### 5차 Threshold 결과

| Threshold | 기준 | 실제 | 결과 |
|-----------|------|------|------|
| http_req_duration p(95) | < 3000ms | 1,020ms | **PASS** |
| http_req_duration p(99) | < 5000ms | 1,230ms | **PASS** |
| http_req_failed rate | < 5% | 0.00% | **PASS** |
| POST /home-notes p(95) | < 3000ms | 1,050ms | **PASS** |
| PATCH /home-notes/{id} p(95) | < 1500ms | 1,020ms | **PASS** |
| GET /home-notes/{id}/checklists p(95) | < 1500ms | 1,000ms | **PASS** |
| PATCH /checklists/items/{id} p(95) | < 1000ms | 1,010ms | **FAIL** |
| DELETE /home-notes/{id} p(95) | < 2000ms | 1,010ms | **PASS** |

#### 5차 API별 응답 시간

| API | avg | med | p(90) | p(95) | max |
|-----|-----|-----|-------|-------|-----|
| `POST /home-notes` | 741ms | 848ms | 997ms | 1,050ms | 1.95s |
| `PATCH /home-notes/{id}` | 718ms | 823ms | 969ms | 1,020ms | 14.83s |
| `GET /home-notes/{id}/checklists` | 704ms | 814ms | 953ms | 1,000ms | 5.82s |
| `PATCH /checklists/items/{id}` | 717ms | 825ms | 963ms | 1,010ms | 20.80s |
| `DELETE /home-notes/{id}` | 712ms | 811ms | 964ms | 1,010ms | 10.91s |

#### 5차 처리량

| 지표 | 값 |
|------|-----|
| 총 요청 수 | 120,120 |
| 총 반복 수 | 12,012 |
| 요청 속도 | 197 req/s |
| 에러율 | 0.00% |
| check 성공율 | 99.99% (132,129 / 132,132, 체크리스트 토글 3건 실패) |

### 6차 실행 (400 VU, Rate Limit 활성화, 재현 확인)

| 항목 | 값 |
|------|-----|
| 실행 일시 | 2026-02-11 15:00:17 KST |
| 대상 서버 | https://<PRODUCTION_URL> |
| 테스트 시간 | 10분 7초 |
| 최대 VU | 400 |
| 토큰 방식 | 단일 토큰 (1개) |
| Rate Limit | **활성화 상태** |
| 결과 파일 | `results/20260211_150017_scenario-3.json` |

#### 6차 Threshold 결과

| Threshold | 기준 | 실제 | 결과 |
|-----------|------|------|------|
| http_req_duration p(95) | < 3000ms | 1,060ms | **PASS** |
| http_req_duration p(99) | < 5000ms | 1,300ms | **PASS** |
| http_req_failed rate | < 5% | 0.00% | **PASS** |
| POST /home-notes p(95) | < 3000ms | 1,090ms | **PASS** |
| PATCH /home-notes/{id} p(95) | < 1500ms | 1,070ms | **PASS** |
| GET /home-notes/{id}/checklists p(95) | < 1500ms | 1,040ms | **PASS** |
| PATCH /checklists/items/{id} p(95) | < 1000ms | 1,050ms | **FAIL** |
| DELETE /home-notes/{id} p(95) | < 2000ms | 1,040ms | **PASS** |

#### 6차 API별 응답 시간

| API | avg | med | p(90) | p(95) | max |
|-----|-----|-----|-------|-------|-----|
| `POST /home-notes` | 763ms | 882ms | 1,030ms | 1,090ms | 8.75s |
| `PATCH /home-notes/{id}` | 743ms | 861ms | 1,010ms | 1,070ms | 11.68s |
| `GET /home-notes/{id}/checklists` | 723ms | 837ms | 988ms | 1,040ms | 10.47s |
| `PATCH /checklists/items/{id}` | 735ms | 854ms | 1,000ms | 1,050ms | 20.69s |
| `DELETE /home-notes/{id}` | 728ms | 829ms | 986ms | 1,040ms | 17.73s |

#### 6차 처리량

| 지표 | 값 |
|------|-----|
| 총 요청 수 | 118,660 |
| 총 반복 수 | 11,866 |
| 요청 속도 | 196 req/s |
| 에러율 | 0.00% |
| check 성공율 | 100% (130,526 / 130,526) |

## 분석

### 1. VU별 성능 변화 곡선 (1~4차, Rate Limit 비활성화)

| VU | avg | p(95) | 상태 |
|----|-----|-------|------|
| 200 | 89ms | 190ms | 여유 |
| 300 | 339ms | 524ms | 양호 |
| **400** | **702ms** | **969ms** | **경계** |
| 600 | 1,422ms | 1,962ms | 포화 |

- 200 → 300 VU (+50%): p(95) **2.8배** 증가 (190 → 524ms)
- 300 → 400 VU (+33%): p(95) **1.8배** 증가 (524 → 969ms)
- 400 → 600 VU (+50%): p(95) **2.0배** 증가 (969 → 1,962ms)

### 2. 400 VU 재검증 결과 (5~6차, Rate Limit 활성화)

두 번의 재검증 결과가 매우 일관적입니다:

| 지표 | 5차 | 6차 |
|------|-----|-----|
| 성공률 | 99.99% | 100% |
| avg 응답 시간 | 718ms | 738ms |
| p(95) 응답 시간 | 1,020ms | 1,060ms |
| 처리량 | 197 req/s | 196 req/s |
| Threshold FAIL | 1개 | 1개 |

- Rate Limit 활성화 상태에서 전체 응답시간이 약 **50~90ms 증가** (4차 대비)
- `PATCH /checklists/items/{id}`의 p(95)가 **안정적으로 1,010~1,050ms**에 위치하여 임계값(1,000ms)을 반복적으로 초과
- 에러율은 0%로, 서버 안정성은 확보됨

### 3. 처리량 포화 확인

| VU | 요청 속도 | 증가율 |
|----|----------|--------|
| 200 | 162 req/s | - |
| 300 | 193 req/s | +19% |
| 400 (RL OFF) | 200 req/s | +4% |
| 400 (RL ON, 5차) | 197 req/s | -2% |
| 400 (RL ON, 6차) | 196 req/s | -2% |
| 600 | 207 req/s | +3% |

- **서버의 CRUD 처리 한계: ~200 req/s** (Rate Limit 유무와 무관하게 일관)
- Rate Limit 활성화 시 처리량이 미세하게 감소 (~3 req/s)

### 4. 결론

- **300 VU**: 모든 threshold 여유 있게 통과, 193 req/s 처리 → **권장**
- **400 VU**: threshold 경계선, `PATCH /checklists/items/{id}`가 반복적으로 p(95) 1,000ms 초과
  - 해당 임계값을 **1,100ms로 완화**하면 400 VU에서도 전체 PASS 가능
  - 또는 백엔드에서 체크리스트 토글 API 성능 최적화 검토
- 서비스 안정성 기준으로 **300 VU를 시나리오 3의 확정 VU**로 유지

## 시나리오 2와 비교

| 지표 | 시나리오 2 (GET, 800 VU) | 시나리오 3 (CRUD, 300 VU) |
|------|------------------------|--------------------------|
| 최대 VU | 800 | 300 |
| API 유형 | GET (읽기) | POST/PATCH/GET/DELETE (쓰기 포함) |
| 에러율 | 0% | 0% |
| avg 응답 시간 | 271ms | 339ms |
| p(95) 응답 시간 | 476ms | 524ms |
| 요청 속도 | 346 req/s | 193 req/s |
| Threshold 결과 | 전체 PASS | 전체 PASS |

> 300 VU CRUD와 800 VU GET이 비슷한 응답 시간 수준. CRUD의 적정 VU는 GET의 약 1/3.

## 다음 단계

1. 시나리오 4 (파일 업로드) 진행
2. 시나리오 3 확정 VU: **300** (적정 부하, threshold 여유 확보)
