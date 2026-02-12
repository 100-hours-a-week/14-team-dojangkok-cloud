# 시나리오 5: 체크리스트 집중 사용 - 점검 기록

## 목적

사용자가 실제 집을 보면서 **체크리스트를 하나씩 체크하는 패턴**의 부하를 측정한다.
시나리오 3에서 최대 5개 항목만 토글하는 것과 달리, 전체 22개 항목을 순차적으로 토글하여
**짧은 간격으로 반복되는 PATCH 요청이 서버에 주는 쓰기 부하**를 집중 측정하는 시나리오이다.

측정 목표:
- 체크리스트 개별 토글(PATCH) 반복 시 응답 시간 및 안정성 확인
- 시나리오 3(일반 CRUD, 최대 5개 토글)과의 쓰기 부하 비교
- DB row-level lock 경합 여부 확인

## 테스트 흐름

```
집 노트 생성 → sleep(1s) → 체크리스트 조회 → sleep(1s)
→ [항목 개별 토글 × 22개, 각 sleep(0.3~1.5s)] → sleep(2s)
→ [일부 항목 해제 × 3개, 각 sleep(0.5s)]
→ 체크리스트 전체 수정 (일괄 저장) → sleep(1s) → 체크리스트 재조회 → sleep(1s)
→ 집 노트 삭제 → sleep(0.5s)
```

### API 호출 상세

| 순서 | API | 메서드 | 설명 |
|------|-----|--------|------|
| 1 | `/api/v1/home-notes` | POST | 집 노트 생성 |
| 2 | `/api/v1/home-notes/{id}/checklists` | GET | 체크리스트 조회 (항목 목록 확보) |
| 3 | `/api/v1/home-notes/{id}/checklists/items/{itemId}` | PATCH | 항목 개별 토글 × 22회 (전체 체크) |
| 4 | `/api/v1/home-notes/{id}/checklists/items/{itemId}` | PATCH | 일부 항목 해제 × 3회 |
| 5 | `/api/v1/home-notes/{id}/checklists` | PUT | 체크리스트 전체 수정 (일괄 저장) |
| 6 | `/api/v1/home-notes/{id}/checklists` | GET | 최종 확인 조회 |
| 7 | `/api/v1/home-notes/{id}` | DELETE | 집 노트 삭제 (테스트 데이터 정리) |

### 이터레이션당 요청 분포

| API | 호출 수 | 비고 |
|-----|---------|------|
| POST /home-notes | 1 | 집 노트 생성 |
| GET /home-notes/{id}/checklists | 2 | 조회 + 최종확인 |
| PATCH /checklists/items/{id} | 25 | 전체 토글 22 + 해제 3 |
| PUT /home-notes/{id}/checklists | 1 | 일괄 수정 |
| DELETE /home-notes/{id} | 1 | 데이터 정리 |
| **합계** | **30** | |

### 부하 프로파일 (ramping-vus)

| 단계 | 시간 | VU 수 | 설명 |
|------|------|-------|------|
| Ramp-up | 2분 | 0 → 300 | 점진적 증가 |
| Steady | 6분 | 300 | 최대 부하 유지 |
| Ramp-down | 2분 | 300 → 0 | 점진적 감소 |

총 테스트 시간: **10분**, gracefulRampDown: 30s

## 시나리오 3과의 차이점

| 항목 | 시나리오 3 (집 노트 CRUD) | 시나리오 5 (체크리스트 집중) |
|------|--------------------------|---------------------------|
| 체크리스트 토글 횟수 | 최대 5개 | 전체 22개 + 해제 3개 = 25회 |
| 체크리스트 일괄 수정 | 없음 | 있음 (PUT) |
| 제목 수정 (PATCH) | 있음 | 없음 |
| 집 노트 목록 조회 | 있음 | 없음 |
| 이터레이션당 API 호출 | ~10건 | 30건 |
| sleep 패턴 | 고정 | 토글 간 랜덤 sleep (0.3~1.5s) |
| 측정 초점 | 일반 CRUD 성능 | PATCH 반복 쓰기 부하 |

## 특이사항

- **PATCH 집중 패턴**: 이터레이션당 25회의 PATCH 요청 → 전체 요청의 83%가 쓰기 작업
- **랜덤 sleep**: 토글 간 `sleep(0.3 + Math.random() * 1.2)` → 실제 사용자가 항목을 하나씩 체크하는 패턴 모사
- **일괄 수정**: 개별 토글 후 PUT으로 전체 수정 수행 → 70% 완료 상태로 일괄 저장
- **데이터 자동 정리**: 이터레이션 마지막에 집 노트 삭제 수행
- **단일 토큰**: 동일 사용자로 300 VU 실행 → 같은 사용자의 서로 다른 집 노트에 대한 동시 체크리스트 조작
- Rate Limit **비활성화 상태**에서 테스트 (단일 토큰 사용으로 인한 제약)

## 성공 기준 (thresholds)

| 지표 | 기준 |
|------|------|
| 전체 http_req_duration p(95) | < 3000ms |
| 전체 http_req_duration p(99) | < 5000ms |
| http_req_failed rate | < 5% |
| GET /home-notes/{id}/checklists p(95) | < 1500ms |
| PATCH /checklists/items/{id} p(95) | < 800ms |
| PUT /home-notes/{id}/checklists p(95) | < 2000ms |

## 실행 조건

### 실행 명령

```bash
# 단일 토큰 사용
ACCESS_TOKEN=<토큰> ./run.sh 5

# 토큰 풀 사용 (tokens.json 또는 환경변수)
ACCESS_TOKENS="token1,token2,token3" ./run.sh 5
```

## 수정 이력 (테스트 중 발견)

### VU 수 조정

| 항목 | 변경 전 | 변경 후 | 사유 |
|------|---------|---------|------|
| VU 수 | 100 | 300 | 1차(100 VU) 실행 시 서버 여력 충분하여 증가 |

- 1차(100 VU): p(95) 125ms, 요청 속도 80.74 req/s → 서버 여력 충분
- 2차(300 VU): p(95) 569ms, 요청 속도 192.70 req/s → threshold 여유 있게 통과
- **300 VU를 시나리오 5의 확정 VU로 채택**
