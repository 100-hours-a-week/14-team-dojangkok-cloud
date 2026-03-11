# V3 Secret 관리 방식 설계 (v0.1.0)

- 작성일: 2026-03-11
- 최종수정일: 2026-03-11
- 작성자: jsh
- 상태: draft
- 관련문서: `cicd-plan.md` §7, `../../../project/reports/2026-03-10_v3-k8s-manifest-deploy_report.md`

---

## 1. 배경

V3 K8S에 ArgoCD를 도입하면 Git이 Single Source of Truth가 된다. Deployment, ConfigMap, Service 등은 Git에 평문으로 커밋하면 되지만, **Secret은 민감 정보를 포함**하므로 별도의 관리 방식이 필요하다.

현재 Cloud 레포는 **Public**이므로 Git에 민감 정보를 넣을 수 없다. Private 전환 시 선택지가 넓어진다.

---

## 2. 현재 환경설정 관리 방식

### V2 (EC2 + Docker)

| 서비스 | 민감 정보 저장소 | 전달 방식 |
|--------|----------------|----------|
| BE (Spring Boot) | **S3** (`application-dev.yaml` 통째) | CI가 S3 다운로드 → CodeDeploy ZIP → EC2에서 docker-compose 마운트 |
| FE (Next.js) | **S3** (`.env`) | CI가 S3 다운로드 → `$GITHUB_ENV` → Docker build-arg (빌드타임) |
| AI (FastAPI) | **GCP Secret Manager** (4개 key-value) | VM startup script에서 `gcloud secrets access` → `.env` 생성 |

### V3 수동 배포 (2026-03-10 검증)

| 서비스 | 방식 | 내용 |
|--------|------|------|
| BE | `kubectl create secret --from-file` | S3에서 application.yaml 수동 다운로드 → Secret 생성 |
| AI | `kubectl create secret --from-literal` | 4개 값을 직접 입력 |
| FE | 없음 | 런타임 Secret 없음 (빌드타임 변수만) |

---

## 3. 암호화 대상 목록

### Backend — application.yaml (파일 통째)

Spring 외부 설정 파일 하나에 아래 민감 정보가 모두 포함:

| 항목 | 민감 이유 |
|------|----------|
| DB host/port/username/password | 데이터베이스 접근 |
| Redis host/password | 캐시 접근 |
| JWT secret key | 토큰 위조 가능 |
| S3 bucket 설정 | 파일 저장소 접근 |
| RabbitMQ 연결 정보 (user:pass) | 메시지 큐 접근 |

### AI Server — 4개 key-value

| 키 | 민감 이유 |
|----|----------|
| `VLLM_API_KEY` | vLLM 인증 |
| `OCR_API` | Upstage API 과금 키 |
| `BACKEND_INTERNAL_TOKEN` | 내부 서비스 인증 |
| `RABBITMQ_URL` | MQ 접근 (비밀번호 포함) |

### Frontend — 없음

`NEXT_PUBLIC_*`는 빌드타임에 이미지에 포함되며 민감하지 않음 (API URL 등 공개 가능한 값).

---

## 4. 선택지 비교

### 4.1 각 방식 작동 원리

#### A. ESO + AWS SM/SSM (External Secrets Operator)

```
AWS SM/SSM (실제 값 저장)
       │
       │ ESO가 주기적 sync (refreshInterval)
       ▼
K8S Secret 자동 생성/갱신

Git에는 ExternalSecret 리소스만 커밋 (키 이름 참조, 값 없음)
```

- 클러스터에 ESO Helm chart 설치 필요
- ArgoCD가 ExternalSecret을 sync → ESO가 SM/SSM에서 값 조회 → K8S Secret 생성
- Secret 변경: SM/SSM에서 값 수정 → ESO가 자동 반영

#### B. SOPS + AWS KMS

```
로컬: sops --encrypt secrets.yaml → 암호화된 파일 Git push
                    │
       ArgoCD가 Git pull
                    │
       helm-secrets 플러그인이 KMS에 복호화 요청
                    │
       KMS가 복호화 키 반환 → 평문 복원 → K8S Secret 생성
```

