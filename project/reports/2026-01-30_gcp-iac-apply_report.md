# GCP IaC Apply 테스트 - 결과보고서

- 작성일: 2026-01-30
- 작업자: jsh

## 작업 내용

GCP Terraform 코드를 테스트 환경(fiery-topic-483322-b2)에서 apply/destroy 테스트 수행

## 테스트 환경

| 항목 | 값 |
|------|-----|
| 프로젝트 | fiery-topic-483322-b2 |
| Backend | GCS (dojangkok-gcp-iac-backend) |
| Terraform 버전 | v1.5.7 |

## 생성된 리소스

1. **Service Account** - github-actions-sa
2. **IAM 권한** - Compute Admin, IAP Tunnel, SA User
3. **Workload Identity Pool** - github-pool
4. **Workload Identity Provider** - github-provider (OIDC)
5. **Firewall Rule** - dojangkok-ai-server-fw (포트 8000, 8001, 8100)
6. **Compute Instance** - ai-server-test (n1-standard-4, T4 GPU)

## 결과

### Apply
- 대부분의 리소스 정상 생성
- Workload Identity Pool/Provider: soft delete 상태로 인해 409 에러 발생 → `terraform import`로 해결

### Destroy
- 정상 삭제 (10 resources destroyed)
- Workload Identity Pool은 soft delete 처리됨 (30일 후 영구 삭제)

## 주의사항

### Workload Identity Pool Soft Delete 문제

```
destroy 후 재생성 시 → 409 에러 (이미 존재)
```

**해결 방법:**
1. `gcloud iam workload-identity-pools undelete` 후 `terraform import`
2. 또는 pool/provider 이름 변경 (예: github-pool-v2)

### GPU Quota
- GPU 사용 시 해당 리전에 quota 필요
- 테스트 시 `gpu_count = 0`으로 설정하면 비용 절감

## 파일 구조

```
IaC/1-bigbang/gcp/
├── provider.tf          # Backend 설정 (GCS)
├── variables.tf         # 변수 정의
├── terraform.tfvars     # 실제 값 (gitignore)
├── terraform.tfvars.example
├── service_account.tf   # SA + IAM
├── workload_identity.tf # WI Pool/Provider
├── firewall.tf          # 방화벽 규칙
├── compute.tf           # AI Server VM
└── outputs.tf           # 출력값
```

## 사용 방법

```bash
# 테스트 환경
terraform init -backend-config="prefix=test"
terraform plan
terraform apply

# 프로덕션 환경
terraform init -backend-config="prefix=prod"
terraform plan
terraform apply
```

## 비고

- Workload Identity Pool 외 다른 리소스는 의존성 문제 없이 정상 동작
- 플랫 구조(모듈 미사용)로 리팩토링 완료
