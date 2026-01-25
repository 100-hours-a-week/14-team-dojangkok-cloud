# AWS Infrastructure as Code (Terraform)
- 작성일: 2025-01-25
- 최종수정일: 2026-01-25
- 작성자: howard.ha(하주영)


## 1. 도입 배경

### 도장콕 인프라 아키텍처

도장콕은 **메인 서비스(AWS)** 와 **AI 서비스(GCP)** 를 분리한 멀티 클라우드 구조를 채택했습니다.

| 클라우드 | 용도 | 비고 |
|---------|------|------|
| AWS | 메인 서비스 (Backend, Frontend) | |
| GCP | AI 서비스 (LLM 추론 서버) | GPU 크레딧 활용, AI/ML 특화 서비스 |

### 왜 GCP를 별도로 사용하는가?

1. **GPU 크레딧 활용**: GCP 교육 크레딧으로 GPU 비용 절감 (T4 GPU 무료 사용)
2. **관심사 분리**: AI 워크로드와 메인 서비스의 독립적 스케일링 및 장애 격리
3. **비용 최적화**: AI 서버만 GPU 인스턴스로 분리하여 효율적 리소스 관리

### AWS 관점에서 왜 IaC(Terraform)가 필요한가?

1. **DEV, STG, PRD 환경의 신속하고 안전한 구축 (Environment Parity)**
    > 서비스 성장 단계에 맞춰 **DEV(개발) → STG(스테이징) → PRD(운영)** 환경을 단계적으로 구축할 계획입니다. 콘솔을 통한 수동 구성은 반복 작업으로 인한 **속도 저하**와 **휴먼 에러**의 위험이 큽니다. IaC를 도입하면 검증된 인프라 코드를 각 환경에 즉시 복제할 수 있어, **환경 간 일관성(Consistency)**을 보장하고 **배포 속도**를 획기적으로 단축할 수 있습니다.

2. **변경 이력 추적 및 협업 강화 (Auditability & Collaboration)**
    > AWS 콘솔 작업은 "누가, 언제, 왜" 변경했는지 추적하기 어렵습니다. 인프라를 코드로 관리(IaC)하면 모든 변경 사항이 **Git 버전 관리 시스템**에 기록됩니다. 이를 통해 변경의 배경을 명확히 파악할 수 있고, **코드 리뷰(Code Review)**를 통한 사전 검증 및 문제 발생 시 **신속한 롤백(Rollback)**이 가능해져 운영 안정성이 강화됩니다.

### Terraform 선택 이유

- **멀티 클라우드 통합 관리 (Vendor Agnostic)**
    > 도장콕은 **AWS**와 **GCP**를 결합한 멀티 클라우드 전략을 취하고 있습니다. CloudFormation(AWS)이나 Deployment Manager(GCP)와 같은 벤더 종속적인 도구 대신, **Terraform**을 채택함으로써 단일화된 워크플로우를 구축했습니다. 이를 통해 운영 팀은 **단일 도구(Unified Toolchain)**와 문법(HCL)만 익히면 되므로 학습 비용을 절감하고 관리 효율성을 극대화할 수 있습니다.


## 2. 파일 구성

해당 챕터에서는 각 파일별 역할을 간단히 설명합니다. AWS 인프라에 대한 Terraform 코드는 총 11개의 파일로 구성되어 있으며, 각 역할을 다음과 같습니다.

| 파일명 | 분류 | 역할 및 목적 |
|:---:|:---:|---|
| **`provider.tf`** | 설정 | Terraform이 AWS와 통신하기 위한 프로바이더 및 리전 설정 |
| **`variables.tf`** | 설정 | 프로젝트 전반에서 재사용되는 공통 변수(Region, CIDR, Name) 정의 |
| **`vpc.tf`** | 네트워크 | VPC 및 인터넷 게이트웨이(IGW) 생성 |
| **`subnets.tf`** | 네트워크 | VPC 내부의 Public/Private 서브넷 구획 정의 |
| **`routes.tf`** | 네트워크 | 트래픽 경로를 위한 라우팅 테이블 및 서브넷 연결 |
| **`endpoints.tf`** | 네트워크 | 인터넷을 거치지 않는 S3 내부 연결을 위한 VPC 엔드포인트 |
| **`security_groups.tf`** | 보안 | 인스턴스 앞단의 방화벽(Inbound/Outbound 규칙) 정의 |
| **`iam.tf`** | IAM | 리소스(EC2 등)가 가질 권한(Role) 및 정책 정의 |
| **`iam_users.tf`** | IAM | 실제 사용자(User), 그룹(Group), 멤버십 구성 및 권한 할당 |
| **`s3.tf`** | 스토리지 | 데이터/배포/백업용 S3 버킷 생성 및 퍼블릭 차단 등 보안 설정 |
| **`ec2.tf`** | 컴퓨팅 | 애플리케이션 서버(EC2), AMI 데이터 소스, Elastic IP 정의 |


## 3. 기본 명령어
```bash
# 초기화
terraform init

# 변경사항 확인
terraform plan

# 적용
terraform apply
```