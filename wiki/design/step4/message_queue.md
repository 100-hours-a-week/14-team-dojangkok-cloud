# 도장콕(DojangKok) 하이브리드 클라우드 아키텍처 설계서


## 1. 개요 (Executive Summary)

본 문서는 AI 기반 이미지 생성 및 처리 서비스 **'도장콕(DojangKok)'**의 시스템 아키텍처를 기술한다.  
본 서비스는 **AWS의 안정적인 웹 서비스 인프라**와 **GCP의 고성능 GPU 리소스**를 결합한 **하이브리드 클라우드(Hybrid Cloud)** 전략을 채택하였다. 대규모 트래픽과 긴 AI 추론 시간(Long-running Task)을 효율적으로 처리하기 위해 **RabbitMQ 기반의 비동기 이벤트 구동(Event-Driven) 아키텍처**와 **SSE(Server-Sent Events)** 기술을 핵심으로 한다.


## 2. 시스템 아키텍처 (System Architecture)

### 2.1. 전체 구조도 (High-Level Design)
시스템은 크게 **AWS 서비스 영역(Service Layer)**과 **GCP 연산 영역(Compute Layer)**으로 나뉜다.

* **AWS (Service Zone):** 사용자 접점, 비즈니스 로직, 메시지 브로커 담당
* **GCP (Compute Zone):** AI 모델 추론 및 이미지 생성 담당 (GPU 활용)
* **Inter-Cloud Bridge:** AWS NLB와 GCP Cloud NAT를 통한 보안 터널링

### 2.2. 기술 스택 (Tech Stack)

| 구분 | 기술 요소 | 비고 |
| :--- | :--- | :--- |
| **Frontend** | Next.js | SSR/CSR 하이브리드, AWS EC2 배포 |
| **Backend** | Spring Boot | REST API, SSE, RabbitMQ Client |
| **Message Broker** | RabbitMQ | 비동기 작업 큐, RPC 패턴 구현 |
| **AI Worker** | FastAPI, vLLM | GPU 가속 추론, Python 기반 비동기 처리 |
| **Infra (AWS)** | ALB, NLB, EC2 | 부하 분산 및 네트워크 보안 |
| **Infra (GCP)** | Compute Engine, Cloud NAT | GPU 인스턴스(MIG), Outbound IP 고정 |


## 3. 핵심 기술적 의사결정 (Key Technical Decisions)

### 3.1. 통신 패턴: RabbitMQ RPC (Remote Procedure Call)
* **배경:** 초기에는 응답 처리를 위해 Redis Pub/Sub 도입을 고려했으나, 브로드캐스팅(Broadcasting) 방식의 비효율성과 메시지 유실 위험(Fire-and-Forget)이 식별됨.
* **결정:** **RabbitMQ 단일 브로커를 활용한 RPC 패턴** 도입.
    * **요청(Request):** Spring Boot가 메시지 헤더에 `Reply-To`(응답받을 큐)와 `Correlation-ID`(요청 고유 ID)를 포함하여 발행.
    * **응답(Reply):** FastAPI가 작업 완료 후, 헤더에 명시된 `Reply-To` 큐로 결과를 직접 반환.
* **효과:** 요청을 보낸 특정 인스턴스만 응답을 수신하므로 트래픽 낭비가 없고, 메시지 영속성(Durability)을 보장함.

### 3.2. 실시간 통신: SSE & Sticky Session
* **배경:** AI 이미지 생성은 수십 초 이상 소요될 수 있어, 일반적인 HTTP Request-Response 모델로는 타임아웃(504 Gateway Timeout) 발생 위험이 큼.
* **결정:** **SSE(Server-Sent Events)** 도입 및 **Sticky Session** 적용.
    * **SSE:** 단방향 지속 연결을 통해 서버가 클라이언트에게 실시간으로 진행률 및 결과를 전송.
    * **Sticky Session (AWS ALB):** 다중화된 Spring Boot 환경에서, 클라이언트가 **SSE 연결을 맺은 특정 서버**로 후속 요청(`POST`)이 전달되도록 ALB의 쿠키 기반 세션 고정(Duration: 1시간) 활성화.

### 3.3. 보안 아키텍처: 3중 방어막 (Security Triad)
mTLS(Mutual TLS)의 관리 복잡성을 제거하면서도 엔터프라이즈급 보안을 달성하기 위해 3단계 보안 체계 구축.

1.  **전송 계층 암호화 (AMQPS):** AWS NLB에 ACM 인증서를 적용하여 인터넷 구간 통신을 TLS로 암호화. (TLS Termination)
2.  **네트워크 격리 (IP Whitelisting):** GCP에 **Cloud NAT(Manual IP)**를 적용하여 모든 Worker의 Outbound IP를 고정하고, AWS Security Group에서 해당 IP만 허용.
3.  **애플리케이션 인증:** RabbitMQ 내부 계정(ID/PW) 인증 수행.


