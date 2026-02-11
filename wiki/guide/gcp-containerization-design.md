# GCP 컨테이너화 설계문서

- 작성일: 2026-02-11
- 최종수정일: 2026-02-11
- 작성자: waf.jung(정승환)
- 관련문서: ../../../IaC/2-v2/IaC-설계문서-통합본.md

---

## 목차

1. [개요](#1-개요)
2. [아키텍처 제약](#2-아키텍처-제약)
3. [Dockerfile](#3-dockerfile)
4. [docker-compose 구성](#4-docker-compose-구성)
5. [CI/CD 파이프라인](#5-cicd-파이프라인)
6. [산출물 위치](#6-산출물-위치)

---

## 1. 개요

### 전환 배경: V1 → V2 컨테이너 기반 배포

### 1.1 V1 배포 방식과 한계

V1 CI/CD(`14-team-dojangkok-ai/.github/workflows/ai-cicd.yml`)는 **tar.gz 아티팩트를 SSH로 전송하여 VM에 직접 배포**하는 in-place 방식이다.

```
lint-test → build-and-artifact (tar.gz) → deploy
                                            ├─ runner IP 취득 (curl ifconfig.me)
                                            ├─ 임시 방화벽 생성 (runner IP → :22)
                                            ├─ gcloud compute scp (아티팩트 전송)
                                            ├─ gcloud compute ssh
                                            │    ├─ systemctl stop ai-server
                                            │    ├─ tar 풀기 → uv sync (uv.lock 해시 비교)
                                            │    └─ systemctl start ai-server
                                            ├─ health check (외부 IP curl)
                                            └─ 임시 방화벽 삭제
```

**한계**:

| 문제 | 설명 |
|------|------|
| 배포 중 서비스 중단 | `systemctl stop → start` 사이 다운타임 발생 |
| SSH 직접 접속 필요 | runner IP 기반 임시 방화벽 생성/삭제 매 배포마다 반복 |
| VM 내부 상태 의존 | uv.lock 해시 비교로 의존성 동기화 — drift 가능 |
| 스케일링/무중단 배포 불가 | 단일 VM 대상 배포, 수평 확장 구조 없음 |

### 1.2 V2 전환: Docker 컨테이너 기반 CI/CD

V2는 **앱과 의존성을 Docker 이미지로 패키징**하고, Artifact Registry → MIG 롤링 업데이트로 배포한다.

전환 이유:
- **환경 일관성**: 앱 + 런타임 + 의존성을 이미지에 포함 → VM 상태 drift 제거
- **이미지 버전 관리**: Artifact Registry에 SHA 태그로 저장 → 버전 추적, 롤백 용이
- **무중단 배포**: MIG 롤링 업데이트(`max_surge=1, max_unavailable=0`)
- **보안 강화**: SSH 불필요 → 임시 방화벽 제거

**V1 vs V2 비교**:

| 항목 | V1 | V2 |
|------|----|----|
| 아티팩트 | tar.gz | Docker 이미지 |
| 배포 방식 | SSH in-place | MIG 롤링 업데이트 |
| 서비스 중단 | O (`systemctl stop→start`) | X (무중단) |
| 의존성 관리 | VM 내 `uv sync` | 이미지에 포함 |
| SSH 접근 | 임시 방화벽 필요 | 불필요 |
| 스케일링 | 불가 | MIG `target_size` 조정 |
| Health Check | 외부 IP curl | MIG auto-healing |

> Section 5에서 V2 워크플로우의 구체적 구현(Job 구성, 롤링 업데이트 절차)을 다룬다.

### 1.3 IaC 설계: COS → Packer + docker-compose

V2 컨테이너화를 위한 IaC 기반 OS로 처음 검토한 COS(Container-Optimized OS)는 **단일 컨테이너 전용**이라 모니터링 사이드카(node-exporter, promtail 등)를 함께 배치할 수 없었다. 이에 **Packer 커스텀 이미지 + docker-compose** 조합으로 전환하여 멀티 컨테이너 운영을 실현한다.

> COS 제약사항 및 Packer 모듈 설계 상세는 [IaC 설계문서 통합본 §3.7](../../../IaC/2-v2/IaC-설계문서-통합본.md)을 참조한다.

**목표**: Packer + docker-compose 기반 멀티 컨테이너 운영
- Packer 이미지에 Docker, docker-compose-plugin 프리인스톨
- GPU VM에서 nvidia-container-toolkit으로 `runtime: nvidia` 사용
- startup_script에서 `docker compose up -d`만 실행

---

## 2. 아키텍처 제약

### amd64 통일

GCP 서울 리전(asia-northeast3)에는 **T2A(Arm) 인스턴스가 제공되지 않는다**. 따라서 모든 VM과 Docker 이미지를 `linux/amd64`로 통일한다.

| 환경 | 빌드 방식 |
|------|----------|
| CI (GitHub Actions `ubuntu-22.04`) | `docker build --platform linux/amd64` — 네이티브, 빠름 |
| 로컬 (Apple Silicon) | `docker build --platform linux/amd64` — QEMU cross-build, 느리지만 동작 |

### GPU VM

vLLM VM에는 nvidia-container-toolkit이 필수. Packer GPU 이미지(`gpu-base.pkr.hcl`)에 포함하여 `runtime: nvidia`를 사용 가능하게 한다.

---

## 3. Dockerfile

AI Server용 멀티스테이지 빌드. 패키지 매니저로 **uv**를 사용한다.

```dockerfile
# Stage 1: builder
FROM python:3.10-slim AS builder
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY app/ ./app/

# Stage 2: runtime
FROM python:3.10-slim
WORKDIR /app
RUN groupadd -r appuser && useradd -r -g appuser appuser \
    && mkdir -p /var/log/dojangkok/prod \
    && chown -R appuser:appuser /var/log/dojangkok
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/app /app/app
COPY --from=builder /app/pyproject.toml /app/pyproject.toml
ENV PATH="/app/.venv/bin:$PATH"
ENV APP_ENV=prod
USER appuser
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**설계 포인트**:

| 항목 | 설명 |
|------|------|
| 멀티스테이지 | 빌드 도구(uv, gcc 등)를 런타임에 미포함 → 이미지 최소화 |
| uv sync --frozen | lockfile 기반 결정론적 설치 |
| --no-dev | 테스트/린트 패키지 제외 |
| non-root user | `appuser`로 실행, 보안 강화 |

**.dockerignore**: `.git`, `.venv`, `__pycache__`, `.env*`, `tests/`, `dist/`, `*.tar.gz` 제외.

---

## 4. docker-compose 구성

### 공통 패턴

모든 VM의 docker-compose에 적용되는 공통 설정:

| 패턴 | 설명 |
|------|------|
| `network_mode: host` | 호스트 네트워크 직접 사용, 포트 매핑 불필요, 서브넷 내부 통신 단순화 |
| `restart: unless-stopped` | VM 재부팅 시 자동 복구 |
| promtail | `/tmp/promtail-config.yml`을 마운트 (startup_script에서 생성) |
| node-exporter | `prom/node-exporter:v1.9.0`, `/proc`·`/sys`·`/` 마운트 |

### 4.1 AI Server (`docker-compose/ai-server.yml`)

| 서비스 | 이미지 | 포트 | 역할 |
|--------|--------|------|------|
| ai-server | `${AI_SERVER_IMAGE}` (AR에서 pull) | 8000 | FastAPI 메인 서비스 |
| node-exporter | `prom/node-exporter:v1.9.0` | 9100 | 시스템 메트릭 |
| promtail | `grafana/promtail:3.4.2` | 9080 | 로그 수집 → Loki |

**환경변수** (Terraform `templatefile`로 주입):

| 변수 | 설명 |
|------|------|
| `VLLM_BASE_URL` | `http://{vllm_internal_ip}:8001/v1` |
| `VLLM_API_KEY` | vLLM 인증 키 |
| `VLLM_MODEL` | 모델명 |
| `VLLM_LORA_ADAPTER_CHECKLIST` | LoRA 어댑터 |
| `VLLM_LORA_ADAPTER_EASYCONTRACT` | LoRA 어댑터 |
| `CHROMADB_URL` | `http://{chromadb_internal_ip}:8100` |
| `BACKEND_CALLBACK_BASE_URL` | AWS 백엔드 콜백 URL |
| `BACKEND_INTERNAL_TOKEN` | 내부 통신 토큰 |
| `OCR_API` | Upstage OCR API 키 |
| `HTTP_TIMEOUT_SEC` | HTTP 타임아웃 |

### 4.2 vLLM (`docker-compose/vllm.yml`)

| 서비스 | 이미지 | 포트 | 역할 |
|--------|--------|------|------|
| vllm | `${VLLM_IMAGE}` (AR에서 pull) | 8001 | LLM 추론 (GPU) |
| node-exporter | `prom/node-exporter:v1.9.0` | 9100 | 시스템 메트릭 |
| dcgm-exporter | `nvcr.io/nvidia/k8s/dcgm-exporter:3.3.9-3.6.1-ubuntu22.04` | 9400 | GPU 메트릭 |
| promtail | `grafana/promtail:3.4.2` | 9080 | 로그 수집 |

vllm 서비스 특이사항:
- `runtime: nvidia` + `NVIDIA_VISIBLE_DEVICES: all`
- command: `--model`, `--port 8001`, `--enforce-eager`, `--enable-lora`, `--lora-modules`, `--api-key`

### 4.3 ChromaDB (`docker-compose/chromadb.yml`)

| 서비스 | 이미지 | 포트 | 역할 |
|--------|--------|------|------|
| chromadb | `chromadb/chroma:${CHROMADB_VERSION:-latest}` | 8100 | 벡터 DB |
| node-exporter | `prom/node-exporter:v1.9.0` | 9100 | 시스템 메트릭 |
| promtail | `grafana/promtail:3.4.2` | 9080 | 로그 수집 |

ChromaDB 특이사항:
- named volume `chromadb-data` → `/chroma/chroma` (데이터 영속화)
- 공식 이미지 사용, 커스텀 빌드 없음

---

## 5. CI/CD 파이프라인

### 5.1 AS-IS: SSH in-place 배포

```
lint-test → build-and-artifact (tar.gz) → deploy
                                            ├─ 임시 방화벽 생성 (runner IP → :22)
                                            ├─ gcloud compute scp (아티팩트 전송)
                                            ├─ gcloud compute ssh (systemctl stop → tar 풀기 → uv sync → start)
                                            ├─ health check (외부 IP 직접 curl)
                                            └─ 임시 방화벽 삭제
```

**문제점**:
- 배포 중 서비스 중단 (systemctl stop → start)
- VM에 직접 SSH 접근 필요 → 임시 방화벽 열고 닫기
- 아티팩트 전송 + uv sync 시간으로 배포 느림
- VM 내부 상태에 의존 (drift 발생 가능)

### 5.2 TO-BE: Docker → AR → MIG 롤링 업데이트

```
lint-test → build-push (Docker → AR) → deploy
                                          ├─ 현재 MIG의 Instance Template 조회
                                          ├─ Template 복사 + startup-script 내 이미지 태그 교체
                                          ├─ MIG 롤링 업데이트 (max-surge=1, max-unavailable=0)
                                          ├─ 완료 대기 (timeout 300s)
                                          └─ 이전 Template 정리 (최근 5개 유지)
```

**제거된 것**:

| 항목 | 이유 |
|------|------|
| SSH 접속 (gcloud compute ssh/scp) | MIG가 VM을 자동 교체 |
| 임시 방화벽 | SSH 불필요 |
| tar.gz 아티팩트 | Docker 이미지로 대체 |
| VM 내 uv sync, systemctl | 컨테이너에 의존성 포함 |
| 외부 IP health check | MIG auto-healing으로 대체 |

### 5.3 워크플로우 상세

**파일**: `workflows/1-bigbang/AI/ai-cicd.yml`

**트리거**:

| 이벤트 | 브랜치 | 실행 Job |
|--------|--------|---------|
| `pull_request` → main, dev | - | lint-test |
| `push` → main (PR 머지) | main | lint-test → build-push → deploy |
| `workflow_dispatch` | - | 모든 job |

paths-ignore: `.github/workflows/**`, `**.md`, `docs/**`

**Job 1: lint-test**

```
1. checkout
2. uv setup (캐시: uv.lock)
3. uv python install 3.10
4. uv sync --frozen
5. ruff check . (non-blocking)
6. ruff format --check . (non-blocking)
7. pytest tests/ -v --cov (tests/ 존재 시)
```

`continue-on-error: true` — lint/test 실패해도 build-push 진행.

**Job 2: build-push** (main push only)

```
1. checkout
2. GCP OIDC 인증 (Workload Identity)
3. gcloud auth configure-docker asia-northeast3-docker.pkg.dev
4. 이미지 태그 생성: SHA 앞 7자리
5. docker build --platform linux/amd64 \
     -t $AR_REPO/ai-server:$SHA_SHORT \
     -t $AR_REPO/ai-server:latest
6. docker push (SHA태그 + latest)
```

**Job 3: deploy** (main push only)

```
1. GCP OIDC 인증
2. 현재 MIG의 Instance Template 이름 조회
3. 기존 Template의 startup-script 추출
4. sed로 ai-server 이미지 태그 교체
5. 새 Template 생성 (source-instance-template + metadata 덮어쓰기)
6. MIG 롤링 업데이트 시작 (max-surge=1, max-unavailable=0)
7. 완료 대기 (timeout 300s)
8. 이전 Template 정리 (최근 5개 유지, 나머지 삭제)
```

**concurrency**: `ai-server-cicd-${{ github.ref }}` 그룹, cancel-in-progress.

### 5.4 GitHub Secrets 목록

| Secret | 값 | 용도 |
|--------|-----|------|
| `WORKLOAD_IDENTITY_PROVIDER` | `projects/{num}/locations/global/...` | GCP OIDC 인증 |
| `GCP_SERVICE_ACCOUNT` | `github-actions-sa@{project}.iam.gserviceaccount.com` | SA 이메일 |
| `GCP_PROJECT_ID` | GCP 프로젝트 ID | gcloud 명령 대상 |
| `GCP_ZONE` | `asia-northeast3-a` | MIG/VM 존 |
| `AR_REPO` | `asia-northeast3-docker.pkg.dev/{project}/dojangkok-ai` | Docker push 대상 |
| `MIG_NAME` | `dojangkok-{env}-ai-server-mig` | 롤링 업데이트 대상 |

Secrets 위치: AI 레포(`14-team-DojangKok-ai`) → Environments → `1-bigbang`

### 5.5 vLLM / ChromaDB 수동 배포

MIG가 아닌 단일 VM이므로 롤링 업데이트 불가. IAP SSH를 통한 수동 배포.

| VM | 트리거 | 방식 | 이유 |
|----|--------|------|------|
| vLLM | 모델/vLLM 버전 변경 시 수동 | IAP SSH → docker compose pull/up | 모델 캐시/LoRA 보존, GPU 할당 1개로 surge 불가 |
| ChromaDB | 버전 업 시 수동 | IAP SSH → docker compose pull/up | 공식 이미지, 볼륨 데이터 보존 |

```bash
gcloud compute ssh $VM --tunnel-through-iap \
  --command="cd /opt/app && docker compose pull && docker compose up -d"
```

`workflow_dispatch`로 GitHub Actions 자동화도 가능.

IAP 필요 조건:
- 방화벽: `35.235.240.0/20 → tcp:22` (이미 존재)
- SA 역할: `roles/iap.tunnelResourceAccessor` (이미 부여)

---

## 6. 산출물 위치

| 파일 | 위치 | 설명 |
|------|------|------|
| Dockerfile | `14-team-dojangkok-ai/Dockerfile` | AI Server 빌드 (원본) |
| .dockerignore | `14-team-dojangkok-ai/.dockerignore` | 빌드 컨텍스트 제외 |
| Dockerfile (사본) | `Docker/v2/gcp/ai-server/Dockerfile` | cloud 레포 보관용 |
| .dockerignore (사본) | `Docker/v2/gcp/ai-server/.dockerignore` | cloud 레포 보관용 |
| ai-server compose | `Docker/v2/gcp/ai-server/docker-compose.yml` | AI Server compose |
| vllm compose | `Docker/v2/gcp/vllm/docker-compose.yml` | vLLM compose |
| chromadb compose | `Docker/v2/gcp/chromadb/docker-compose.yml` | ChromaDB compose |
| ai-cicd.yml | `workflows/1-bigbang/AI/ai-cicd.yml` | CI/CD 워크플로우 |
| startup-ai-server.sh | `IaC/2-v2/gcp/environments/{dev,prod}/scripts/` | MIG startup script |
| cpu-base.pkr.hcl | `IaC/2-v2/gcp/packer/cpu-base.pkr.hcl` | Packer CPU 이미지 |
| gpu-base.pkr.hcl | `IaC/2-v2/gcp/packer/gpu-base.pkr.hcl` | Packer GPU 이미지 |
