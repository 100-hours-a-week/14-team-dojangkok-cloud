- 작성일: 2026-02-05
- 최종수정일: 2026-02-05
- 작성자: waf.jung(정승환)

> GCP 프로젝트에 관계없이 사용 가능한 공통 L4 + vLLM 세팅 가이드. 실제 배포 경험(2026-02-04)을 기반으로 작성.

<br>

## 스펙 요약

| 항목 | 값 |
|------|-----|
| GPU | NVIDIA L4 (24GB VRAM) |
| 머신타입 | g2-standard-4 |
| OS 이미지 | ubuntu-accelerator (NVIDIA 드라이버 + CUDA 프리인스톨) |
| 모델 | LGAI-EXAONE/EXAONE-3.5-2.4B-Instruct + LoRA 어댑터 2개 |
| 서빙 | vLLM (port 8001) + FastAPI (port 8000) |

<br>

## 변수 정의

가이드 전체에서 사용할 변수. 실행 전 자신의 환경에 맞게 수정.

```bash
# GCP 설정
export PROJECT_ID="your-project-id"
export ZONE="asia-northeast3-a"
export INSTANCE_NAME="your-instance-name"

# 서비스 설정
export VLLM_API_KEY="your-vllm-api-key"
export VLLM_PORT="8001"
export FASTAPI_PORT="8000"
```

<br>

## 1. 방화벽 생성 (VM 생성 전)

VM 생성 전에 필요한 방화벽 규칙을 먼저 생성.

### 1-1. vLLM + FastAPI 포트 방화벽

```bash
gcloud compute firewall-rules create allow-ai-server-ports \
  --project=${PROJECT_ID} \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:8000,tcp:8001 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=ai-server
```

### 1-2. 모니터링 포트 방화벽 (선택)

Prometheus 스크래핑용.

```bash
gcloud compute firewall-rules create allow-monitoring-ports \
  --project=${PROJECT_ID} \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:9100,tcp:9400 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=monitoring
```

### 1-3. 방화벽 확인

```bash
gcloud compute firewall-rules list \
  --project=${PROJECT_ID} \
  --format="table(name, direction, allowed[].map().firewall_rule().list():label=ALLOWED, targetTags.list():label=TARGET_TAGS)"
```

<br>

## 2. VM 인스턴스 생성

### 2-1. 사용 가능한 이미지 확인

```bash
# ubuntu-os-accelerator-images 프로젝트의 이미지 목록
gcloud compute images list \
  --project=ubuntu-os-accelerator-images \
  --filter="family:ubuntu-accelerator" \
  --format="table(name, family, creationTimestamp)"
```

> Deep Learning VM 이미지(`deeplearning-platform-release`)는 G2 머신타입에서 사용 불가. `ubuntu-os-accelerator-images` 사용.

### 2-2. L4 GPU 가용 존 확인

```bash
gcloud compute accelerator-types list \
  --filter="name=nvidia-l4" \
  --format="table(zone, name)"
```

### 2-3. VM 생성

```bash
gcloud compute instances create ${INSTANCE_NAME} \
  --project=${PROJECT_ID} \
  --zone=${ZONE} \
  --machine-type=g2-standard-4 \
  --accelerator=type=nvidia-l4,count=1 \
  --image-family=ubuntu-accelerator-2204-amd64-with-nvidia-580 \
  --image-project=ubuntu-os-accelerator-images \
  --boot-disk-size=200GB \
  --boot-disk-type=pd-ssd \
  --maintenance-policy=TERMINATE \
  --restart-on-failure \
  --tags=ai-server,monitoring
```

> 이미지 패밀리가 변경될 수 있음. 위 2-1 명령어로 최신 패밀리명 확인 후 사용.

### 2-4. GPU 확인

SSH 접속 후:

```bash
nvidia-smi
```

기대 결과:
- GPU: NVIDIA L4
- VRAM: 24GB
- Driver: 580.x
- CUDA: 13.x

> ubuntu-accelerator 이미지에는 `nvcc`(CUDA Toolkit) 미포함, `libcuda.so`만 있음. vLLM pip 설치로 충분.

<br>

## 3. vLLM 설치 및 서비스 구성

### 3-1. 디렉토리 생성 및 권한 설정

```bash
sudo mkdir -p /app/vllm-server
sudo chown -R $(whoami):$(whoami) /app/vllm-server
```

### 3-2. Python venv 생성 및 vLLM 설치

```bash
cd /app/vllm-server
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install vllm
deactivate
```

### 3-3. 환경변수 파일 작성 (`vllm.env`)

