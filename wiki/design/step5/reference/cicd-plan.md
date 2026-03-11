# 5단계: V3 CI/CD 설계 (v1.0.0)

- 작성일: 2026-03-09
- 최종수정일: 2026-03-09
- 작성자: infra (claude-code)
- 상태: draft
- 관련문서: `./design-step5.md` (v3.0.0), `./iac-plan.md` (v1.0.0)

> **스코프**: V2 CI/CD(CodeDeploy/MIG) → V3 K8S CI/CD로 전환.
> CI(빌드/테스트/이미지 푸시)는 V2 패턴을 계승하고, CD(배포)를 K8S GitOps 방식으로 변경한다.

---

## 목차

1. [V2 → V3 변경 요약](#1-v2--v3-변경-요약)
2. [CI 파이프라인 — GitHub Actions](#2-ci-파이프라인--github-actions)
3. [CD 방식 선택 — ArgoCD vs kubectl](#3-cd-방식-선택--argocd-vs-kubectl)
4. [ArgoCD 구성](#4-argocd-구성)
5. [매니페스트 관리](#5-매니페스트-관리)
6. [이미지 태깅 & 배포 트리거](#6-이미지-태깅--배포-트리거)
7. [Secret 관리](#7-secret-관리)
8. [롤백 전략](#8-롤백-전략)
9. [Health Check — K8S Probe](#9-health-check--k8s-probe)
10. [구현 순서](#10-구현-순서)

---

## 1. V2 → V3 변경 요약

| 항목 | V2 | V3 |
|------|-----|-----|
| **CD 도구** | CodeDeploy (BE/FE) + MIG Rolling (AI) | ArgoCD (GitOps) |
| **배포 대상** | EC2 (AWS) + GCE MIG (GCP) | K8S Pod (AWS 단일) |
| **설정 소스** | S3 (`application.yaml`, `.env`) | K8S ConfigMap + Secret |
| **배포 단위** | VM 1대 = 앱 1개 | Pod (노드 공유) |
| **롤백** | 수동 (이전 Template/이미지) | `git revert` → ArgoCD 자동 동기화 |
| **Health Check** | bash 루프 (curl) | K8S Readiness/Liveness Probe |
| **Downtime** | AllAtOnce → 가능 | Rolling Update → 0 |
| **CI** | **변경 없음** | GitHub Actions 계승 |

### 변경되지 않는 것

- GitHub Actions CI (lint → test → build → Docker → ECR push)
- ECR 이미지 저장소 (data source로 참조)
- 이미지 태깅 (`:latest` + `:${SHA}`)
- OIDC 인증 (AWS IAM Role)

### 변경되는 것

- CodeDeploy / MIG → ArgoCD
- S3 config download → K8S ConfigMap/Secret
- appspec.yml / deploy.sh → K8S Deployment YAML
- docker-compose up → `kubectl apply` (ArgoCD 자동)
- GCP CI/CD 전체 → 제거 (AI Server가 K8S Pod로 이동)

---

## 2. CI 파이프라인 — GitHub Actions

V2 CI를 그대로 계승하되, CD 단계를 ArgoCD 트리거로 교체.

### BE (Spring Boot)

```
Trigger: push to dev/main
  ↓
① Checkout + Java 21 + Gradle
② ./gradlew test
③ ./gradlew bootJar
④ Docker build (ARM64) → ECR push (:latest + :SHA)
⑤ [V3 추가] 매니페스트 레포 이미지 태그 업데이트
```

### FE (Next.js)

```
Trigger: push to dev/main
  ↓
① Checkout + Node 22
② Prettier + lint
③ npm run test:run
④ Docker build (ARM64) → ECR push (:latest + :SHA)
⑤ [V3 추가] 매니페스트 레포 이미지 태그 업데이트
```

### AI Server (FastAPI)

```
Trigger: push to dev/main
  ↓
① Checkout + Python 3.10 + uv
② Ruff lint/format
③ Pytest
④ Docker build → ECR push (:latest + :SHA)    ← GAR에서 ECR로 변경
⑤ [V3 추가] 매니페스트 레포 이미지 태그 업데이트
```

> AI Server: GCP GAR → AWS ECR로 이동. GCP CI/CD 워크플로우(WIF, MIG rolling) 전체 제거.

### ⑤ 매니페스트 업데이트 스텝 (공통)

```yaml
# GitHub Actions step (CI 워크플로우 마지막)
- name: Update K8S manifest
  run: |
    git clone https://x-access-token:${{ secrets.MANIFEST_REPO_TOKEN }}@github.com/team/k8s-manifests.git
    cd k8s-manifests

    # Plain YAML에서 이미지 태그 교체
    IMAGE="${ECR_REGISTRY}/dojangkok-be:${GITHUB_SHA}"
    sed -i "s|image: .*dojangkok-be:.*|image: ${IMAGE}|" apps/backend/deployment.yaml

    git config user.name "github-actions"
    git config user.email "actions@github.com"
    git add .
    git commit -m "deploy(be): ${GITHUB_SHA::7}"
    git push
```

> ArgoCD가 매니페스트 레포 변경을 감지하여 자동 배포.

---

## 3. CD 방식 선택 — ArgoCD vs kubectl

### 비교

| 항목 | ArgoCD (GitOps) | kubectl apply |
|------|-----------------|--------------|
| **소스 오브 트루스** | Git 레포 (선언적) | CI 파이프라인 (명령적) |
| **Drift 감지** | 자동 (실시간 비교) | 없음 |
| **롤백** | `git revert` → 자동 | 수동 `kubectl rollout undo` |
| **상태 가시성** | ArgoCD UI (웹) | `kubectl get` (CLI) |
| **복잡도** | ArgoCD 설치/운영 추가 | 단순 |
| **보안** | Git RBAC + K8S RBAC 분리 | CI에 kubeconfig 노출 필요 |
| **멀티 환경** | Application 분리 | 스크립트로 분기 |

### 결정: ArgoCD

**근거:**
1. design-step5.md §17에서 `argocd` Namespace 이미 설계
2. Drift 자동 감지 — 수동 kubectl 변경 시 자동 복원
3. Git 기반 롤백 — 커밋 히스토리가 배포 히스토리
4. 웹 UI — 배포 상태 시각화 (kubectl 숙련도 불필요)

> **단계적 접근**: 초기에 kubectl로 수동 배포하여 매니페스트 검증 → 이후 ArgoCD 연동.

---

## 4. ArgoCD 구성

### 설치

```bash
# Helm 설치 (권장)
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --set server.service.type=NodePort
```

> ArgoCD UI는 NodePort로 노출. 운영자만 접근하므로 ALB 노출 불필요 — kubectl port-forward 또는 SSH 터널로 접근.

### Application 정의

서비스당 1개 Application:

```yaml
# argocd/apps/backend.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: backend
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/team/k8s-manifests.git
    targetRevision: main
    path: apps/backend          # Plain YAML 디렉터리
  destination:
    server: https://kubernetes.default.svc
    namespace: dojangkok
  syncPolicy:
    automated:
      prune: true               # Git에서 삭제된 리소스 제거
      selfHeal: true            # 수동 변경 자동 복원
    syncOptions:
    - CreateNamespace=false     # Namespace는 사전 생성
```

### Application 목록

| Application | 소스 경로 | 대상 NS | 자동 동기화 |
|-------------|----------|---------|-----------|
| backend | `apps/backend/` | dojangkok | Yes |
| frontend | `apps/frontend/` | dojangkok | Yes |
| ai-server | `apps/ai-server/` | dojangkok | Yes |
| networking | `apps/networking/` | (다수) | Yes |
| monitoring | `apps/monitoring/` | monitoring | Yes (Phase 3 이후) |

---

## 5. 매니페스트 관리

### 레포지토리 구조

**매니페스트 전용 레포** (앱 코드와 분리):

```
k8s-manifests/                    ← 별도 Git 레포
├── apps/
│   ├── backend/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   └── hpa.yaml
│   ├── frontend/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── configmap.yaml
│   ├── ai-server/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── configmap.yaml
│   └── networking/
│       ├── namespaces.yaml
│       ├── networkpolicies.yaml
│       ├── gateway.yaml          # Gateway API HTTPRoute
│       └── rbac.yaml
├── argocd/
│   └── apps/                     # ArgoCD Application 정의
│       ├── backend.yaml
│       ├── frontend.yaml
│       ├── ai-server.yaml
│       └── networking.yaml
└── README.md
```

### Plain YAML 방식

Kustomize/Helm 없이 순수 YAML 사용:
- 파일 = 리소스 (1:1 대응)
- ArgoCD는 디렉터리 내 모든 YAML을 자동 적용
- 환경별 분리가 필요하면 `apps-dev/`, `apps-prod/` 디렉터리로 분리

> 단계적: Plain YAML로 시작 → 환경 분리 필요 시 Helm Chart로 전환.

### 앱 코드 레포 vs 매니페스트 레포

| 항목 | 앱 코드 레포 | 매니페스트 레포 |
|------|------------|--------------|
| 내용 | 소스 코드, Dockerfile, CI 워크플로우 | K8S YAML, ArgoCD 설정 |
| 변경 주체 | 개발자 | CI 자동 (이미지 태그) + 인프라 (설정) |
| 변경 빈도 | 높음 | 이미지 태그 업데이트 위주 |
| 접근 권한 | 개발자 + CI | CI + 인프라 담당자 |

> 분리 이유: 앱 코드 push가 ArgoCD를 불필요하게 트리거하지 않도록. CI가 명시적으로 매니페스트 레포를 업데이트할 때만 배포 발생.

---

## 6. 이미지 태깅 & 배포 트리거

### 태깅 전략

V2와 동일:

```
{ECR_REGISTRY}/dojangkok-be:latest
{ECR_REGISTRY}/dojangkok-be:{GITHUB_SHA}
```

- `:latest` — 최신 빌드 참조용 (배포에 직접 사용하지 않음)
- `:{SHA}` — 배포에 사용. 불변(immutable) 태그.

### 배포 흐름

```
개발자가 앱 코드 push
  ↓
GitHub Actions CI 실행
  ↓
Docker 이미지 빌드 + ECR push (:SHA)
  ↓
매니페스트 레포의 deployment.yaml 이미지 태그 업데이트
  ↓
ArgoCD가 변경 감지 → K8S Deployment 업데이트
  ↓
Rolling Update (maxSurge=1, maxUnavailable=0)
  ↓
Readiness Probe 통과 후 트래픽 수신
```

### 환경별 분리

| 환경 | 트리거 브랜치 | 매니페스트 경로 | ArgoCD App |
|------|-------------|--------------|------------|
| dev | `dev` | `apps/backend/` | backend-dev |
| prod | `main` | `apps-prod/backend/` (또는 별도 브랜치) | backend-prod |

> 초기에는 dev 환경만. prod 분리는 안정화 후.

---

## 7. Secret 관리

### V2 현황

| 서비스 | Secret | 저장 위치 |
|--------|--------|----------|
| BE | `application.yaml` (DB 비밀번호, API 키) | S3 |
| FE | `.env` (API URL, 빌드 변수) | S3 |
| AI | Terraform vars (`vllm_api_key`, `ocr_api`) | Terraform state |

### V3 방식 — 단계적 접근

#### Phase A: 수동 Secret (초기)

```bash
# 클러스터에 직접 생성
kubectl create secret generic db-credentials \
  --namespace dojangkok \
  --from-literal=password='xxxx'

kubectl create secret generic api-keys \
  --namespace dojangkok \
  --from-literal=vllm-api-key='xxxx' \
  --from-literal=ocr-api='xxxx'
```

- Git에 커밋하지 않음 (보안)
- ArgoCD sync에서 Secret은 제외 (prune 대상 아님)
- 단점: 수동 관리, 히스토리 없음

#### Phase B: External Secrets Operator (안정화 후)

AWS Secrets Manager에서 자동 동기화:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: dojangkok
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-sm
    kind: ClusterSecretStore
  target:
    name: db-credentials
  data:
  - secretKey: password
    remoteRef:
      key: dojangkok/db/password
```

> Phase A로 시작하여 운영 안정화 후 Phase B로 전환. Secret 개수가 적으므로 (5~6개) Phase A만으로도 충분할 수 있음.

---

## 8. 롤백 전략

### Git 기반 롤백

```bash
# 1. 문제 커밋 확인
git log --oneline apps/backend/deployment.yaml

# 2. 이전 이미지 태그로 복원
git revert HEAD
git push

# 3. ArgoCD가 자동 동기화 → 이전 이미지로 롤백
```

### K8S 네이티브 롤백 (긴급)

```bash
# ArgoCD 우회, 즉시 롤백
kubectl rollout undo deployment/be -n dojangkok

# ArgoCD selfHeal이 Git 상태로 되돌릴 수 있으므로
# 긴급 시 selfHeal 일시 비활성화 후 롤백
```

### 롤백 시나리오

| 상황 | 방법 | 소요 시간 |
|------|------|----------|
| 코드 버그 (일반) | `git revert` → ArgoCD sync | ~2분 |
| 긴급 장애 | `kubectl rollout undo` | ~30초 |
| 설정 오류 | ConfigMap 수정 → Pod restart | ~1분 |

---

## 9. Health Check — K8S Probe

V2의 bash 스크립트 → K8S 네이티브 Probe로 전환.

### BE (Spring Boot Actuator)

```yaml
readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3

livenessProbe:
  httpGet:
    path: /actuator/health/liveness
    port: 8080
  initialDelaySeconds: 60
  periodSeconds: 30
  failureThreshold: 3
```

### FE (Next.js)

```yaml
readinessProbe:
  httpGet:
    path: /health-check
    port: 3000
  initialDelaySeconds: 10
  periodSeconds: 10
  failureThreshold: 3

livenessProbe:
  httpGet:
    path: /health-check
    port: 3000
  initialDelaySeconds: 20
  periodSeconds: 30
  failureThreshold: 3
```

### AI Server (FastAPI)

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 15
  periodSeconds: 10
  failureThreshold: 3

livenessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 30
  periodSeconds: 30
  failureThreshold: 3
```

### Rolling Update 전략

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1           # 새 Pod 1개 먼저 생성
    maxUnavailable: 0     # 기존 Pod 유지 → readiness 통과 후 교체
```

> V2 AllAtOnce 방식의 다운타임 문제 해결. 새 Pod가 Readiness Probe를 통과해야 트래픽 수신.

---

## 10. 구현 순서

```
┌───────────────────────────────────────────┐
│ 1. 매니페스트 레포 생성                      │
│    - Plain YAML 작성 (deployment, service)  │
│    - kubectl apply로 수동 검증               │
└────────────────┬──────────────────────────┘
                 │
┌────────────────▼──────────────────────────┐
│ 2. ArgoCD 설치                              │
│    - Helm 설치 (argocd NS)                  │
│    - Application 생성 (서비스별)             │
│    - 수동 sync 테스트                        │
└────────────────┬──────────────────────────┘
                 │
┌────────────────▼──────────────────────────┐
│ 3. CI 워크플로우 수정                        │
│    - BE/FE: CD 단계를 매니페스트 업데이트로   │
│    - AI: GAR → ECR, MIG → 매니페스트 업데이트 │
│    - CodeDeploy/MIG 단계 제거                │
└────────────────┬──────────────────────────┘
                 │
┌────────────────▼──────────────────────────┐
│ 4. Secret 설정                              │
│    - kubectl create secret (Phase A)        │
│    - ConfigMap 생성                          │
└────────────────┬──────────────────────────┘
                 │
┌────────────────▼──────────────────────────┐
│ 5. 자동 동기화 활성화                        │
│    - ArgoCD automated sync ON               │
│    - selfHeal ON                            │
│    - E2E 배포 테스트                         │
└───────────────────────────────────────────┘
```

> 핵심: **1번에서 kubectl로 매니페스트를 충분히 검증한 후** ArgoCD를 연결. ArgoCD 문제와 매니페스트 문제를 분리하여 디버깅.

---

## 변경 이력

| 버전 | 날짜 | 변경 내용 |
|------|------|----------|
| v1.0.0 | 2026-03-09 | 초안: V2→V3 전환 설계, ArgoCD 선택, Plain YAML, Secret 단계적 접근 |
