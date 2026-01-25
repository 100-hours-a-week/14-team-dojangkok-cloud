# GCP Infrastructure as Code (Terraform)

- 작성일: 2025-01-25
- 최종수정일: 2026-01-25
- 작성자: DevOps
- 상태: approved

---

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

### 왜 IaC(Terraform)가 필요한가?

1. **다계정 운영**: AWS/GCP 크레딧 계정과 프로덕션 계정 분리 관리
2. **환경 재현성**: GPU 할당량 변경, 계정 이전 시 동일한 인프라 즉시 재구성
3. **변경 이력 추적**: Git을 통한 버전 관리 및 코드 리뷰
4. **CI/CD 자동화**: GitHub Actions와 연동한 자동 배포

### Terraform 선택 이유

- **멀티 클라우드 지원**: AWS + GCP 동시 관리 가능 (동일한 도구로 통합 관리)
- **HCL 선언적 문법**: 학습 비용 낮음, 가독성 높음
- **풍부한 GCP Provider 생태계**: Google 공식 지원

---

## 2. 현재 배포 현황

### 프로덕션 환경 (dojangkok-ai)

| 리소스 | 상태 | 비고 |
|--------|------|------|
| Service Account | Terraform 관리 | github-actions-sa |
| Workload Identity | Terraform 관리 | GitHub OIDC 인증 |
| Firewall | Terraform 관리 | TCP 8000, 8001, 8100 |
| AI Server VM | 문서화 | n1-standard-4 + T4 GPU |

> **참고**: VM은 현재 수동 관리 중입니다. VM 재생성 시 `ai-server` 모듈 코드를 사용하세요.

### 주요 사양

- **머신 타입**: n1-standard-4 (vCPU 4개, RAM 15GB)
- **GPU**: NVIDIA Tesla T4 x 1
- **존**: asia-northeast3-b
- **부팅 디스크**: 200GB SSD
- **OS**: Ubuntu 22.04 LTS

---

## 3. 모듈 구성

```
IaC/gcp/
├── README.md
├── modules/
│   ├── ai-server/          # GPU 지원 VM 인스턴스
│   ├── firewall/           # 방화벽 규칙
│   ├── github-actions-sa/  # CD 파이프라인용 Service Account
│   └── workload-identity/  # GitHub Actions OIDC 인증
└── environments/
    └── prod/               # 프로덕션 환경
```

### 모듈 설명

| 모듈 | 용도 |
|------|------|
| `github-actions-sa` | GitHub Actions CD 파이프라인에서 사용할 Service Account 생성 및 IAM 권한 부여 |
| `workload-identity` | GitHub OIDC를 통한 인증 설정 (키 없는 인증) |
| `firewall` | AI 서버 배포 포트에 대한 방화벽 규칙 |
| `ai-server` | GPU 지원 Compute Engine 인스턴스 (T4 GPU) |

---

## 4. 사용 방법

### 사전 요구사항

- Terraform >= 1.0.0
- GCP 프로젝트 접근 권한
- gcloud CLI 인증 완료

### 환경 설정

```bash
cd IaC/gcp/environments/prod

# 변수 파일 생성
cp terraform.tfvars.example terraform.tfvars

# terraform.tfvars 수정
vim terraform.tfvars
```

### 배포

```bash
# 초기화
terraform init

# 변경사항 확인
terraform plan

# 적용
terraform apply
```

### 상태 확인

```bash
# 리소스 목록
terraform state list

# 특정 리소스 상세
terraform state show module.github_actions_sa.google_service_account.github_actions
```

---

## 5. CI/CD 연동

### Workload Identity Provider 정보

Terraform apply 후 출력되는 값을 GitHub Secrets에 설정:

```bash
# 출력값 확인
terraform output workload_identity_provider
terraform output service_account_email
```

### GitHub Secrets 설정

| Secret 이름 | 값 |
|------------|-----|
| `GCP_PROJECT_ID` | dojangkok-ai |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/{project_number}/locations/global/workloadIdentityPools/github-pool/providers/github-provider` |
| `GCP_SERVICE_ACCOUNT` | `github-actions-sa@dojangkok-ai.iam.gserviceaccount.com` |

### GitHub Actions 워크플로우 예시

```yaml
- name: Authenticate to Google Cloud
  uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
    service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}
```

---

## 6. 주의사항

### VM 관리

- **현재 VM은 terraform import 하지 않음** (수동 관리)
- VM 재생성 필요 시 `ai-server` 모듈 활성화 후 apply
- GPU가 포함된 VM은 `on_host_maintenance = TERMINATE` 필수

### GPU 관련

- GPU 할당은 GCP 할당량(Quota) 승인 필요
- T4 GPU는 n1 머신 타입에서만 사용 가능
- Spot VM 사용 시 GPU 비용 절감 가능 (최대 91%)

### 보안

- `terraform.tfvars`는 Git에 커밋하지 않음 (.gitignore에 추가)
- Service Account 키 대신 Workload Identity 사용 권장
