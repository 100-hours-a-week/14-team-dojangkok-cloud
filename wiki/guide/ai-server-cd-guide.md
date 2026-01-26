# AI Server CD 설정 가이드

- 작성일: 2026-01-08
- 최종수정일: 2026-01-26

## 목차

1. [개요](#개요)
   - [기술 스택](#기술-스택)
   - [배포 방식 요약](#배포-방식-요약)
2. [CD 워크플로우](#cd-워크플로우)
   - [파일 위치](#파일-위치)
   - [Deploy Job](#deploy-job)
3. [GitHub Secrets 설정](#github-secrets-설정)
4. [CD 흐름](#cd-흐름)
5. [주요 특징](#주요-특징)
   - [Workload Identity Federation (OIDC)](#workload-identity-federation-oidc)
   - [동적 방화벽 규칙](#동적-방화벽-규칙)
   - [uv 패키지 관리](#uv-패키지-관리)
6. [systemd 서비스 설정](#systemd-서비스-설정)
7. [롤백 절차](#롤백-절차)
8. [실패 시 대응](#실패-시-대응)
9. [환경 변수 관리](#환경-변수-관리)
10. [향후 계획](#향후-계획)

<br>

## 개요

이 문서는 **FastAPI(AI Server) 프로젝트**의 GitHub Actions CD 설정을 다룬다.

> **참고**: CI/CD가 하나의 워크플로우(`ai-cicd.yml`)로 통합되어 있음. 이 문서는 CD 부분(deploy job)만 다룸. CI 부분은 [[ai-server-ci-guide]] 참조.

### 기술 스택

| 항목 | 내용 |
|------|------|
| 프레임워크 | FastAPI |
| 런타임 | Python 3.10 |
| 패키지 관리 | uv (uv.lock) |
| 프로세스 관리 | systemd |
| 인프라 | GCP Compute Engine (GPU Instance) |
| 인증 | Workload Identity Federation (OIDC) |


### 배포 방식 요약

| 항목 | 내용 |
|------|------|
| 아티팩트 | CI에서 생성된 tar.gz |
| 배포 방식 | Artifact 다운로드 → uv sync → 서비스 재시작 |
| 다운타임 | 서비스 재시작 시간 |
| 롤백 방식 | Re-run (해당 시점 아티팩트 재배포) |

<br>

## CD 워크플로우

### 파일 위치
```
.github/workflows/ai-cicd.yml
```

> CI/CD 통합 워크플로우. deploy job은 `if: github.ref == 'refs/heads/main'` 조건으로 main 브랜치에서만 실행됨.

### 동작 시나리오

| 이벤트 | lint-test | build-artifact | deploy |
|--------|:---------:|:--------------:|:------:|
| PR 생성/업데이트 | O | O | X (`refs/pull/...`) |
| PR 머지 (main push) | O | O | O (`refs/heads/main`) |
| 롤백 (Re-run) | O | O | O |

### Deploy Job

```yaml
  # ============================================
  # CD: Deploy (main 브랜치만)
  # ============================================
  deploy:
    name: Deploy to GCP
    if: github.ref == 'refs/heads/main'
    needs: build-and-artifact
    runs-on: ubuntu-22.04
    environment: 1-bigbang
    permissions:
      contents: read
      id-token: write
      actions: read
    env:
      GCP_PROJECT_ID: ${{ secrets.GCP_PROJECT_ID }}
      GCP_ZONE: ${{ secrets.GCP_ZONE }}
      GCP_INSTANCE: ${{ secrets.GCP_INSTANCE }}
    steps:
      - name: Get Runner IP
        id: ip
        run: echo "ip=$(curl -s ifconfig.me)" >> $GITHUB_OUTPUT

      - name: Authenticate to GCP (OIDC)
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

      - name: Setup gcloud CLI
        uses: google-github-actions/setup-gcloud@v2
        with:
          project_id: ${{ env.GCP_PROJECT_ID }}

      - name: Add Firewall Rule
        run: |
          gcloud compute firewall-rules create github-actions-temp-${{ github.run_id }} \
            --allow=tcp:22 \
            --source-ranges=${{ steps.ip.outputs.ip }}/32 \
            --target-tags=ai-server \
            --project=${{ env.GCP_PROJECT_ID }} \
            --description="Temporary rule for GitHub Actions CD"
          echo "Firewall rule created for IP: ${{ steps.ip.outputs.ip }}"

      - name: Download Artifact
        uses: actions/download-artifact@v4
        with:
          name: ai-server-${{ github.sha }}
          path: ./artifact

      - name: Deploy to VM
        run: |
          ARTIFACT_FILE=$(find ./artifact -name "*.tar.gz" | head -1)
          if [ -z "$ARTIFACT_FILE" ]; then
            echo "Artifact not found"
            exit 1
          fi
          echo "Deploying: $ARTIFACT_FILE"

          # Artifact 전송
          gcloud compute scp "$ARTIFACT_FILE" \
            ${{ env.GCP_INSTANCE }}:/tmp/ai-server-deploy.tar.gz \
            --zone=${{ env.GCP_ZONE }}

          # VM에서 배포 실행
          gcloud compute ssh ${{ env.GCP_INSTANCE }} \
            --zone=${{ env.GCP_ZONE }} \
            --command='
              set -e

              # uv 설치 (없는 경우)
              if ! command -v uv &> /dev/null; then
                echo "Installing uv..."
                curl -LsSf https://astral.sh/uv/install.sh | sh
              fi
              export PATH="$HOME/.local/bin:$PATH"

              # 서비스 중단
              sudo systemctl stop ai-server || true

              # 배포
              sudo mkdir -p /app/ai-server
              sudo tar -xzf /tmp/ai-server-deploy.tar.gz -C /app/ai-server

              # 권한 설정 (uv sync 전에 먼저 설정)
              sudo chown -R $(whoami):$(whoami) /app/ai-server

              # uv sync (uv.lock 변경 시에만 재설치)
              cd /app/ai-server
              NEW_HASH=$(md5sum uv.lock | cut -d" " -f1)
              OLD_HASH=""
              if [ -f ".venv/.uv_lock_hash" ]; then
                OLD_HASH=$(cat .venv/.uv_lock_hash)
              fi

              if [ "$NEW_HASH" != "$OLD_HASH" ] || [ ! -d ".venv" ]; then
                echo "uv.lock changed or .venv missing, installing..."
                rm -rf .venv
                $HOME/.local/bin/uv sync --frozen
                echo "$NEW_HASH" > .venv/.uv_lock_hash
                echo "Dependencies installed"
              else
                echo "uv.lock unchanged, skipping dependency install"
              fi

              # 서비스 시작
              sudo systemctl start ai-server

              # 정리
              rm -f /tmp/ai-server-deploy.tar.gz
            '

      - name: Health Check
        id: healthcheck
        run: |
          EXTERNAL_IP=$(gcloud compute instances describe ${{ env.GCP_INSTANCE }} \
            --zone=${{ env.GCP_ZONE }} \
            --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

          echo "Health check: http://$EXTERNAL_IP:8000/health"

          for i in {1..12}; do
            if curl -s -f "http://$EXTERNAL_IP:8000/health" > /dev/null; then
              echo "Health check passed"
              echo "status=success" >> $GITHUB_OUTPUT
              exit 0
            fi
            echo "Attempt $i/12 - Waiting..."
            sleep 5
          done

          echo "Health check failed"
          echo "status=failed" >> $GITHUB_OUTPUT
          exit 1

      - name: Remove Firewall Rule
        if: always()
        run: |
          gcloud compute firewall-rules delete github-actions-temp-${{ github.run_id }} \
            --project=${{ env.GCP_PROJECT_ID }} \
            --quiet || true
          echo "Firewall rule removed"
```

<br>

## GitHub Secrets 설정

| Secret 이름 | 설명 | 예시 |
|------------|------|------|
| `GCP_PROJECT_ID` | GCP 프로젝트 ID | `dojangkok-ai` |
| `GCP_ZONE` | VM 인스턴스 Zone | `asia-northeast3-a` |
| `GCP_INSTANCE` | VM 인스턴스 이름 | `ai-server-prod` |
| `WORKLOAD_IDENTITY_PROVIDER` | WIF Provider 전체 경로 | `projects/123/locations/global/workloadIdentityPools/github-pool/providers/github-provider` |
| `GCP_SERVICE_ACCOUNT` | 서비스 계정 이메일 | `github-actions@project.iam.gserviceaccount.com` |

---

## CD 흐름

```mermaid
flowchart TD
    A[main 브랜치 push] --> B[CI Jobs 완료]
    B --> C[deploy Job 시작]
    C --> D[GCP OIDC 인증]
    D --> E[Runner IP 획득]
    E --> F[동적 방화벽 규칙 생성]
    F --> G[Artifact 다운로드]
    G --> H[VM에 Artifact 전송]
    H --> I[서비스 중단]
    I --> J[코드 배포]
    J --> K{uv.lock 변경?}
    K -->|Yes| L[uv sync 실행]
    K -->|No| M[의존성 설치 스킵]
    L --> N[서비스 시작]
    M --> N
    N --> O[헬스체크]
    O -->|성공| P[방화벽 규칙 삭제]
    O -->|실패| Q[배포 실패 - Re-run으로 롤백]
    P --> R[완료]
```

<br>

## 주요 특징

### 통합 CI/CD 워크플로우

기존 분리된 CI/CD를 하나의 워크플로우로 통합.

**장점:**
- 단순한 구조: `if: github.ref == 'refs/heads/main'`으로 배포 제어
- workflow_run 의존성 제거로 복잡도 감소
- BE/FE와 동일한 패턴으로 일관성 유지

### Workload Identity Federation (OIDC)

SSH 키 없이 GCP에 인증하는 방식.

**장점:**
- 키 관리 불필요 (유출 위험 없음)
- 자동 토큰 만료 (15분)
- GitHub 워크플로우에서만 사용 가능

**설정 요구사항:**
- GCP Workload Identity Pool 생성
- GitHub Provider 연결
- Service Account에 적절한 IAM 역할 부여

### 동적 방화벽 규칙

GitHub Actions Runner의 IP에 대해서만 SSH 허용.

```bash
# 배포 시작 시 생성
gcloud compute firewall-rules create github-actions-temp-${{ github.run_id }} \
  --allow=tcp:22 \
  --source-ranges=${{ steps.ip.outputs.ip }}/32 \
  --target-tags=ai-server

# 배포 완료 후 삭제 (always)
gcloud compute firewall-rules delete github-actions-temp-${{ github.run_id }}
```

### uv 패키지 관리

**최적화:**
- uv.lock 해시 비교로 변경 시에만 재설치
- .venv/.uv_lock_hash 파일로 상태 추적
- 의존성 변경 없으면 설치 스킵

<br>

## systemd 서비스 설정

### 서비스 파일 위치
```
/etc/systemd/system/ai-server.service
```

### 서비스 파일 예시

```ini
[Unit]
Description=Dojangkok AI Server (FastAPI)
After=network.target

[Service]
User=ubuntu
Group=ubuntu
WorkingDirectory=/app/ai-server
ExecStart=/app/ai-server/.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=on-failure
RestartSec=5

# 환경 변수 파일
EnvironmentFile=/app/ai-server/.env

# 로그 설정
StandardOutput=append:/var/log/dojangkok/ai-server.log
StandardError=append:/var/log/dojangkok/ai-server-error.log

[Install]
WantedBy=multi-user.target
```

### systemd 명령어

```bash
# 서비스 시작
sudo systemctl start ai-server

# 서비스 중단
sudo systemctl stop ai-server

# 서비스 재시작
sudo systemctl restart ai-server

# 서비스 상태 확인
sudo systemctl status ai-server

# 로그 확인
sudo journalctl -u ai-server -f
```

<br>

## 롤백 절차

### Re-run 방식 (권장)

롤백 필요 시 과거 실행을 Re-run하여 해당 시점의 아티팩트로 재배포한다.

**절차:**
1. GitHub Actions → AI Server CI/CD 워크플로우로 이동
2. 롤백하고 싶은 시점의 실행 기록 클릭
3. "Re-run all jobs" 클릭
4. 해당 시점의 아티팩트로 재배포됨

**장점:**
- BE/FE와 동일한 롤백 방식
- 컨테이너 환경 전환 시 자연스럽게 적용 가능 (이미지 태그만 변경)
- 워크플로우 단순화

### 수동 롤백 방법 (아티팩트 직접 다운로드)

GitHub UI에서 과거 아티팩트를 직접 다운로드하여 배포하는 방식.

```bash
# 1. GitHub Actions UI → 이전 성공한 run → Artifacts → 다운로드

# 2. GCP Console 또는 gcloud로 VM 접속
gcloud compute ssh ai-server-prod --zone=asia-northeast3-a

# 3. 아티팩트 업로드 및 배포
# (로컬에서)
gcloud compute scp ai-server-*.tar.gz ai-server-prod:/tmp/

# (VM에서)
sudo systemctl stop ai-server
sudo tar -xzf /tmp/ai-server-*.tar.gz -C /app/ai-server
sudo systemctl start ai-server

# 4. 상태 확인
curl http://localhost:8000/health
```

<br>

## 실패 시 대응

### OIDC 인증 실패
- **원인**: Workload Identity 설정 오류
- **해결**:
  - GCP Console에서 Workload Identity Pool 확인
  - Service Account 권한 확인
  - Secrets 값 재확인

### 방화벽 규칙 생성 실패
- **원인**: Service Account 권한 부족
- **해결**:
  ```bash
  # 필요한 역할 확인
  gcloud projects get-iam-policy $PROJECT_ID \
    --filter="bindings.members:github-actions@"
  ```

### Artifact 다운로드 실패
- **원인**: build-and-artifact job 실패, Artifact 만료
- **해결**:
  - build-and-artifact job 상태 확인
  - Artifact retention-days 확인 (기본 7일)

### 헬스체크 실패
- **확인사항**:
  ```bash
  # VM 접속 후 로그 확인
  sudo journalctl -u ai-server -n 100

  # 수동 실행으로 오류 확인
  cd /app/ai-server
  source .venv/bin/activate
  uvicorn main:app --host 0.0.0.0 --port 8000
  ```
- **롤백**: 이전 성공한 실행을 Re-run하여 롤백 (위 [롤백 절차](#롤백-절차) 참조)

<br>

## 환경 변수 관리

### .env 파일 위치
```
/app/ai-server/.env
```

### .env 예시
```bash
# API Keys
OPENAI_API_KEY=sk-xxx
FIREWORKS_API_KEY=fw-xxx

# Database
CHROMA_PERSIST_DIRECTORY=/app/ai-server/chroma_db

# Service
LOG_LEVEL=INFO
ENVIRONMENT=production
```

> **주의**: .env 파일은 Git에 포함하지 않습니다. 서버에서 직접 관리합니다.



<br>

## 향후 계획

- [ ] Blue-Green 또는 Canary 배포 검토
- [ ] 모델 파일 버전 관리
- [ ] Graceful shutdown (요청 처리 완료 후 종료)
- [ ] 배포 알림 (Slack/Discord)