```bash
cat > /app/vllm-server/vllm.env << 'EOF'
# 모델 설정
VLLM_MODEL=LGAI-EXAONE/EXAONE-3.5-2.4B-Instruct

# 서버 설정
VLLM_HOST=0.0.0.0
VLLM_PORT=8001
VLLM_API_KEY=your-vllm-api-key

# GPU 설정
VLLM_GPU_MEMORY_UTILIZATION=0.85
VLLM_MAX_MODEL_LEN=8192
VLLM_DTYPE=bfloat16

# LoRA 설정
VLLM_MAX_LORA_RANK=16
EOF
```

| 키 | 설명 | 권장값 |
|-----|------|--------|
| `VLLM_MODEL` | HuggingFace 모델 ID | - |
| `VLLM_PORT` | vLLM 서비스 포트 | 8001 |
| `VLLM_API_KEY` | API 인증 키 | (프로젝트별 설정) |
| `VLLM_GPU_MEMORY_UTILIZATION` | GPU 메모리 사용 비율 | 0.85 |
| `VLLM_MAX_MODEL_LEN` | 최대 시퀀스 길이 | 4096~8192 |
| `VLLM_DTYPE` | 연산 정밀도 | bfloat16 (L4 지원) |
| `VLLM_MAX_LORA_RANK` | LoRA 최대 rank | 16 |

> `vllm.env`에는 **스칼라 값만** 넣는다. LoRA 모듈 인자는 서비스 파일에서 직접 명시.

### 3-4. systemd 서비스 파일 (`vllm.service`)

```bash
sudo tee /etc/systemd/system/vllm.service > /dev/null << 'EOF'
[Unit]
Description=vLLM Server (EXAONE 2.4B + LoRA)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/app/vllm-server
EnvironmentFile=/app/vllm-server/vllm.env
Environment="PATH=/app/vllm-server/venv/bin:/usr/local/bin:/usr/bin:/bin"
Environment="LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu"
Environment="HF_HOME=/app/vllm-server/.cache/huggingface"
Environment="TRANSFORMERS_CACHE=/app/vllm-server/.cache/huggingface"

ExecStart=/app/vllm-server/venv/bin/vllm serve ${VLLM_MODEL} \
    --host ${VLLM_HOST} \
    --port ${VLLM_PORT} \
    --api-key ${VLLM_API_KEY} \
    --gpu-memory-utilization ${VLLM_GPU_MEMORY_UTILIZATION} \
    --max-model-len ${VLLM_MAX_MODEL_LEN} \
    --dtype ${VLLM_DTYPE} \
    --trust-remote-code \
    --enable-lora \
    --lora-modules \
      '{"name":"easycontract","path":"temdy/exaone-3.5-2.4b-easycontract-qlora-v1.1"}' \
      '{"name":"checklist","path":"imyj1013/exaone-qlora-checklist-adapter"}' \
    --max-lora-rank ${VLLM_MAX_LORA_RANK}

Restart=always
RestartSec=10
TimeoutStartSec=600
LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
EOF
```

> **`--lora-modules`는 반드시 ExecStart에 직접 명시.** systemd EnvironmentFile은 다중 JSON 인자를 정상 전달하지 못함 (워드 스플리팅 미지원).

> **`LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu` 필수.** ubuntu-accelerator 이미지에서 libcuda.so 위치.

### 3-5. 서비스 시작

```bash
sudo systemctl daemon-reload
sudo systemctl enable vllm
sudo systemctl start vllm
```

### 3-6. 로그 확인

```bash
# 실시간 로그 (첫 시작 시 모델 다운로드 + torch.compile로 3~6분 소요)
sudo journalctl -u vllm -f
```

### 3-7. vLLM 검증

```bash
# Health check
curl http://localhost:8001/health

# 모델 목록 확인
curl -s http://localhost:8001/v1/models \
  -H "Authorization: Bearer ${VLLM_API_KEY}" | python3 -m json.tool
```

기대 결과 (3개 모델):
- `LGAI-EXAONE/EXAONE-3.5-2.4B-Instruct` (base)
- `easycontract` (LoRA)
- `checklist` (LoRA)

<br>

## 4. FastAPI 서비스 설치

### 4-1. 디렉토리 생성

```bash
sudo mkdir -p /app/ai-server
sudo mkdir -p /app/ai-server/resources/s3
sudo chown -R $(whoami):$(whoami) /app/ai-server
```

> `/app/ai-server/resources/s3` 디렉토리 누락 시 파일 저장 API에서 500 에러 발생.

### 4-2. Python 환경 설정

#### 옵션 A: uv 사용 (권장)

```bash
# uv 설치
if ! command -v uv &> /dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  source $HOME/.local/bin/env
fi

# venv 생성 및 패키지 설치
cd /app/ai-server
uv venv
source .venv/bin/activate
uv pip install fastapi uvicorn httpx python-dotenv
deactivate
```

