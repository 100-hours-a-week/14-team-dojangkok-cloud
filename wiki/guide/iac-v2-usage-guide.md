# IaC v2 실행 가이드

- 작성일: 2026-02-11
- 최종수정일: 2026-02-11
- 작성자: waf.jung(정승환)
- 관련문서: ../../IaC/2-v2/IaC-설계문서-통합본.md

---

## 목차

1. [사전 준비](#1-사전-준비)
2. [디렉토리 구조](#2-디렉토리-구조)
3. [GCP 실행 가이드](#3-gcp-실행-가이드)
4. [AWS 실행 가이드](#4-aws-실행-가이드)
5. [주의사항 / 트러블슈팅](#5-주의사항--트러블슈팅)
6. [환경별 차이점 요약](#6-환경별-차이점-요약)

---

## 1. 사전 준비

### 1.1 필수 도구 설치

| 도구 | 최소 버전 | 용도 |
|------|-----------|------|
| Terraform | >= 1.0.0 | IaC 실행 |
| gcloud CLI | latest | GCP 인증/관리 |
| AWS CLI v2 | latest | AWS 인증/관리 |

### 1.2 인증 설정

#### GCP

```bash
# Application Default Credentials 설정
gcloud auth application-default login

# 프로젝트 설정 확인
gcloud config set project <PROJECT_ID>
```

#### AWS

3가지 인증 방식을 비교하고, 팀 상황에 맞게 선택한다.

| 방식 | 설정 | 장점 | 단점 |
|------|------|------|------|
| **Terraform 전용 IAM User** (권장 고려) | 전용 IAM User 생성 → 최소 권한 부여 → 별도 프로필로 사용 | 최소 권한 원칙, 키 유출 시 영향 범위 제한 | 초기 설정 필요, 키 로테이션 관리 |
| **SSO** | `aws sso login` → 환경변수 export | 토큰 기반 (임시 자격증명), 중앙 관리 | SSO 설정 필요, 세션 만료 시 재인증 |

**각 방식 설정법:**

```bash
#  Terraform 전용 프로필
aws configure --profile terraform
# → 전용 IAM User 키 입력
export AWS_PROFILE=terraform

#  SSO
aws sso login --profile <sso-profile>
eval "$(aws configure export-credentials --profile <sso-profile> --format env)"
```

> `~/.aws/credentials`에 키가 저장된다. `AWS_PROFILE` 환경변수로 프로필을 전환할 수 있다.
> aws login 의 경우, 해당 폴더의 cache 파일에서 액세스키와 시크릿키 발췌해서 사용해야함.

### 1.3 사전 생성 리소스 체크리스트

#### GCP

- [ ] GCP 프로젝트 생성 (DEV/PROD 별도)
- [ ] 결제 계정 연결
- [ ] GPU 할당량 요청 (L4 x1, `asia-northeast3` 리전)
- [ ] GCS state 버킷 생성: `dojangkok-ai-iac-backend`
- [ ] Packer 이미지 빌드 (`gcp/packer/`)
  - CPU 베이스: `dojangkok-cpu-base`
  - GPU 베이스: nvidia 드라이버 포함 (vLLM은 공용 이미지 사용 가능)

#### AWS

- [ ] S3 state 버킷 확인: `ktb-team14-dojangkok-deploy`
- [ ] 기존 IAM 리소스 확인 (import 대상):
  - IAM Role: `ktb-team14-dojangkok-role-s3-bucket`
  - Instance Profile: `ktb-team14-dojangkok-role-s3-bucket`
- [ ] Packer AMI 빌드 (`aws/packer/`)
  - Docker 베이스 AMI
  - NAT 전용 AMI

---

## 2. 디렉토리 구조

```
IaC/2-v2/
├── gcp/
│   ├── modules/               ← 수정하지 않음
│   │   ├── project-setup/
│   │   ├── networking/
│   │   ├── service-account/
│   │   ├── workload-identity/
│   │   ├── artifact-registry/
│   │   ├── firewall/
│   │   ├── compute/
│   │   ├── compute-mig/
│   │   ├── gpu-compute/
│   │   └── load-balancer/     ← 현재 미사용 (LB 제거)
│   ├── environments/
│   │   ├── dev/               ← 여기서 작업
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── versions.tf
│   │   │   ├── outputs.tf
│   │   │   ├── backend.hcl
│   │   │   ├── terraform.tfvars.example
│   │   │   └── scripts/startup-ai-server.sh
│   │   └── prod/              ← 여기서 작업
│   │       └── (동일 구조)
│   └── packer/                ← 이미지 빌드 (사전 작업)
│
├── aws/
│   ├── modules/               ← 수정하지 않음
│   │   ├── networking/
│   │   ├── security/
│   │   ├── iam/
│   │   ├── alb/
│   │   ├── asg/
│   │   ├── compute/
│   │   └── storage/
│   ├── environments/
│   │   ├── dev/               ← 여기서 작업
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── versions.tf
│   │   │   ├── outputs.tf
│   │   │   ├── backend.hcl
│   │   │   └── terraform.tfvars.example
│   │   ├── stage/             ← CIDR 예약만 (10.1.0.0/18)
│   │   └── prod/              ← 여기서 작업
│   │       └── (동일 구조)
│   ├── iam-global/            ← 1회만 실행
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── versions.tf
│   └── packer/                ← AMI 빌드 (사전 작업)
│
└── IaC-설계문서-통합본.md      ← 설계 배경/모듈 상세 참조
```

> `modules/`는 공용 모듈이다. 직접 수정하지 않고, `environments/{env}/main.tf`에서 호출만 한다.

---

## 3. GCP 실행 가이드

### 3.1 tfvars 설정

```bash
cd IaC/2-v2/gcp/environments/dev/

# example 복사 후 실제 값 입력
cp terraform.tfvars.example terraform.tfvars
```

#### 필수 변수 (`terraform.tfvars`에 입력)

| 변수명 | 설명 | 예시값 | 비고 |
|--------|------|--------|------|
| `project_id` | GCP 프로젝트 ID | `"fiery-topic-483322-b2"` | **필수 입력** |
| `github_org` | GitHub Organization | `"100-hours-a-week"` | WI 설정용 |
| `monitoring_source_ips` | AWS Monitoring EIP 목록 | `["15.165.80.197/32"]` | **실제 IP로 변경** |
| `vllm_api_key` | vLLM API 키 | — | **sensitive**, 반드시 입력 |
| `ocr_api` | Upstage OCR API 키 | — | **sensitive**, 반드시 입력 |

#### 선택 변수 (기본값 있음, 변경 시에만 입력)

| 변수명 | 기본값 | 설명 |
|--------|--------|------|
| `region` | `asia-northeast3` | GCP 리전 |
| `zone` | `asia-northeast3-a` | GCP 존 |
| `ai_server_machine_type` | `n2d-standard-2` | AI Server 머신 타입 |
| `ai_server_boot_disk_image` | `dojangkok-cpu-base` | Packer 빌드 이미지 |
| `chromadb_machine_type` | `e2-medium` | ChromaDB 머신 타입 |
| `vllm_machine_type` | `g2-standard-4` | vLLM 머신 타입 |
| `vllm_gpu_type` | `nvidia-l4` | GPU 타입 |
| `vllm_boot_disk_image` | `ubuntu-os-accelerator-images/...` | GPU 드라이버 포함 이미지 |
| `vllm_model` | `LGAI-EXAONE/EXAONE-3.5-2.4B-Instruct` | vLLM 모델명 |
| `vllm_lora_adapter_checklist` | `checklist` | LoRA 어댑터 (체크리스트) |
| `vllm_lora_adapter_easycontract` | `easycontract` | LoRA 어댑터 (쉬운계약서) |
| `backend_callback_base_url` | `https://dojangkok.cloud/api` | 백엔드 콜백 URL |
| `backend_internal_token` | `""` | 백엔드 내부 통신 토큰 (sensitive) |
| `http_timeout_sec` | `"30"` | HTTP 타임아웃 (초) |

#### backend.hcl (이미 설정되어 있음)

```hcl
# dev/backend.hcl
bucket = "dojangkok-ai-iac-backend"
prefix = "v2/dev"

# prod/backend.hcl
bucket = "dojangkok-ai-iac-backend"
prefix = "v2/prod"
```

### 3.2 Init → Plan → Apply

```bash
cd IaC/2-v2/gcp/environments/dev/

# 1. 초기화 (backend.hcl로 state 위치 지정)
terraform init -backend-config=backend.hcl

# 2. 실행 계획 확인
terraform plan

# 3. 적용
terraform apply

# 4. 출력값 확인
terraform output
```

> PROD 환경도 동일한 명령어. 경로만 `prod/`로 변경한다.

### 3.3 모듈 의존 순서 (이해용)

Terraform이 자동으로 의존성을 해결하므로 수동 순서 지정은 불필요하다. 참고용으로 모듈 간 관계를 정리한다.

```
project-setup ──→ networking ──→ firewall (5개)
             ├──→ service-account ──→ workload-identity
             │                   └──→ compute-mig (AI Server)
             │                   └──→ compute (ChromaDB)
             │                   └──→ gpu-compute (vLLM)
             └──→ artifact-registry ──→ compute-mig (이미지 URL)
                                    └──→ gpu-compute (이미지 URL)
```

**각 모듈 역할:**

| 모듈 | 리소스 | 비고 |
|------|--------|------|
| `project-setup` | GCP API 자동 활성화 | 최초 1회 |
| `networking` | VPC, Subnet, Cloud Router, Cloud NAT | 서브넷: `10.10.0.0/24` |
| `service-account` | GitHub Actions SA | CI/CD용 |
| `workload-identity` | WI Pool + Provider | GitHub OIDC 연동 |
| `artifact-registry` | Docker 이미지 저장소 | `dojangkok-ai` |
| `firewall` | 5개 방화벽 규칙 | AI↔vLLM, AI↔ChromaDB, Monitoring, IAP SSH, Internal |
| `compute-mig` | AI Server (MIG) | CPU, 롤링 업데이트 |
| `compute` | ChromaDB | CPU, 단일 VM |
| `gpu-compute` | vLLM | GPU (L4), 단일 VM |
| `load-balancer` | (미사용) | RabbitMQ 전환으로 LB 제거됨 |

### 3.4 Outputs 활용

`terraform apply` 후 다음 값이 출력된다. GitHub Secrets 등록에 사용한다.

| Output | 용도 |
|--------|------|
| `service_account_email` | GitHub Actions WI 설정 |
| `workload_identity_provider` | GitHub Actions WI 설정 |
| `vpc_name` | 네트워크 참조 |
| `ai_server_mig_name` | CD 파이프라인에서 MIG 업데이트 대상 |
| `chromadb_internal_ip` | AI Server 환경변수 (자동 주입됨) |
| `vllm_internal_ip` | AI Server 환경변수 (자동 주입됨) |

---

## 4. AWS 실행 가이드

### 4.1 실행 순서 (반드시 순서대로)

```
① iam-global/     ← 1회만 (기존 리소스 import 필수)
② environments/dev/   ← DEV 환경
③ environments/prod/  ← PROD 환경
```

> `iam-global`은 환경과 무관한 글로벌 IAM 리소스(Users, Groups)를 관리한다. DEV/PROD 환경보다 먼저 실행해야 한다.

### 4.2 iam-global: Import + Apply

`iam-global/`의 리소스는 이미 AWS 콘솔에서 생성되어 있다. Terraform으로 관리하려면 먼저 import해야 한다.

```bash
cd IaC/2-v2/aws/iam-global/

# 초기화 (backend가 versions.tf에 하드코딩됨)
terraform init

# Import — Groups
terraform import aws_iam_group.deployer deployer
terraform import aws_iam_group.developers developers
terraform import aws_iam_group.infra_admin InfraAdminGroup

# Import — Users
terraform import aws_iam_user.deployer ktb-team14-deployer
terraform import aws_iam_user.ellen ktb-team14-ellen
terraform import aws_iam_user.suho ktb-team14-suho
terraform import aws_iam_user.howard ktb-team14-howard
terraform import aws_iam_user.waf ktb-team14-waf

# Import — Group Memberships
terraform import aws_iam_group_membership.deployer deployer
terraform import aws_iam_group_membership.developers developers
terraform import aws_iam_group_membership.infra_admin InfraAdminGroup

# Import — Policy Attachments
terraform import aws_iam_group_policy_attachment.deployer_s3_readonly "deployer/arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
terraform import aws_iam_group_policy_attachment.admin_full "InfraAdminGroup/arn:aws:iam::aws:policy/AdministratorAccess"
terraform import aws_iam_group_policy_attachment.developers_s3_full "developers/arn:aws:iam::aws:policy/AmazonS3FullAccess"

# Plan으로 diff 확인 (No changes 목표)
terraform plan

# Apply
terraform apply
```

> `iam-global/` State: `s3://dojangkok-aws-iac-state/v2/iam-global/terraform.tfstate`

### 4.3 environments/dev: Import + Apply

#### tfvars 설정

```bash
cd IaC/2-v2/aws/environments/dev/
cp terraform.tfvars.example terraform.tfvars
```

#### 필수 변수 (`terraform.tfvars`에 입력)

| 변수명 | 설명 | 예시값 | 기본값 |
|--------|------|--------|--------|
| `ec2_role_name` | 기존 IAM Role 이름 | `"ktb-team14-dojangkok-role-s3-bucket"` | 없음 |
| `ec2_instance_profile_name` | 기존 Instance Profile 이름 | `"ktb-team14-dojangkok-role-s3-bucket"` | 없음 |
| `docker_ami_id` | Docker 프리인스톨 AMI | `"ami-xxxxxxxx"` | `null` (TODO) |
| `nat_ami_id` | NAT 전용 AMI | `"ami-xxxxxxxx"` | `null` (TODO) |
| `monitoring_instance_type` | Monitoring 인스턴스 타입 | `"t3.medium"` | `""` (TODO) |
| `monitoring_volume_size` | Monitoring 볼륨 (GB) | `30` | `0` (TODO) |
| `fe_instance_type` | FE ASG 인스턴스 타입 | `"t3.small"` | `""` (TODO) |
| `fe_volume_size` / `min` / `max` / `desired` | FE ASG 스케일링 | — | 모두 `0` (TODO) |
| `be_instance_type` | BE ASG 인스턴스 타입 | `"t3.small"` | `""` (TODO) |
| `be_volume_size` / `min` / `max` / `desired` | BE ASG 스케일링 | — | 모두 `0` (TODO) |
| `mysql_instance_type` / `volume_size` | MySQL 사양 | — | `""` / `0` (TODO) |
| `redis_instance_type` / `volume_size` | Redis 사양 | — | `""` / `0` (TODO) |

#### 선택 변수 (기본값 있음)

| 변수명 | 기본값 | 설명 |
|--------|--------|------|
| `region` | `ap-northeast-2` | AWS 리전 |
| `project_name` | `dojangkok-dev` | 리소스 네이밍 접두사 |
| `vpc_id` | `vpc-060a437112ddb879d` | 기존 VPC |
| `rabbitmq_instance_type` | `t4g.small` | RabbitMQ 인스턴스 |
| `ssl_certificate_arn` | `null` | HTTPS 사용 시 ACM ARN |

#### Import (최초 1회)

```bash
# IAM Role / Instance Profile (기존 AWS 리소스)
terraform import module.iam.aws_iam_role.ec2 ktb-team14-dojangkok-role-s3-bucket
terraform import module.iam.aws_iam_instance_profile.ec2 ktb-team14-dojangkok-role-s3-bucket

# CodeDeploy Role (사용 시)
# terraform import module.iam.aws_iam_role.codedeploy[0] dojangkok-codedeploy-role
```

#### Init → Plan → Apply

```bash
cd IaC/2-v2/aws/environments/dev/

# 초기화
terraform init -backend-config=backend.hcl

# 실행 계획 확인
terraform plan

# 적용
terraform apply
```

> DEV State: `s3://ktb-team14-dojangkok-deploy/iac-state/v2/dev/terraform.tfstate`

### 4.4 environments/prod: Import + Apply

PROD는 DEV와 거의 동일하되 다음이 다르다:

- Secondary CIDR `10.2.0.0/18` 사용 (VPC에 추가됨)
- `storage` 모듈 포함 (S3 버킷 + ECR 리포지토리)
- Monitoring 인스턴스 없음 (DEV의 Monitoring 공유)

#### 추가 변수 (PROD 전용)

| 변수명 | 설명 | 예시값 |
|--------|------|--------|
| `s3_buckets` | S3 버킷 맵 | `{ data = { name = "ktb-team14-dojangkok-bucket" }, ... }` |
| `ecr_repositories` | ECR 리포 목록 | `["dojangkok/frontend", "dojangkok/backend"]` |

#### Import (최초 1회) — PROD 추가분

```bash
cd IaC/2-v2/aws/environments/prod/

terraform init -backend-config=backend.hcl

# IAM (DEV와 동일 — 같은 Role을 공유)
terraform import module.iam.aws_iam_role.ec2 ktb-team14-dojangkok-role-s3-bucket
terraform import module.iam.aws_iam_instance_profile.ec2 ktb-team14-dojangkok-role-s3-bucket

# S3 버킷 (기존 리소스)
terraform import 'module.storage.aws_s3_bucket.buckets["data"]' ktb-team14-dojangkok-bucket
terraform import 'module.storage.aws_s3_bucket.buckets["deploy"]' ktb-team14-dojangkok-deploy
terraform import 'module.storage.aws_s3_bucket.buckets["backup"]' ktb-team14-dojangkok-mysql-backup

# S3 VPC Endpoint (이미 존재하는 경우)
# terraform import module.security.aws_vpc_endpoint.s3[0] vpce-xxxxxxxx

# Plan → Apply
terraform plan
terraform apply
```

> PROD State: `s3://ktb-team14-dojangkok-deploy/iac-state/v2/prod/terraform.tfstate`

---

## 5. 주의사항 / 트러블슈팅

### terraform.tfvars 커밋 금지

`terraform.tfvars`에는 API 키, 프로젝트 ID 등 민감 정보가 포함된다. `.gitignore`에 등록되어 있으므로 절대 커밋하지 않는다.

```
# .gitignore에 포함됨
*.tfvars
!*.tfvars.example
```

### WI Pool soft delete 문제 (GCP)

GCP Workload Identity Pool은 삭제 후 30일간 soft delete 상태로 남는다. 같은 `pool_id`로 재생성하면 충돌이 발생한다.

```
Error: Error creating WorkloadIdentityPool: googleapi: Error 409: Already exists
```

**해결법:**
```bash
# 삭제된 풀 복원
gcloud iam workload-identity-pools undelete github-pool \
  --location=global --project=<PROJECT_ID>

# 또는 terraform import로 기존 리소스 연결
terraform import module.workload_identity.google_iam_workload_identity_pool.pool \
  projects/<PROJECT_ID>/locations/global/workloadIdentityPools/github-pool
```

### GPU 할당량 미승인 시 에러 (GCP)

```
Error: Error creating Instance: ... Quota 'NVIDIA_L4_GPUS' exceeded
```

**해결법:** GCP 콘솔 → IAM & Admin → Quotas → `NVIDIA L4 GPUs (asia-northeast3)` 할당 요청. 승인까지 수 시간~수일 소요.

### AMI 교체 시 taint 필요 (AWS)

ASG Launch Template의 AMI는 `lifecycle { ignore_changes = [ami] }`로 보호될 수 있다. AMI를 강제로 교체하려면:

```bash
# Launch Template 재생성 강제
terraform taint module.asg_fe.aws_launch_template.this
terraform apply
```

### v1 State와 완전 독립

v2 IaC는 v1과 State가 완전히 분리되어 있다. v1 리소스를 건드리지 않으며, v2 작업이 v1에 영향을 주지 않는다.

| 버전 | GCP State | AWS State |
|------|-----------|-----------|
| v1 | `prefix = "terraform/state"` | `key = "terraform.tfstate"` |
| v2 | `prefix = "v2/{env}"` | `key = "iac-state/v2/{env}/terraform.tfstate"` |

### S3 VPC Endpoint 충돌 (AWS)

VPC에 이미 S3 Gateway Endpoint가 존재하면 `enable_s3_endpoint = true`에서 충돌한다. 기존 Endpoint를 import하거나 `enable_s3_endpoint = false`로 변경한다.

---

## 6. 환경별 차이점 요약

### GCP

| 항목 | DEV | PROD |
|------|-----|------|
| GCP 프로젝트 | 별도 | 별도 |
| State prefix | `v2/dev` | `v2/prod` |
| ChromaDB 디스크 | 50 GB | 100 GB |
| deletion_protection | 없음 | ChromaDB + vLLM |
| vLLM 부트 디스크 | pd-standard | pd-ssd (명시) |
| 서브넷 CIDR | `10.10.0.0/24` | `10.10.0.0/24` (프로젝트 분리) |

### AWS

| 항목 | DEV | STAGE | PROD |
|------|-----|-------|------|
| CIDR | 10.0.0.0/18 (Primary) | 10.1.0.0/18 (예약) | 10.2.0.0/18 (Secondary) |
| Secondary CIDR | 불필요 | 필요 | 필요 |
| Monitoring | 있음 (public) | 없음 (DEV 공유) | 없음 (DEV 공유) |
| Storage 모듈 | 없음 | 없음 | S3 + ECR |
| State key | `iac-state/v2/dev/...` | 미설정 | `iac-state/v2/prod/...` |
| 서브넷 prefix | `dev-` | `stage-` | (없음) |

### 공통

- VPC: 단일 VPC (`vpc-060a437112ddb879d`) 내 CIDR 분리
- NAT: t4g.nano 인스턴스 (비용 절약)
- 접근: Bastion 없음 → SSM Session Manager 사용
- Monitoring: DEV public subnet에 통합 (Prometheus, Grafana, Loki)