- 추가 설치: ArgoCD에 helm-secrets/SOPS 플러그인만
- ArgoCD Pod에 KMS Decrypt IAM 권한 필요 (Node IAM role)
- Secret 변경: 로컬에서 값 수정 → sops 재암호화 → Git push → ArgoCD sync

#### C. Sealed Secrets

```
로컬: kubeseal --cert pub.pem < secret.yaml > sealed.yaml → Git push
                    │
       ArgoCD가 Git pull → SealedSecret 리소스 적용
                    │
       클러스터 내 Controller가 개인키로 복호화 → K8S Secret 생성
```

- 클러스터에 Sealed Secrets Controller 설치 필요
- 비대칭 암호화 (공개키=암호화, 개인키=복호화)
- 클러스터 재생성 시 **개인키 백업 필수** (없으면 기존 Secret 복호화 불가)

#### D. CI kubectl (GitOps 아님)

```
GitHub Actions CD:
  1. S3/SSM/GitHub Secrets에서 값 조회
  2. kubectl create secret ... (클러스터에 직접 push)
  3. ArgoCD는 Secret 외 리소스만 sync
```

- 추가 설치 없음
- GitOps 원칙 위반 (Secret이 Git에 선언되지 않음)
- CI Runner에서 K8S API 접근 필요 (네트워크 문제)

### 4.2 비교 매트릭스

| 기준 | A. ESO+SM/SSM | B. SOPS+KMS | C. Sealed Secrets | D. CI kubectl |
|------|:---:|:---:|:---:|:---:|
| **Public repo 안전** | O (값 없음) | X (암호문 노출) | X (암호문 노출) | O (값 없음) |
| **Private repo 안전** | O | **O** | **O** | O |
| **GitOps 완전성** | **완전** | **완전** | **완전** | 불완전 |
| **Git에 민감정보** | 없음 | 암호문 | 암호문 | 없음 |
| **변경 이력 추적** | SM/SSM (CloudTrail) | **Git log** | **Git log** | GitHub Secrets 이력 |
| **PR 리뷰 가능** | X (외부 저장소) | **O** (키 이름 보임) | **O** | X |
| **자동 갱신** | O (refreshInterval) | X | X | X |
| **추가 설치** | ESO (Helm) | ArgoCD 플러그인 | Controller (Helm) | 없음 |
| **외부 서비스 의존** | SM/SSM | KMS | 없음 | S3/SSM/GitHub |
| **비용** | SSM 무료 / SM $0.40/secret/월 | KMS $1/키/월 | 무료 | 무료 |
| **클러스터 재생성 시** | SM/SSM에 값 유지 | KMS 키 유지 | **키 백업 필수** | 재실행하면 됨 |
| **업계 사용 빈도** | 높음 (대규모) | **높음** (GitOps) | 중간 | 낮음 (임시용) |

---

## 5. Public vs Private Repo에 따른 추천

### Public Repo (현재)

| 방식 | 적합도 | 이유 |
|------|:------:|------|
| A. ESO + SM/SSM | **O** | Git에 값 없음, 안전 |
| B. SOPS + KMS | **X** | 암호문이 전 세계에 공개 |
| C. Sealed Secrets | **X** | 암호문이 전 세계에 공개 |
| D. CI kubectl | **△** | 안전하지만 GitOps 불완전 |

### Private Repo (전환 시)

| 방식 | 적합도 | 이유 |
|------|:------:|------|
| A. ESO + SM/SSM | **O** | 안전, 자동 갱신 |
| B. SOPS + KMS | **O** | Git 중심, 변경 추적, 업계 표준 |
| C. Sealed Secrets | **O** | 외부 의존 없음, 단순 |
| D. CI kubectl | **△** | GitOps 불완전 |

---

## 6. SOPS + KMS 상세 (Private repo 전환 시 추천)