#### 옵션 B: pip 사용

```bash
cd /app/ai-server
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install fastapi uvicorn httpx python-dotenv
deactivate
```

### 4-3. 환경변수 파일 (`.env`)

```bash
cat > /app/ai-server/.env << 'EOF'
# 앱 설정
APP_ENV=production

# vLLM 연결
VLLM_BASE_URL=http://localhost:8001/v1
VLLM_API_KEY=your-vllm-api-key
VLLM_MODEL=LGAI-EXAONE/EXAONE-3.5-2.4B-Instruct

# LoRA 어댑터
VLLM_LORA_ADAPTER_EASYCONTRACT=easycontract
VLLM_LORA_ADAPTER_CHECKLIST=checklist

# 백엔드 콜백 (비동기 작업 완료 알림용)
BACKEND_CALLBACK_BASE_URL=https://your-backend.example.com/api
BACKEND_INTERNAL_TOKEN=your-internal-token

# HTTP 설정
HTTP_TIMEOUT_SEC=30
EOF
```

| 키 | 필수 | 설명 |
|-----|------|------|
| `APP_ENV` | O | 실행 환경 (`production`) |
| `VLLM_BASE_URL` | O | vLLM 서버 주소 (포트 뒤에 `/v1` 포함) |
| `VLLM_API_KEY` | O | vLLM API 인증 키 |
| `VLLM_MODEL` | O | 기본 모델 이름 |
| `VLLM_LORA_ADAPTER_*` | O | LoRA 어댑터 이름 |
| `BACKEND_CALLBACK_BASE_URL` | O | 백엔드 콜백 URL (**`/v1` 붙이지 않음**) |
| `BACKEND_INTERNAL_TOKEN` | △ | 백엔드 인증 토큰 (백엔드 팀 발급) |
| `HTTP_TIMEOUT_SEC` | O | HTTP 요청 타임아웃 (초) |

> `.env` 파일은 보통 gitignore 대상. 새 VM에서는 **반드시 수동 생성**.

> **`BACKEND_CALLBACK_BASE_URL` 주의**: 값은 `https://example.com/api`까지만. `/v1`을 붙이면 콜백 URL이 `/api/v1/internal/callbacks/...`로 생성되어 401 에러 발생.

### 4-4. systemd 서비스 파일 (`ai-server.service`)

```bash
sudo tee /etc/systemd/system/ai-server.service > /dev/null << EOF
[Unit]
Description=AI Server (FastAPI)
After=network.target vllm.service
Wants=vllm.service

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=/app/ai-server
Environment="PATH=/app/ai-server/.venv/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=/app/ai-server/.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000

Restart=always
RestartSec=5
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
EOF
```

> `User`는 디렉토리 소유자와 일치해야 함.

### 4-5. 서비스 시작

```bash
sudo systemctl daemon-reload
sudo systemctl enable ai-server
sudo systemctl start ai-server
```

### 4-6. 검증

```bash
# 서비스 상태
sudo systemctl status ai-server

# Health check
curl http://localhost:8000/health
```

<br>

## 5. 외부 접근 테스트

### 5-1. 외부 IP 확인

```bash
gcloud compute instances describe ${INSTANCE_NAME} \
  --project=${PROJECT_ID} \
  --zone=${ZONE} \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)"
```

또는 VM 내부에서:

```bash
curl -s ifconfig.me
```

### 5-2. 외부에서 테스트

```bash
EXTERNAL_IP="<위에서 확인한 IP>"

# FastAPI
curl http://${EXTERNAL_IP}:8000/health

# vLLM
curl http://${EXTERNAL_IP}:8001/health

# vLLM 모델 목록
curl -s http://${EXTERNAL_IP}:8001/v1/models \
  -H "Authorization: Bearer ${VLLM_API_KEY}" | python3 -m json.tool
```

<br>

## 6. 검증 체크리스트

- [ ] `nvidia-smi` → NVIDIA L4, 24GB 표시
- [ ] vLLM health → `curl localhost:8001/health` → 200 OK
- [ ] vLLM models → base + LoRA 어댑터 표시
- [ ] FastAPI health → `curl localhost:8000/health` → 200 OK
- [ ] 외부 접근 → 8000, 8001 포트 정상 응답

---

## 7. 정리 명령어

### VM 중지 (비용 절감)

```bash
gcloud compute instances stop ${INSTANCE_NAME} \
  --project=${PROJECT_ID} \
  --zone=${ZONE}
```

### VM 삭제

```bash
gcloud compute instances delete ${INSTANCE_NAME} \
  --project=${PROJECT_ID} \
  --zone=${ZONE}
```

### 방화벽 삭제

