# 시나리오 3: 집 노트 CRUD - 점검 기록

## 목적

사용자가 집을 보러 다니며 노트를 작성하고 체크리스트를 활용하는 **핵심 비즈니스 흐름**의 부하를 측정한다.
쓰기 작업(생성/수정/삭제)이 포함되어 있어 DB 부하를 측정하는 데 중요한 시나리오이다.

## 테스트 흐름

```
집 노트 생성 → sleep(1s) → 제목 수정 → sleep(0.5s) → 체크리스트 조회 → sleep(1s)
→ [체크리스트 항목 토글 × 최대 5개, 각 sleep(0.5s)] → sleep(1s) → 집 노트 목록 확인
→ sleep(2s) → 집 노트 삭제 → sleep(1s)
```

### API 호출 상세

| 순서 | API | 메서드 | 설명 |
|------|-----|--------|------|
| 1 | `/api/v1/home-notes` | POST | 집 노트 생성 |
| 2 | `/api/v1/home-notes/{id}` | PATCH | 제목 수정 |
| 3 | `/api/v1/home-notes/{id}/checklists` | GET | 체크리스트 조회 |
| 4 | `/api/v1/home-notes/{id}/checklists/items/{itemId}` | PATCH | 체크리스트 항목 토글 (최대 5개, 조건부) |
| 5 | `/api/v1/home-notes` | GET | 집 노트 목록 확인 |
| 6 | `/api/v1/home-notes/{id}` | DELETE | 집 노트 삭제 (테스트 데이터 정리) |

### 부하 프로파일 (ramping-vus)

| 단계 | 시간 | VU 수 | 설명 |
|------|------|-------|------|
| Ramp-up | 2분 | 0 → 400 | 점진적 증가 |
| Steady | 6분 | 400 | 최대 부하 유지 |
| Ramp-down | 2분 | 400 → 0 | 점진적 감소 |

총 테스트 시간: **10분**, gracefulRampDown: 30s

## 특이사항

- **쓰기 작업 포함**: 시나리오 2(모두 GET)와 달리 POST/PATCH/DELETE가 포함되어 DB 쓰기 부하 발생
- **데이터 자동 정리**: finally 블록에서 반드시 삭제 수행 → 테스트 후 데이터 오염 최소화
- **단일 토큰**: 같은 사용자가 집 노트를 반복 생성/삭제 → 동시성 이슈 가능성 확인 필요
- **체크리스트 토글**: 생성된 집 노트에 체크리스트 항목이 있을 때만 실행 (조건부)
- Rate Limit **비활성화 상태**에서 테스트 (단일 토큰 사용으로 인한 제약)

## 단건 테스트 결과

| API | 상태 | 비고 |
|-----|------|------|
| `POST /home-notes` | 200 | 집 노트 생성 + 체크리스트 22개 자동 생성 |
| `PATCH /home-notes/{id}` | 200 | 제목 수정 정상 |
| `GET /home-notes/{id}/checklists` | 200 | 체크리스트 항목 22개 반환 |
| `PATCH /checklists/items/{id}` | 200 | 항목 토글 정상 |
| `GET /home-notes` | 200 | 목록 조회 정상 (items, hasNext, limit, next_cursor) |
| `DELETE /home-notes/{id}` | 204 | 삭제 정상 |

집 노트 생성 시 체크리스트 22개 항목이 자동 생성됨 → 시나리오에서 최대 5개만 토글.

## 성공 기준 (thresholds)

| 지표 | 기준 |
|------|------|
| 전체 http_req_duration p(95) | < 3000ms |
| 전체 http_req_duration p(99) | < 5000ms |
| http_req_failed rate | < 5% |
| POST /home-notes p(95) | < 3000ms |
| PATCH /home-notes/{id} p(95) | < 1500ms |
| GET /home-notes/{id}/checklists p(95) | < 1500ms |
| PATCH /checklists/items/{id} p(95) | < 1000ms |
| DELETE /home-notes/{id} p(95) | < 2000ms |
