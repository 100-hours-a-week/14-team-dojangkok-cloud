# 모니터링 대시보드 이용 가이드

본 문서는 '도장콕' 서비스의 안정적인 운영과 기술적 고도화를 위해 구축된 모니터링 시스템의 활용 방법을 안내합니다.
팀원 누구나 서비스의 핵심 지표를 쉽고 빠르게 시각적으로 확인하고, 이를 통해 효율적인 문제 해결과 품질 개선을 수행할 수 있도록 지원하는 것을 목적으로 합니다.

이 가이드에서는 대시보드의 구성 요소와 각 패널의 역할, 그리고 효과적인 데이터 조회 방법을 상세히 다룹니다. 모니터링 시스템을 처음 접하는 구성원도 직관적으로 이해하고 즉시 업무에 활용할 수 있도록 작성되었습니다.

## 목차

1. [대시보드 접속 방법](#1-대시보드-접속-방법)
2. [모니터링 페이지 로그인](#2-모니터링-페이지-로그인)
3. [홈 대시보드 (Homepage)](#3-홈-대시보드-homepage)
4. [대시보드 목록 및 구성](#4-대시보드-목록-및-구성)
5. [로그 탐색 (Explore)](#5-로그-탐색-explore)
6. [실시간 로그 모니터링](#6-실시간-로그-모니터링)

## 1. 대시보드 접속 방법

대시보드 접속 방법은 별도의 보안 접속 가이드 문서에서 상세히 다루고 있습니다. 대시보드 접속이 처음이신 분들은 아래 링크를 통해 해당 문서를 먼저 확인해 주시기 바랍니다. (특히 5번 항목 참고)

[AWS 인프라 보안접속 가이드](https://github.com/100-hours-a-week/14-team-dojangkok-cloud/wiki/AWS-%EC%9D%B8%ED%94%84%EB%9D%BC-%28EC2%2C-MySQL%2C-Redis%29-%EB%B3%B4%EC%95%88%EC%A0%91%EC%86%8D-%EA%B0%80%EC%9D%B4%EB%93%9C)


## 2. 모니터링 페이지 로그인

보안 터널링 설정 후 브라우저를 통해 접속하면 아래와 같은 로그인 화면이 나타납니다.

![로그인 화면](https://raw.githubusercontent.com/100-hours-a-week/14-team-dojangkok-cloud/refs/heads/main/wiki/guide/monitoring/images/01_login.png)

1. **Email or username:** 관리자로부터 부여받은 계정 정보를 입력합니다.
2. **Password:** 해당 계정의 비밀번호를 입력합니다.
3. **Log in:** 정보를 입력한 후 버튼을 클릭하여 대시보드에 접속합니다.

> **참고:** 모니터링 계정 정보의 경우 담당자에게 문의 부탁드립니다. (@howard)


## 3. 홈 대시보드 (Homepage)

로그인에 성공하면 Grafana의 홈 화면으로 이동합니다. 이곳에서 최근 본 대시보드나 즐겨찾기한 대시보드에 빠르게 접근할 수 있습니다.

![홈페이지 화면](https://raw.githubusercontent.com/100-hours-a-week/14-team-dojangkok-cloud/refs/heads/main/wiki/guide/monitoring/images/02_homepage.png)

### 주요 구성 요소

| 영역 | 설명 |
|------|------|
| **좌측 네비게이션 바** | Home, Dashboards, Explore, Alerting 등 주요 기능으로 이동할 수 있는 메뉴 |
| **Dashboards** | 모든 모니터링 대시보드 목록을 확인하고 원하는 항목을 선택 |
| **Starred** | 자주 사용하는 대시보드를 즐겨찾기 해두면 이곳에 표시 |
| **Recently viewed dashboards** | 최근에 접속했던 대시보드 목록 |

상단의 검색창이나 좌측 메뉴의 **Dashboards**를 클릭하여, 모니터링하고자 하는 리소스의 대시보드로 이동하세요.


## 4. 대시보드 목록 및 구성

좌측 메뉴에서 **Dashboards**를 클릭하면 현재 구성된 모든 대시보드 목록을 확인할 수 있습니다.

![대시보드 목록](https://raw.githubusercontent.com/100-hours-a-week/14-team-dojangkok-cloud/refs/heads/main/wiki/guide/monitoring/images/03_dashboard.png)

### 대시보드 분류

도장콕의 대시보드는 크게 **인프라 모니터링**과 **애플리케이션 모니터링**으로 구분됩니다.

#### 인프라 모니터링

| 대시보드 | 설명 | 주요 확인 지표 |
|----------|------|----------------|
| **EC2 Instances** | AWS EC2 인스턴스 전체 현황 | CPU, Memory, Disk, Network I/O |
| **GPU Server** | GCP GPU 인스턴스 상태 | GPU 사용률, 메모리, 온도 |
| **Nginx** | 웹서버 트래픽 현황 | 요청 수, 응답 코드, 연결 수 |
| **Nginx Detail** | Nginx 상세 지표 | 상세 트래픽 분석, 에러율 |
| **MySQL** | 데이터베이스 상태 | 쿼리 수, 커넥션, 슬로우 쿼리 |
| **Redis** | 캐시 서버 상태 | 메모리 사용량, Hit/Miss 비율, 명령어 처리량 |

#### 애플리케이션 모니터링

| 대시보드 | 설명 | 주요 확인 지표 |
|----------|------|----------------|
| **Spring Boot System Monitor** | Backend 애플리케이션 상태 | JVM 메모리, GC, 스레드, HTTP 요청 |
| **JVM (Micrometer)** | JVM 상세 지표 | Heap/Non-Heap 메모리, GC 상세 |
| **FastAPI** | AI Server 애플리케이션 상태 | 요청 수, 응답 시간, 에러율 |
| **vLLM** | LLM 추론 서버 상태 | 추론 요청, 토큰 처리량, 큐 대기 |

원하는 대시보드를 클릭하여 상세 화면으로 이동할 수 있습니다.
> **참고:** 현재 제공되는 계정의 경우 대시보드 수정이 불가능합니다. 추가로 원하는 지표나 대시보드 수정이 필요한 경우 담당자에게 문의 부탁드립니다. (@howard)

## 5. 로그 탐색 (Explore)

Grafana의 **Explore** 기능을 통해 Loki에 수집된 로그를 검색하고 분석할 수 있습니다.

### 5.1 Explore 접속

좌측 메뉴에서 **Explore**를 클릭한 후, 상단의 데이터 소스 선택 드롭다운에서 **Loki**를 선택합니다.

![Loki 선택](https://raw.githubusercontent.com/100-hours-a-week/14-team-dojangkok-cloud/refs/heads/main/wiki/guide/monitoring/images/04_explore_log.png)

### 5.2 로그 검색 방법

![로그 검색](https://raw.githubusercontent.com/100-hours-a-week/14-team-dojangkok-cloud/refs/heads/main/wiki/guide/monitoring/images/05_search_log.png)

#### Step 1: Label Filter 설정

`Label filters` 섹션에서 조회하고자 하는 서비스를 선택합니다.

| Label Key | 설명 | 예시 값 |
|-----------|------|---------|
| `job` | 서비스/애플리케이션 구분 | `nginx`, `was`, `fastapi` |

#### Step 2: 검색 조건 추가 (선택사항)

- **Line contains**: 특정 텍스트가 포함된 로그만 필터링
- **Operations**: 추가적인 LogQL 연산 적용

#### Step 3: 쿼리 실행

우측 상단의 **Run query** 버튼을 클릭하면 검색 결과가 표시됩니다.

### 5.3 검색 결과 화면 구성

| 영역 | 설명 |
|------|------|
| **Logs volume** | 시간대별 로그 발생량을 막대 그래프로 표시 |
| **Logs** | 실제 로그 내용이 시간순으로 표시 |
| **Log levels** | 로그 레벨(info, warn, error 등)별 필터링 |

### 5.4 유용한 검색 팁

**특정 에러 로그 찾기:**
```
{job="was"} |= "error"
```

**특정 시간대 로그 조회:**
- 우측 상단의 시간 범위 선택기에서 원하는 기간 설정
- `Last 1 hour`, `Last 6 hours`, 또는 커스텀 범위 지정

**로그 레벨 필터링:**
- 검색 결과 우측의 `Log levels` 패널에서 원하는 레벨만 선택


## 6. 실시간 로그 모니터링

장애 대응이나 배포 시 실시간으로 로그를 확인해야 할 때 **Live** 모드를 활용합니다.

![실시간 로그](https://raw.githubusercontent.com/100-hours-a-week/14-team-dojangkok-cloud/refs/heads/main/wiki/guide/monitoring/images/06_live_log.png)

### 6.1 Live 모드 활성화

1. Explore 화면에서 원하는 로그 쿼리 설정
2. 우측 상단의 **Live** 버튼 클릭
3. 실시간으로 새로운 로그 스트리밍

### 6.2 Live 모드 컨트롤

| 버튼 | 기능 |
|------|------|
| **Pause** | 로그 스트리밍 일시 중지 (현재 화면 고정) |
| **Clear logs** | 화면에 표시된 로그 초기화 |
| **Exit live mode** | Live 모드 종료 및 일반 검색 모드로 복귀 |