```bash
gcloud compute firewall-rules delete allow-ai-server-ports \
  --project=${PROJECT_ID}

gcloud compute firewall-rules delete allow-monitoring-ports \
  --project=${PROJECT_ID}
```

<br>

## 부록 A: nvidia-smi 출력 예시

2026-02-04 실제 배포 시 출력값:

```
Wed Feb  4 12:33:19 2026
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 580.126.09             Driver Version: 580.126.09     CUDA Version: 13.0     |
+-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA L4                      On  |   00000000:00:03.0 Off |                    0 |
| N/A   75C    P0             35W /   72W |   19980MiB /  23034MiB |      0%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+

+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI              PID   Type   Process name                        GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|    0   N/A  N/A            4203      C   VLLM::EngineCore                      19972MiB |
+-----------------------------------------------------------------------------------------+
```

<br>

## 부록 B: 트러블슈팅

### B-1. Deep Learning VM 이미지 사용 불가

**증상**: G2 머신타입에서 Deep Learning VM 이미지로 VM 생성 실패

**원인**: `deeplearning-platform-release` 이미지는 G2 머신타입과 호환되지 않음

**해결**: `ubuntu-os-accelerator-images` 프로젝트의 이미지 사용

```bash
--image-family=ubuntu-accelerator-2204-amd64-with-nvidia-580 \
--image-project=ubuntu-os-accelerator-images
```

### B-2. libcuda.so not found

**증상**: vLLM 실행 시 `libcuda.so` 로딩 실패

**원인**: ubuntu-accelerator 이미지의 libcuda 경로가 기본 LD_LIBRARY_PATH에 없음

**해결**: systemd 서비스에 환경변수 추가

```ini
Environment="LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu"
```

### B-3. LoRA 모듈 JSON 파싱 실패

**증상**: vLLM 시작 시 `Invalid JSON` 에러

**원인**: systemd EnvironmentFile은 다중 JSON 인자를 정상 전달하지 못함

**해결**: `--lora-modules` 인자를 ExecStart에 직접 명시

```ini
ExecStart=/app/vllm-server/venv/bin/vllm serve ${VLLM_MODEL} \
    ...
    --lora-modules \
      '{"name":"easycontract","path":"..."}' \
      '{"name":"checklist","path":"..."}' \
    ...
```

### B-4. vLLM OOM (Out of Memory)

**증상**: GPU 메모리 부족으로 vLLM 시작 실패

**원인**: `max_model_len`이 너무 크거나 모델 크기가 VRAM 초과

**해결**:
- `max_model_len` 축소 (8192 → 4096)
- `gpu-memory-utilization` 조정 (0.85 → 0.80)
- 더 작은 모델 사용 (7.8B → 2.4B)

### B-5. 외부 접근 불가

**증상**: VM 내부에서는 정상이지만 외부에서 접근 불가

**원인**: 방화벽 규칙 미적용 또는 태그 불일치

**해결**:
1. 방화벽 규칙 존재 확인
2. VM에 올바른 태그가 있는지 확인
3. 포트가 올바르게 열려있는지 확인

```bash
# 방화벽 규칙 확인
gcloud compute firewall-rules list --project=${PROJECT_ID}

# VM 태그 확인
gcloud compute instances describe ${INSTANCE_NAME} \
  --project=${PROJECT_ID} --zone=${ZONE} \
  --format="get(tags.items)"

# 태그 추가 (필요시)
gcloud compute instances add-tags ${INSTANCE_NAME} \
  --project=${PROJECT_ID} --zone=${ZONE} \
  --tags=ai-server
```

### B-6. 첫 기동 시 오래 걸림

**증상**: vLLM 서비스 시작 후 5분 이상 응답 없음

**원인**: 정상 동작. 첫 실행 시 모델 다운로드 + torch.compile 필요

**예상 소요 시간** (첫 실행):
| 단계 | 소요 시간 |
|------|----------|
| 모델 다운로드 (~5GB for 2.4B) | ~60초 |
| 가중치 로딩 | ~60초 |
| torch.compile | ~60초 |
| 그래프 캡처 + 워밍업 | ~10초 |
| **합계** | **~3분** |

> 두 번째 기동부터는 다운로드 생략 → ~2분.

<br>

## 부록 C: max_model_len 선택 가이드

| max_model_len | 동시 처리량 | 용도 |
|---------------|------------|------|
| 4096 | 높음 | 짧은 요청 다량 처리 |
| 6144 | 중간 | 균형 |
| 8192 | 낮음 | 긴 컨텍스트 필요 |

> `max_model_len`은 2의 거듭제곱 제한 없음. 임의의 정수 설정 가능.
> 값이 클수록 요청당 KV 캐시 할당 증가 → 동시 처리량 감소.