## 4. 상세 데이터 흐름 (Data Flow Lifecycle)

사용자가 '도장콕' 서비스에서 이미지를 생성하고 결과를 받기까지의 흐름은 다음과 같다.

### Step 1: 연결 수립 (Subscribe)
1.  **Client → ALB:** `GET /api/sse/connect` 요청.
2.  **ALB:** URL 경로(`/api`)를 확인하고 Spring Boot 타겟 그룹으로 라우팅. **Sticky Cookie(AWSALB)**를 생성하여 응답에 포함.
3.  **Spring Boot (Instance A):** `SseEmitter`를 생성하고 메모리에 저장. 연결 유지.

### Step 2: 작업 요청 (Publish)
1.  **Client → ALB:** `POST /api/generate` 요청 (쿠키 포함).
2.  **ALB:** 쿠키를 확인하여 **Spring Boot (Instance A)**로 요청 전달.
3.  **Spring Boot (A):**
    * RabbitMQ `task_queue`에 메시지 발행.
    * Header: `Reply-To: queue_A`, `Correlation-ID: user_123`.
    * 즉시 `202 Accepted` 응답 반환 (HTTP 연결 종료).

### Step 3: AI 추론 (Process - Cross Cloud)
1.  **GCP FastAPI:** RabbitMQ(AWS)에서 메시지 수신 (Consume).
2.  **FastAPI → vLLM:** 내부 로드밸런서를 통해 vLLM 엔진에 추론 요청.
3.  **FastAPI:** 작업 완료 후 결과 생성.

### Step 4: 결과 반환 (Reply & Push)
1.  **GCP FastAPI:** 결과 메시지를 RabbitMQ의 `queue_A`로 전송 (Publish).
2.  **Spring Boot (A):** `queue_A`를 리스닝하다가 메시지 수신.
3.  **Spring Boot (A):** 메모리에 있는 `user_123`의 SSE 연결을 통해 클라이언트에게 결과 전송 (`emitter.send()`).


## 5. 인프라 구성 상세 (Infrastructure Specification)

### 5.1. AWS 구성 (Seoul Region)
* **VPC:** Private/Public Subnet 분리.
* **ALB (Application Load Balancer):**
    * Routing: `/` → Next.js, `/api` → Spring Boot.
    * **Settings:** Idle Timeout 300초 이상 설정 (SSE 끊김 방지).
    * **Target Group:** Spring Boot 그룹에 **Stickiness(LBCookie) 활성화**.
* **RabbitMQ (EC2):** Private Subnet 배치.
* **NLB (Network Load Balancer):**
    * Listener: TCP 5671 (TLS).
    * Certificate: ACM 발급 (`mq.dojangkok.com`).
    * Target: RabbitMQ EC2 (TCP 5672).
* **Security Group:**
    * NLB SG: Inbound 5671 허용 (Source: GCP Cloud NAT IP /32).

### 5.2. GCP 구성 (Compute Region)
* **Network:** Default VPC (Public IP 미할당 원칙).
* **Cloud NAT:**
    * Mode: **Manual (수동)**.
    * IP: 고정 IP (Static IP) 할당.
* **FastAPI Worker (MIG):**
    * Managed Instance Group으로 구성하여 오토스케일링 적용.
    * **Firewall:** Inbound **All Deny** (외부 접근 원천 차단). Outbound **Allow** (to AWS).


## 6. 확장성 및 성능 전략 (Scalability & Performance)

* **Stateless AI Worker:** GCP의 FastAPI는 상태를 저장하지 않으므로(Stateless), 큐에 쌓인 작업량(Lag)에 따라 수평 확장(Scale-out)이 자유로움.
* **GPU 리소스 격리:** 비즈니스 로직(FastAPI)과 AI 연산(vLLM)을 분리하여, 고가의 GPU 인스턴스를 효율적으로 관리하고 독립적으로 확장 가능.
* **비동기 처리:** 사용자의 대기 시간(Blocking)을 제거하여 UX를 향상시키고, 서버 리소스를 효율적으로 사용.


## 7. 결론 (Conclusion)

'도장콕' 서비스의 아키텍처는 **보안**, **확장성**, **사용자 경험**을 최우선으로 고려하여 설계되었다.
AWS와 GCP의 장점만을 결합한 이 하이브리드 구조는, 외부 공격으로부터 안전하며(Inbound Zero), 대규모 트래픽 상황에서도 유연하게 대응할 수 있는 견고한 기반을 제공한다.