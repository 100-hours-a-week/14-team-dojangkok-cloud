# 시나리오 2: 기존 사용자 탐색 - 점검 기록

## 목적

이미 가입된 사용자가 앱에 재접속하여 기존 데이터를 열람하는 **가장 일반적인 사용 패턴**의 부하를 측정한다.
모든 요청이 GET(조회)이므로 단일 토큰으로도 유의미한 성능 데이터를 얻을 수 있다.

## 테스트 흐름

```
프로필 조회 → sleep(0.3s) → 라이프스타일 확인 → sleep(1s) → 집 노트 목록 → sleep(2s) → [페이지네이션] → sleep(1.5s) → [체크리스트 조회] → sleep(2s) → sleep(1s)
```

### API 호출 상세

| 순서 | API | 메서드 | 설명 |
|------|-----|--------|------|
| 1 | `/api/v1/members/me` | GET | 프로필 조회 (앱 초기 화면) |
| 2 | `/api/v1/lifestyles` | GET | 라이프스타일 확인 |
| 3 | `/api/v1/home-notes` | GET | 집 노트 목록 (메인 화면) |
| 4 | `/api/v1/home-notes?cursor=...` | GET | 페이지네이션 (다음 페이지, 조건부) |
| 5 | `/api/v1/home-notes/{id}/checklists` | GET | 체크리스트 조회 (상세 진입, 조건부) |

### 부하 프로파일 (ramping-vus)

| 단계 | 시간 | VU 수 | 설명 |
|------|------|-------|------|
| Ramp-up | 2분 | 0 → 800 | 점진적 증가 |
| Steady | 6분 | 800 | 최대 부하 유지 |
| Ramp-down | 2분 | 800 → 0 | 점진적 감소 |

총 테스트 시간: **10분**, gracefulRampDown: 30s

## 단건 테스트 결과

| API | 상태 | 비고 |
|-----|------|------|
| `GET /members/me` | 200 | 정상 |
| `GET /lifestyles` | 200 | 정상 |
| `GET /home-notes` | 200 | 집 노트 4건 반환, hasNext=false |

페이지네이션/체크리스트 조회는 집 노트 데이터에 의존하여 조건부 실행됨.

## 한계점

- 단일 토큰으로 800 VU 실행 → 동일 사용자의 동일 데이터를 반복 조회하므로 DB 캐시 히트율이 실제보다 높을 수 있음
- hasNext=false이므로 페이지네이션(Step 4)은 실행되지 않을 가능성이 높음
- Rate Limit **비활성화 상태**에서 테스트 (단일 토큰 사용으로 인한 제약)

## 성공 기준 (thresholds)

| 지표 | 기준 |
|------|------|
| 전체 http_req_duration p(95) | < 3000ms |
| 전체 http_req_duration p(99) | < 5000ms |
| http_req_failed rate | < 5% |
| GET /members/me p(95) | < 1000ms |
| GET /lifestyles p(95) | < 1000ms |
| GET /home-notes p(95) | < 2000ms |
| GET /home-notes/{id}/checklists p(95) | < 1500ms |
