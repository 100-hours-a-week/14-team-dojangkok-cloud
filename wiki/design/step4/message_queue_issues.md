# RabbitMQ 기술적 이슈 해결 전략 (Architecture Decision Record)

## 배경 및 목적
RabbitMQ를 활용한 비동기 아키텍처에서 발생할 수 있는 데이터 유실 문제와 리소스 관리 이슈를 해결하기 위함입니다. 초기에는 복잡한 백업(DLX) 전략을 고려했으나, 시스템의 복잡도를 낮추고 유지보수성을 높이기 위해 **"단순함(Simplicity)과 배포 안정성(Stability)"**을 핵심 가치로 삼아 설계를 확정했습니다.

## 핵심 제약조건
1. **Redis Pub/Sub 미사용:** 메시지 브로커(RabbitMQ)로 통신 채널을 일원화하여 관리 포인트 최소화.
2. **Polling 제거:** 서버 리소스 낭비와 응답 지연을 방지하기 위해 Event-Driven 방식 유지.
3. **복잡도 최소화:** 장애 대응 로직(DLX, Backup) 대신 표준 RPC 패턴 사용.

## 상세 해결 전략

### 1. 통신 패턴: Direct Reply-To (RPC)
복잡한 큐 관리(생성/삭제/바인딩)를 피하기 위해 RabbitMQ의 **Direct Reply-To** 기능을 사용합니다.

*   **동작 원리:**
    1.  **요청(Request):** Spring 서버는 메시지 헤더 `Reply-To` 속성에 특수 값인 `amq.rabbitmq.reply-to`를 설정하여 발행합니다.
    2.  **소비(Consume):** Spring 서버는 `amq.rabbitmq.reply-to`라는 가상 큐(Pseudo-Queue)를 리스닝하며 대기합니다.
    3.  **응답(Reply):** GCP Worker는 헤더에 명시된 주소로 결과를 바로 반환합니다.

### 2. 배포 시 안정성 확보: Graceful Shutdown & Blue/Green
배포 과정에서 서버가 중단되어 발생하는 응답 유실 문제를 방지하기 위해 **애플리케이션 레벨의 우아한 종료(Graceful Shutdown)**와 **인프라 레벨의 무중단 배포(Blue/Green)** 전략을 결합합니다.

*   **Spring Boot 설정:**
    *   `server.shutdown: graceful` 설정을 적용하여, 종료 신호(SIGTERM) 수신 시 즉시 종료하지 않고 **진행 중인 요청(Active Request)이 완료될 때까지 대기**합니다.
    *   **대기 시간(Timeout):** 작업 최대 소요 시간을 고려하여 넉넉하게 설정(예: 60s)합니다.
    
*   **배포 시나리오:**
    1.  **Traffic Switch:** 로드밸런서가 신규 버전(Green)으로 트래픽을 전환합니다.
    2.  **Draining (Blue):** 구 버전(Blue) 서버는 더 이상 새 요청을 받지 않지만, 이미 RabbitMQ에 요청을 보냈거나 기다리고 있는 응답은 계속 처리합니다.
    3.  **Complete:** 모든 대기 중인 작업이 완료되거나 타임아웃이 지나면, Blue 서버는 RabbitMQ 연결을 끊고 안전하게 종료됩니다.
    *   **결과:** 배포로 인한 **임시 큐 소멸 및 응답 유실은 0에 수렴**하게 됩니다.

### 3. 예외 처리: 불가피한 유실 대응 (Client Retry)
하드웨어 장애(Crash)나 네트워크 단절 등 불가피한 상황으로 인한 유실은 **"클라이언트 중심의 재시도 정책"**으로 커버합니다.

*   **정책:** 클라이언트는 일정 시간(Timeout) 동안 응답이 없거나 연결이 끊어지면, 사용자에게 알리거나 자동으로 재요청(Retry)을 수행합니다.
*   **근거:** 빈도가 극히 낮은 장애 상황을 위해 복잡한 Server-Side 복구 시스템을 구축하는 것은 비효율적(Over-Engineering)이라는 판단입니다.

### 4. 결론
**"Simple RPC + Graceful Shutdown"** 조합으로 대부분의 운영 상황(배포 등)에서 안정성을 보장하며, 드물게 발생하는 장애 상황은 클라이언트 재시도로 유연하게 대처하는 **실용적인 아키텍처**를 채택합니다.