### 장점
- **GitOps 완전**: Secret도 Git에 선언 (암호화 상태)
- **변경 이력**: `git log`로 Secret 변경 추적 가능
- **PR 리뷰**: 암호문이지만 키 이름/구조 변경은 리뷰 가능
- **추가 인프라 최소**: ArgoCD 플러그인 + KMS 키 하나
- **이중 보안**: Private repo 접근 제한 + KMS 암호화

### 구성 요소

```
[로컬 개발 환경]
  └── SOPS CLI (brew install sops)
       └── ~/.sops.yaml (KMS ARN 설정)

[AWS]
  └── KMS Key (ap-northeast-2)
       ├── ArgoCD IAM role → kms:Decrypt
       └── 개발자 IAM user → kms:Encrypt, kms:Decrypt

[ArgoCD]
  └── helm-secrets 플러그인 (또는 ksops + Kustomize)
       └── SOPS 바이너리 포함
```

### 파일 구조 예시 (Kustomize + SOPS)

```
k8s/apps/
├── base/
│   ├── backend/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── configmap.yaml
│   └── ...
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   ├── patches/
    │   └── secrets/
    │       ├── backend-secret.enc.yaml    ← SOPS 암호화
    │       └── ai-server-secret.enc.yaml  ← SOPS 암호화
    └── prod/
        ├── kustomization.yaml
        └── secrets/
            ├── backend-secret.enc.yaml
            └── ai-server-secret.enc.yaml
```

### Secret 변경 워크플로우

```
1. sops secrets/backend-secret.enc.yaml    # 에디터에서 평문 편집
2. 저장 시 자동 재암호화
3. git add → git commit → git push
4. ArgoCD가 감지 → SOPS 복호화 → K8S Secret 업데이트
5. Pod 재시작 (Secret 변경 감지 시)
```

---

## 7. ESO + SM/SSM 상세 (Public repo 유지 시 추천)

### 장점
- **Public repo 안전**: Git에 값이 전혀 없음
- **자동 갱신**: SM/SSM 값 변경 시 ESO가 자동 반영
- **중앙 관리**: 여러 클러스터/환경의 Secret을 SM/SSM에서 통합 관리

### 구성 요소

```
[AWS]
  ├── SSM Parameter Store (key-value, 무료, 4KB 한도)
  │   ├── /dojangkok/dev/vllm-api-key
  │   ├── /dojangkok/dev/ocr-api
  │   ├── /dojangkok/dev/backend-internal-token
  │   └── /dojangkok/dev/rabbitmq-url
  └── Secrets Manager (파일, $0.40/secret/월, 64KB 한도)
      └── dojangkok/dev/backend-application-yaml

[K8S Cluster]
  └── ESO (Helm install)
       ├── ClusterSecretStore (AWS 인증 설정)
       └── ExternalSecret → K8S Secret 생성
```

### ExternalSecret 예시 (Git에 커밋하는 것)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ai-server-secret
  namespace: dojangkok
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-parameter-store
    kind: ClusterSecretStore
  target:
    name: ai-server-secret
  data:
    - secretKey: VLLM_API_KEY
      remoteRef:
        key: /dojangkok/dev/vllm-api-key
    - secretKey: OCR_API
      remoteRef:
        key: /dojangkok/dev/ocr-api
    - secretKey: BACKEND_INTERNAL_TOKEN
      remoteRef:
        key: /dojangkok/dev/backend-internal-token
    - secretKey: RABBITMQ_URL
      remoteRef:
        key: /dojangkok/dev/rabbitmq-url
```

---

## 8. 결정 필요 사항

| # | 질문 | 선택지 |
|---|------|--------|
| 1 | **Repo 공개 범위** | Public 유지 → ESO / Private 전환 → SOPS 가능 |
| 2 | **매니페스트 구조** | Kustomize (base + overlay) / Helm chart |
| 3 | **BE application.yaml 저장** | SM 통째 저장 / 개별 키 분리 |
| 4 | **FE 빌드 변수 관리** | S3 유지 / GitHub Secrets 이관 |
| 5 | **KMS 키 관리 (SOPS 시)** | 키 생성 주체, 접근 권한 범위 |
