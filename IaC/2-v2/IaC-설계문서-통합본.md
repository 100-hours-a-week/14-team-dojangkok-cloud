# 도장콕 IaC V2 설계문서 통합본

- 작성일: 2026-02-08
- 최종수정일: 2026-02-11
- 작성자: waf.jung(정승환)

---

## 목차

1. [도입](#1-도입)
2. [AWS 인프라](#2-aws-인프라)
3. [GCP 인프라](#3-gcp-인프라)
4. [Terraform 모듈 구조](#4-terraform-모듈-구조)
5. [사전 조건 + 확정 필요 항목](#5-사전-조건--확정-필요-항목)

---

## 1. 도입

### 1.1 V1 → V2 변경 요약

| 항목 | V1 | V2 |
|------|----|----|
| **구조** | 플랫 (리소스별 .tf 파일) | 모듈 + 환경 분리 |
| **AWS 환경** | 단일 | DEV/PROD 운영 + STAGE CIDR 예약 |
| **AWS 진입점** | EC2 1대 (모놀리식) | ALB + ASG (DEV/PROD 동일) |
| **AWS 네트워크** | Public 1개 | Public + Private (역할별 서브넷) |
| **AWS 컨테이너** | 없음 | Packer + docker-compose |
| **GCP 환경** | 단일 | DEV/PROD (별도 프로젝트) |
| **GCP 통신** | AWS에서 외부 IP 직접 호출 | Cloud NAT 아웃바운드 (LB 제거, RabbitMQ 양방향) |
| **GCP 컨테이너** | systemd 직접 실행 | Packer + docker-compose |
| **GCP 서버** | AI Server 1대 | AI Server(MIG) + ChromaDB + vLLM |
| **State** | 단일 key | 환경별 key (`v2/{env}/`) |
| **값 관리** | 하드코딩 | variables.tf + tfvars |

### 1.2 V2 설계 방향

**동기**: 인프라가 복잡해지면서(AWS 다중 서비스, GCP 멀티 컨테이너) IaC로 팀원 간 일관성 보장과 재현 가능한 인프라가 필요해졌다.

**모듈화**: 생성 로직(모듈)과 환경 설정(환경 디렉토리)을 분리한다.

```
modules/
  networking/    ← VPC+서브넷 만드는 방법 (1곳)
  compute/       ← EC2/VM 만드는 방법 (1곳)

environments/
  dev/main.tf    ← networking(cidr="10.0.0.0/18") + compute(type="t4g.small")
  prod/main.tf   ← networking(cidr="10.2.0.0/18") + compute(type="m7g.medium")
```

**트레이드오프**: 모듈 인터페이스(variable/output) 코드량이 늘고, 값 추적이 환경→모듈→리소스 3단계가 된다. 하지만 2개 환경 운영 기준으로 코드 복사의 유지보수 비용이 모듈화 초기 비용보다 크다.

---

## 2. AWS 인프라

### 2.1 환경 구성

기존 VPC(`vpc-060a437112ddb879d`, `10.0.0.0/18`)에 **Secondary CIDR**을 추가하여 환경을 분리한다. DEV와 PROD는 동일 구조(ALB + ASG)로 운영하며, STAGE는 CIDR만 예약한다.

```
AWS VPC (vpc-060a437112ddb879d)
├── 10.0.0.0/18  Primary CIDR   → DEV (운영 중)
├── 10.1.0.0/18  Secondary CIDR → STAGE (CIDR 예약, 리소스 미생성)
└── 10.2.0.0/18  Secondary CIDR → PROD (운영 중)
```

STAGE 환경: Terraform 코드는 존재하지만 `terraform apply`를 실행하지 않은 상태. 필요 시 tfvars를 채우고 apply하면 즉시 배포 가능.

### 2.2 인프라 구조도

> DEV/PROD 동일 구조. CIDR만 다름 (DEV: `10.0.x.x`, PROD: `10.2.x.x`).

```
Internet
  │
  └─ :80/:443 ──→ [ ALB ] ─┬─ /api/* → [ ASG BE :8080 ]
                            │            ├→ [ MySQL :3306 ]
                            │            ├→ [ RabbitMQ :5672 ]
                            │            └→ [ Redis :6379 ]
                            │
                            └─ /* ────→ [ ASG FE :3000 ]

Public Subnets
  └─ AZ-a: 10.x.0.0/24 (NAT Instance + ALB)
  └─ AZ-c: 10.x.6.0/28 (ALB 2-AZ 요건 충족용, 리소스 없음)

Private Subnets (전부 AZ-a)
  └─ FE:    10.x.1.0/24
  └─ BE:    10.x.2.0/24
  └─ RDB:   10.x.3.0/24
  └─ MQ:    10.x.4.0/24
  └─ Cache: 10.x.5.0/24
```

**DEV 추가 리소스**: Public 서브넷에 Monitoring 인스턴스(EIP) — Prometheus + Grafana + Loki 전 환경 통합.

### 2.3 네트워크

**CIDR 할당**

| 환경 | CIDR | 타입 | Public | Private |
|------|------|------|--------|---------|
| DEV | `10.0.0.0/18` | Primary | `10.0.0.0/24` (AZ-a) + `10.0.6.0/28` (AZ-c) | `10.0.1~5.0/24` (AZ-a) |
| STAGE | `10.1.0.0/18` | Secondary 1 | 예약 | 예약 |
| PROD | `10.2.0.0/18` | Secondary 2 | `10.2.0.0/24` (AZ-a) + `10.2.6.0/28` (AZ-c) | `10.2.1~5.0/24` (AZ-a) |

**단일 AZ 원칙**: 실 리소스는 `ap-northeast-2a`에만 배치. AZ-c의 `/28` 서브넷은 ALB 2-AZ 필수 요건 충족용(EC2 없음).

**트레이드오프**: AZ-a 장애 시 전체 서비스 중단 리스크. 비용 절감(NAT·서브넷·AZ 간 데이터 전송)을 우선하며, 향후 멀티 AZ 전환으로 가용성 보강 예정.

**NAT Instance**: NAT Gateway($32/월) 대신 `t4g.nano`($3/월). 각 환경 Public 서브넷에 배치, `source_dest_check = false`, EIP 할당.

**S3 VPC Endpoint**: Gateway 타입(무료). 단일 VPC에 같은 서비스의 Gateway Endpoint는 1개만 허용 → **import 방식으로 관리**. 전 환경 Route Table을 연결하여 ECR pull 시 NAT 미경유.

### 2.4 보안 그룹

**DEV**

| SG | 포트 | 소스 | 설명 |
|----|------|------|------|
| alb | 80, 443 | `0.0.0.0/0` | HTTP/HTTPS |
| monitoring | 3000, 9090 | `0.0.0.0/0` | Grafana, Prometheus |
| monitoring | 3100 | `10.0.0.0/18`, `10.1.0.0/18`, `10.2.0.0/18`, GCP AI IP | Loki (전 환경 + GCP) |
| fe | 3000 | VPC CIDR (10.0.0.0/18) | Next.js |
| be | 8080 | VPC CIDR (10.0.0.0/18) | Spring Boot |
| mysql | 3306 | BE 서브넷 (10.0.2.0/24) | MySQL |
| rabbitmq | 5672 | VPC CIDR (10.0.0.0/18) | RabbitMQ (AMQP, NLB 경유 GCP 포함) |
| rabbitmq | 15672 | Monitoring | RabbitMQ Management |
| redis | 6379 | BE 서브넷 (10.0.2.0/24) | Redis |

**PROD**

| SG | 포트 | 소스 | 설명 |
|----|------|------|------|
| alb | 80, 443 | `0.0.0.0/0` | ALB 인바운드 |
| fe | 3000 | VPC CIDR (10.2.0.0/18) | ALB → FE |
| be | 8080 | VPC CIDR (10.2.0.0/18) + Monitoring (10.0.0.0/24) | ALB → BE + Monitoring |
| mysql | 3306 | BE 서브넷 (10.2.2.0/24) | BE → MySQL |
| rabbitmq | 5672 | VPC CIDR (10.2.0.0/18) | RabbitMQ (AMQP, NLB 경유 GCP 포함) |
| rabbitmq | 15672 | Monitoring | RabbitMQ Management |
| redis | 6379 | BE 서브넷 (10.2.2.0/24) | BE → Redis |

공통: 모든 Private 인스턴스에 `9100`(node_exporter) 허용. MySQL `9104`(mysql_exporter), Redis `9121`(redis_exporter) 추가. 전체 SG egress `0.0.0.0/0`.

### 2.5 Load Balancer

DEV/PROD 동일 구조.

| 항목 | 값 |
|------|------|
| 타입 | Application Load Balancer |
| 서브넷 | Public 2개 (AZ-a + AZ-c) |
| Listener | HTTP:80 (SSL 인증서 있으면 HTTPS:443 + 리다이렉트) |

**Target Groups**

| TG | 포트 | Health Check | Path Pattern | 우선순위 |
|----|------|-------------|-------------|----------|
| BE | 8080 | `/actuator/health` | `/api/*` | 100 (높음) |
| FE | 3000 | `/` | `/*` | 200 (낮음) |

**NLB (후속 작업)**: GCP AI Server → RabbitMQ 경로에 AMQPS TLS 종료용 Network Load Balancer 추가 예정. NLB는 Public 서브넷에 배치, 타겟은 RabbitMQ 인스턴스(:5672).

### 2.6 Compute

**DEV/PROD — ASG + 단일 인스턴스**

| 인스턴스 | 모듈 | 서브넷 | 스케일링 |
|----------|------|--------|---------|
| fe | asg | `pri-fe` | min/max/desired (변수) |
| be | asg | `pri-be` | min/max/desired (변수) |
| mysql | compute | `pri-rdb` | 단일 |
| rabbitmq | compute | `pri-mq` | 단일 |
| redis | compute | `pri-cache` | 단일 |

DEV 추가: monitoring (compute, Public, EIP)

ASG CPU Target Tracking: 기본 70%. 인스턴스 사양은 `terraform.tfvars`에서 지정.

**RabbitMQ 선택 근거**: 멀티 클라우드(AWS↔GCP) 간 표준 프로토콜(AMQP) 필요. AWS 관리형(SQS/SNS)은 GCP에서 접근 제약이 있고, 자체 운영으로 양쪽 환경 동등 접근 보장.

### 2.7 AMI + 컨테이너 전략

**AMI**

| 변수 | 용도 | fallback |
|------|------|----------|
| `docker_ami_id` | Docker+Compose 프리인스톨 | Ubuntu 22.04 ARM64 |
| `nat_ami_id` | NAT 전용 (IP 포워딩/iptables) | Ubuntu 22.04 ARM64 |

**컨테이너화 전략**

GCP와 동일한 Packer + docker-compose 패턴. 모든 인스턴스에 Docker+Compose가 프리인스톨된 커스텀 AMI를 사용하며, 모니터링 사이드카를 docker-compose로 통합 관리한다.

| 인스턴스 | 애플리케이션 | 모니터링 사이드카 (docker-compose) |
|----------|------------|----------------------------------|
| FE (Next.js) | Docker 컨테이너 (ECR) | node_exporter, promtail |
| BE (Spring Boot) | Docker 컨테이너 (ECR) | node_exporter, promtail |
| MySQL | 호스트 네이티브 | node_exporter, mysql_exporter, promtail |
| RabbitMQ | 호스트 네이티브 | node_exporter, promtail |
| Redis | 호스트 네이티브 | node_exporter, redis_exporter, promtail |
| Monitoring | Docker 컨테이너 (Prometheus, Grafana, Loki) | — |

- **FE/BE**: CD 파이프라인에서 ECR 로그인 → `docker compose pull && docker compose up -d`
- **DB/Cache/MQ**: 애플리케이션은 호스트에서 직접 실행. docker-compose는 모니터링 사이드카 관리 전용
- **Monitoring**: Prometheus + Grafana + Loki 자체가 Docker 컨테이너로 운영

**구분 근거**: DB/MQ는 데이터 영속성·I/O 성능·장애 시 디버깅 용이성을 위해 호스트 네이티브. FE/BE는 빈번한 배포와 ECR 기반 CD 파이프라인에 Docker 컨테이너가 적합.

### 2.8 IAM

import 방식으로 기존 리소스를 Terraform 관리로 전환.

| 항목 | 값 |
|------|------|
| EC2 Role | `ktb-team14-dojangkok-role-s3-bucket` (기존) |
| 연결 정책 | `AmazonS3FullAccess`, `AmazonSSMManagedInstanceCore`, `AmazonEC2ContainerRegistryReadOnly` |
| SSH 접근 | SSM Session Manager (EC2 Key Pair 제거) |

### 2.9 Storage

S3와 ECR은 **PROD 환경에서 단일 생성**, 환경별 키 프리픽스와 이미지 태그로 구분한다. DEV/STAGE 환경에서는 storage 모듈을 호출하지 않는다.

**S3 버킷** (PROD state에서 관리)

| 버킷 | 용도 | 환경 구분 |
|------|------|----------|
| `ktb-team14-dojangkok-bucket` | 데이터 | 키 프리픽스 (`dev/`, `prod/`) |
| `ktb-team14-dojangkok-deploy` | 배포 | 키 프리픽스 (`dev/`, `prod/`) |
| `ktb-team14-dojangkok-mysql-backup` | 백업 | 키 프리픽스 (`dev/`, `prod/`) |

**ECR** (PROD state에서 관리)

| 리포지토리 | 환경 구분 |
|-----------|----------|
| `dojangkok/frontend` | 이미지 태그 (`dev-xxx`, `prod-xxx`) |
| `dojangkok/backend` | 이미지 태그 (`dev-xxx`, `prod-xxx`) |

### 2.10 Monitoring

DEV Public 서브넷(`10.0.0.0/24`)에 통합 Monitoring 인스턴스 배치.

| 서비스 | 포트 | 수집 대상 |
|--------|------|----------|
| Prometheus | 9090 | 전 환경 node/mysql/redis exporter |
| Grafana | 3000 | Prometheus 데이터 시각화 |
| Loki | 3100 | 전 환경 + GCP AI 서버 로그 |

PROD SG에 `10.0.0.0/24`(DEV Public) 소스로 exporter 포트 허용.

---

## 3. GCP 인프라

### 3.1 환경 구성

GPU 할당량이 **프로젝트당 L4 x1**로 제한되어, DEV와 PROD를 별도 GCP 프로젝트로 분리한다. 동일 Terraform 모듈을 공유.

```
GCP Project (DEV)          GCP Project (PROD)
├── VPC                    ├── VPC
├── Subnet 10.10.0.0/24    ├── Subnet 10.10.0.0/24
├── AI Server (MIG)        ├── AI Server (MIG)
├── ChromaDB               ├── ChromaDB
├── vLLM (L4 x1)          ├── vLLM (L4 x1)
└── NAT, FW, AR            └── NAT, FW, AR
```

### 3.2 인프라 구조도

> DEV/PROD 동일 구조. RabbitMQ 도입(#107)으로 **LB 완전 제거**. AI Server는 Cloud NAT 경유로 AWS RabbitMQ에 아웃바운드 연결(양방향 메시징).

```
AWS (RabbitMQ :5671)
  │
  └─ AMQPS ↔── [ AI Server MIG ] ←── Cloud NAT (아웃바운드)
                    ├→ [ vLLM :8001 ] (LLM 추론)
                    └→ [ ChromaDB :8100 ] (임베딩 조회)

VM ──→ Cloud NAT ──→ 일반 인터넷 (pip, HuggingFace)

VM ──→ Private Google Access ──→ Artifact Registry (docker pull, NAT 미경유)

IAP Tunnel (35.235.240.0/20) ──→ SSH :22 (전체 VM)
AWS Monitoring ──→ :9090/:9100/:3000 (메트릭 수집)

Subnet: 10.10.0.0/24 (Private Google Access, 전 VM 외부 IP 없음)
  ├─ AI Server (MIG, n2d-standard-2) — Stateless, 롤링 배포
  ├─ ChromaDB (단일 VM, e2-medium) — Stateful
  └─ vLLM (단일 VM, g2-standard-4 + L4 GPU) — Stateful

Cloud Router + Cloud NAT (AUTO IP)
Artifact Registry (asia-northeast3-docker.pkg.dev)
GitHub Actions → OIDC → Workload Identity → SA → docker push
```

### 3.3 통신 경로

| 경로 | 방향 | 경유 | 비고 |
|------|------|------|------|
| AI Server ↔ AWS RabbitMQ | outbound | Cloud NAT | AMQPS :5671, 양방향(소비+발행) |
| AI Server → vLLM | internal | 서브넷 :8001 | LLM 추론 |
| AI Server → ChromaDB | internal | 서브넷 :8100 | 임베딩 조회 |
| VM → AR | outbound | Private Google Access | NAT 미경유, 무료 |
| VM → 인터넷 | outbound | Cloud NAT | pip, HuggingFace |
| SSH | inbound | IAP Tunnel :22 | 외부 직접 SSH 차단 |
| Monitoring | inbound | 방화벽 허용 (AWS IP) | Prometheus scrape |

### 3.4 네트워크

| 환경 | GCP 프로젝트 | VPC | 서브넷 | CIDR |
|------|-------------|-----|--------|------|
| DEV | [TODO] | dojangkok-ai-vpc | dojangkok-ai-dev | 10.10.0.0/24 |
| PROD | [TODO] | dojangkok-ai-vpc | dojangkok-ai-prod | 10.10.0.0/24 |

프로젝트가 다르므로 동일 CIDR 사용 가능.

**Cloud NAT**: Cloud Router `dojangkok-ai-router` + Cloud NAT `dojangkok-ai-nat`, IP AUTO_ONLY, ALL_SUBNETWORKS.

### 3.5 방화벽

LB 제거로 `allow-lb-to-ai` 규칙 삭제. 총 **5개** 규칙.

| 규칙 | 포트 | 소스 | 타겟 태그 | 우선순위 |
|------|------|------|-----------|----------|
| allow-ai-to-vllm | 8001 | 10.10.0.0/24 | vllm | 1000 |
| allow-ai-to-chromadb | 8100 | 10.10.0.0/24 | chromadb | 1000 |
| allow-monitoring | 9090, 9100, 3000 | AWS Monitoring IP (변수) | dojangkok-monitoring | 1000 |
| allow-iap-ssh | 22 | 35.235.240.0/20 (Google IAP) | 전체 VM | 1000 |
| allow-internal | all | 10.10.0.0/24 | 전체 VM | 1100 |

### 3.6 Compute

| VM | 모듈 | 사양 | 디스크 | 태그 |
|----|------|------|--------|------|
| AI Server | compute-mig | n2d-standard-2 | 30GB pd-balanced | ai-server, dojangkok-monitoring |
| ChromaDB | compute | e2-medium | 50GB(DEV)/100GB(PROD) pd-balanced | chromadb |
| vLLM | gpu-compute | g2-standard-4 + L4 | 200GB pd-ssd | vllm, dojangkok-monitoring |

공통: 전 VM 외부 IP 없음. PROD만 ChromaDB/vLLM에 `deletion_protection = true`.

**AI Server에만 MIG를 쓰는 이유**: Stateless이고 배포 빈도가 높아 무중단 배포 필요. vLLM은 모델 로딩 ~6분의 Stateful 서비스이며 GPU 할당 1개로 surge 인스턴스 생성 불가.

**MIG Auto-healing**: LB 없이 독립 Health Check 사용. HTTP `/health` port 8000, interval 30s. unhealthy VM을 자동 교체.

### 3.7 IaC 변경: COS → Packer + docker-compose

**변경 배경**: COS는 단일 컨테이너 전용이라 node-exporter, promtail 등 모니터링 사이드카 배치 불가. Packer + docker-compose로 전환하여 멀티 컨테이너 운영. AWS도 동일 패턴 적용 (§2.7 참조).

**compute-mig 모듈 전환**: 모듈은 이미 dual-mode 지원 설계.

```
# container_image != null → COS 모드 (cos-cloud/cos-stable 부팅)
# container_image == null → startup_script 모드 (Packer 이미지 부팅)
```

환경 main.tf에서 호출 방식만 변경:

```hcl
# Before (COS)
module "ai_server" {
  container_image = ".../ai-server:latest"
}

# After (Packer + docker-compose)
module "ai_server" {
  boot_disk_image = var.ai_server_boot_disk_image  # Packer 이미지
  startup_script  = templatefile("scripts/startup-ai-server.sh", {
    compose_content = templatefile("../../docker-compose/ai-server.yml", { ... })
    ar_host         = "asia-northeast3-docker.pkg.dev"
  })
}
```

**lifecycle ignore_changes**: `google_compute_instance_group_manager`에 `lifecycle { ignore_changes = [version] }` 추가. CD 파이프라인이 Instance Template을 직접 교체하므로, `terraform apply` 시 version 변경을 되돌리지 않는다.

**신규 변수** (docker-compose에 주입):

| 변수 | 설명 |
|------|------|
| `vllm_api_key` | vLLM API 인증 키 (sensitive) |
| `vllm_model` | vLLM 모델명 |
| `vllm_lora_adapter_checklist` | LoRA 어댑터 (체크리스트) |
| `vllm_lora_adapter_easycontract` | LoRA 어댑터 (쉬운계약서) |
| `backend_callback_base_url` | 백엔드 콜백 URL |
| `backend_internal_token` | 백엔드 내부 토큰 (sensitive) |
| `ocr_api` | Upstage OCR API 키 (sensitive) |
| `http_timeout_sec` | HTTP 타임아웃 |

### 3.8 배포 경로

**AI Server (MIG — 롤링 업데이트)**: Docker Build → AR Push → Instance Template 교체 → MIG 롤링 (max_surge=1, max_unavailable=0).

**vLLM, ChromaDB (단일 VM — 수동)**: IAP SSH → docker compose pull/up.

상세 CI/CD 파이프라인은 별도 문서 참조: [GCP 컨테이너화 설계문서](../../docs/technical/ai/gcp-containerization-design.md)

---

## 4. Terraform 모듈 구조

### 4.1 AWS 모듈

```
aws/modules/
├── networking/     # VPC data 참조, Secondary CIDR, Subnet, NAT Instance, Route Table
├── security/       # Security Group (맵 기반), S3 VPC Endpoint
├── compute/        # EC2 단일 인스턴스 (AMI coalesce, EIP 옵션)
├── asg/            # Launch Template + ASG (AMI coalesce, CPU 스케일링)
├── alb/            # ALB + Target Group + Listener Rule (SSL 옵션)
├── iam/            # IAM Role/Profile (import 방식), CodeDeploy Role (옵션)
└── storage/        # S3 버킷, ECR 리포지토리
```

### 4.2 GCP 모듈

```
gcp/modules/
├── project-setup/       # GCP API 자동 활성화
├── networking/          # VPC, Subnet, Cloud Router, Cloud NAT
├── firewall/            # 방화벽 규칙 (network 필수, source_ranges 필수)
├── compute/             # CPU VM 단일 인스턴스 (external_ip 기본 false)
├── compute-mig/         # CPU VM + MIG 롤링 업데이트 (COS/startup_script 듀얼모드)
├── gpu-compute/         # GPU VM (on_host_maintenance = TERMINATE)
├── service-account/     # SA + IAM (artifactregistry.writer 포함)
├── workload-identity/   # GitHub OIDC Pool/Provider/SA Binding
└── artifact-registry/   # 컨테이너 이미지 저장소
```

`load-balancer` 모듈은 코드에 존재하나 환경에서 미사용 (LB 제거).

### 4.3 Environment 구조

**AWS (3개 환경)**

```
aws/environments/
├── dev/       # networking → security → iam → alb → asg_fe → asg_be → public_servers → db_servers
├── stage/     # dev와 동일 구조 (CIDR 예약, apply 전)
├── prod/      # dev + storage (S3/ECR 공유 리소스 관리)
└── (iam-global/)  # IAM Users/Groups (환경 무관, import용)
```

**GCP (2개 환경)**

```
gcp/environments/
├── dev/       # project_setup → networking → SA/WI → AR → FW x5 → HC → MIG → compute → gpu
└── prod/      # 동일 구조, deletion_protection 활성화
```

### 4.4 State 관리

**AWS** — S3 Backend (`dojangkok-aws-iac-state`)

| 환경 | State Key |
|------|-----------|
| DEV | `v2/dev/terraform.tfstate` |
| STAGE | `v2/stage/terraform.tfstate` |
| PROD | `v2/prod/terraform.tfstate` |
| IAM Global | `v2/iam-global/terraform.tfstate` |

**GCP** — GCS Backend

| 환경 | State Key |
|------|-----------|
| DEV | `v2/gcp/dev/terraform.tfstate` |
| PROD | `v2/gcp/prod/terraform.tfstate` |

V1 state와 **v2/ 프리픽스로 완전 분리**.

---

## 5. 사전 조건 + 확정 필요 항목

### 5.1 사전 조건

**AWS**

| # | 작업 | 누락 시 |
|---|------|--------|
| 1 | S3 state 버킷 생성 + 버전 관리 활성화 | `terraform init` 실패 |
| 2 | IAM Role/Profile import | 이름 충돌 에러 |
| 3 | S3 버킷 import | 이름 충돌 에러 |
| 3-1 | S3 VPC Endpoint import | 중복 생성 실패 (Gateway Endpoint 1개 제한) |
| 4 | Docker AMI 생성 (Packer) | Ubuntu fallback, CD에서 Docker 명령 실패 |
| 5 | NAT AMI 생성 (Packer) | Ubuntu fallback, Private 인터넷 불가 |
| 6 | ACM 인증서 발급 (선택) | HTTP만 동작 |

**GCP**

| # | 작업 | 누락 시 |
|---|------|--------|
| 1 | GCP 프로젝트 생성 (x2) | apply 대상 없음 |
| 2 | 결제 계정 연결 (x2) | API 활성화 불가 |
| 3 | GPU 할당량 요청 (x2) | vLLM VM 생성 실패 (승인 1-2 영업일) |
| 4 | GCS state 버킷 생성 | `terraform init` 실패 |
| 5 | Packer CPU 이미지 빌드 | AI Server MIG 부팅 이미지 없음 |
| 6 | Packer GPU 이미지 빌드 | vLLM VM 부팅 이미지 없음 |
| 7 | AR에 초기 이미지 push | MIG 첫 부팅 시 pull 실패 |

### 5.2 확정 필요 항목

> `terraform.tfvars.example`을 복사하여 `terraform.tfvars`를 만들고 아래 항목을 채운다.

#### AWS 공통

| 변수 | 설명 | 구분 |
|------|------|------|
| `vpc_id` | 기존 VPC ID | 기본값 있음 |
| `ec2_role_name` | IAM Role 이름 (import) | **필수** |
| `ec2_instance_profile_name` | Instance Profile 이름 | **필수** |
| `docker_ami_id` | Docker AMI | **확정 필요** (`null` → Ubuntu fallback) |
| `nat_ami_id` | NAT AMI | **확정 필요** (`null` → Ubuntu fallback) |
| 인스턴스 사양 7종 | `*_instance_type` / `*_volume_size` | **확정 필요** |

#### AWS DEV 전용

| 변수 | 설명 | 구분 |
|------|------|------|
| `gcp_ai_server_cidr` | GCP AI 서버 외부 IP — Loki 방화벽 | **확정 필요** |

#### AWS PROD 전용 (Storage)

| 변수 | 설명 | 구분 |
|------|------|------|
| `s3_buckets` | S3 버킷 이름 맵 (data, deploy, backup) | **필수** |
| `ecr_repositories` | ECR 리포지토리 이름 목록 | **필수** |

#### AWS STAGE/PROD 전용

| 변수 | 설명 | 구분 |
|------|------|------|
| `fe_min_size` / `max_size` / `desired_capacity` | FE ASG 스케일링 | **확정 필요** |
| `be_min_size` / `max_size` / `desired_capacity` | BE ASG 스케일링 | **확정 필요** |
| `ssl_certificate_arn` | ACM 인증서 ARN | **선택** (`null` → HTTP만) |
| `codedeploy_role_name` | CodeDeploy Role | **선택** (`null` → 미생성) |

#### GCP DEV/PROD

| 변수 | 설명 | 구분 |
|------|------|------|
| `project_id` | GCP 프로젝트 ID | **필수** |
| `github_org` | GitHub Organization | **필수** |
| `monitoring_source_ips` | AWS Monitoring EIP | **필수** |
| `vllm_api_key` | vLLM API 키 | **필수** (sensitive) |
| `ocr_api` | Upstage OCR API 키 | **필수** (sensitive) |
| `vllm_model` | vLLM 모델명 | 기본값 있음 |
| `vllm_lora_adapter_*` | LoRA 어댑터 | 기본값 있음 |
| `backend_callback_base_url` | 콜백 URL | 기본값 있음 |
| `backend_internal_token` | 내부 토큰 | **선택** (sensitive) |
| `http_timeout_sec` | 타임아웃 | 기본값 있음 |
| `ai_server_boot_disk_image` | Packer CPU 이미지 | 기본값 있음 |
| `vllm_boot_disk_image` | GPU 부팅 이미지 | 기본값 있음 |

---

## 참고

- `terraform.tfvars`는 Git에 커밋하지 않음 (`.gitignore`)
- 변경 전 반드시 `terraform plan`으로 영향 확인
- GPU VM은 `on_host_maintenance = TERMINATE` 필수 (gpu-compute 모듈에 자동 반영)
- V1 인프라는 별도 state로 관리 — V2 apply가 V1에 영향 없음
