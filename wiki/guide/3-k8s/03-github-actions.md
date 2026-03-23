# GitHub Actions 사용법

cloud 레포(`14-team-dojangkok-cloud`)의 인프라 관리 + 각 서비스 레포의 앱 배포 워크플로우.

---

## Terraform

**파일:** `.github/workflows/terraform-v3-k8s.yml`

### 자동 트리거

`IaC/3-v3/aws/**` 경로 변경 PR → 자동 `plan` 실행 → PR에 결과 코멘트

### 수동 실행 (workflow_dispatch)

GitHub → Actions → "Terraform V3 K8S" → Run workflow

| 입력 | 설명 |
|------|------|
| action | `plan` / `apply` / `destroy` |
| ref | 체크아웃할 커밋 SHA (apply/destroy 시 필수) |

**흐름:**
```
plan → (변경 있으면) → apply 또는 destroy
```

- `plan`: 항상 먼저 실행됨. 변경 없으면(exitcode=0) apply/destroy 스킵
- `apply`: plan에서 변경 감지(exitcode=2) + ref 입력 시에만 실행
- `destroy`: 동일 조건 + `-destroy` 플래그로 plan

**필요 Secrets:**
- `TF_AWS_ROLE_ARN` — OIDC IAM Role (Terraform용)
- `K8S_DEV_VPC_ID` — VPC ID
- `K8S_DEV_SSL_CERT_ARN` — ACM 인증서 ARN

### 사용 예: 워커노드 추가

1. `IaC/3-v3/aws/environments/k8s-dev/variables.tf`에서 `workers_per_az` 변경
2. PR 생성 → 자동 plan → 결과 확인
3. merge 후 Actions에서 수동 `apply` + 커밋 SHA 입력

---

## Ansible

**파일:** `.github/workflows/ansible-v3-k8s.yml`

### 자동 트리거

`IaC/3-v3/ansible/**` 경로 변경 PR → `syntax-check` + `ansible-lint`

### 수동 실행 (workflow_dispatch)

| 입력 | 설명 |
|------|------|
| action | `syntax-check` / `deploy` |
| ref | 체크아웃할 커밋 SHA (deploy 시 필수) |

**deploy 실행 시:**
- SSM 플러그인 자동 설치
- 동적 인벤토리(`aws_ec2.yaml`)로 EC2 자동 감지
- `site.yml` 전체 실행 (멱등성 — 이미 설정된 노드는 스킵)

**필요 Secrets:**
- `ANSIBLE_AWS_ROLE_ARN` — OIDC IAM Role (SSM 접속용)

---

## 앱 CI/CD (서비스 레포)

**워크플로우 템플릿:** `workflows/3-v3/{BE,FE,AI,CHATTING}/ci-cd.yml`

> 이 파일을 각 서비스 레포의 `.github/workflows/`에 복사하여 사용

### 자동 트리거

`dev` 브랜치 push → CI(빌드/테스트) → CD(ECR push → kustomize 태그 업데이트)

### 수동 실행 (prod 배포)

GitHub → Actions → "{서비스} CI/CD (V3 K8S)" → Run workflow

| 입력 | 설명 |
|------|------|
| environment | `dev` / `prod` |

### 배포 흐름

```
서비스 레포 push
  → GitHub Actions
    → 테스트 → Docker 빌드 (arm64) → ECR push
    → cloud 레포 clone
    → kustomization.yaml 이미지 태그 업데이트
    → cloud 레포 push
  → ArgoCD 감지 (3분 이내)
    → kubectl apply -k → Rolling Update
```

### 환경별 차이

| 항목 | dev | prod |
|------|-----|------|
| 트리거 | `dev` 브랜치 push (자동) | workflow_dispatch (수동) |
| ECR 레포 | `dev-dojangkok-{서비스}` | `prod-dojangkok-{서비스}` |
| overlay 경로 | `k8s/apps/overlays/dev` | `k8s/apps/overlays/prod` |
| GitHub Environment | `3-v3-dev` | `3-v3-prod` |

**필요 Secrets (서비스 레포):**
- `AWS_ROLE_ARN` — ECR push용 OIDC IAM Role
- `AWS_REGION` — `ap-northeast-2`
- `CLOUD_REPO_PAT` — cloud 레포 push용 PAT
- `S3_BUCKET_NAME` — FE .env 다운로드용 (FE만)
