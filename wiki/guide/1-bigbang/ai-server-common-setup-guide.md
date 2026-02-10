- 작성일: 2026-02-05
- 최종수정일: 2026-02-10
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
    --enforce-eager \
    --revision e949c91dec92095908d34e6b560af77dd0c993f8 \
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

> **`--enforce-eager` 필수.** L4 GPU에서 torch.compile 시 SM 부족 크래시 발생 (B-10 참조). 2.4B 모델에서는 성능 차이 미미.

> **`--revision` 필수 (임시).** EXAONE 모델 repo가 Transformers v5용으로 업데이트되어 현재 vLLM의 transformers 4.x와 비호환 (B-11 참조). transformers v5 출시 후 제거 가능.

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

# 로그 디렉토리 (logging_config.py에서 사용)
sudo mkdir -p /var/log/dojangkok/production
sudo chmod 777 /var/log/dojangkok /var/log/dojangkok/production
```

> `/app/ai-server/resources/s3` 디렉토리 누락 시 파일 저장 API에서 500 에러 발생.

> `/var/log/dojangkok/production` 디렉토리 누락 시 로그 파일 생성 실패. Promtail도 이 경로의 로그를 수집하므로 반드시 사전 생성.

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

# OCR API 키 (쉬운 계약서 기능용)
OCR_API=your-ocr-api-key
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
| `OCR_API` | O | OCR API 키 (쉬운 계약서 기능용) |

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
ExecStart=/app/ai-server/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

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
- [ ] Node Exporter → `:9100/metrics` 응답
- [ ] DCGM Exporter → `:9400/metrics` 응답 (GPU 메트릭 6종)
- [ ] Promtail → `systemctl status promtail` active, Loki 전송 에러 없음

<br>

## 7. 모니터링 설치

### 7-1. 사전 준비: NVIDIA CUDA repo 등록

ubuntu-accelerator 이미지에는 NVIDIA CUDA repo가 기본 등록되어 있지 않음. DCGM 설치를 위해 먼저 등록.

```bash
distribution=$(. /etc/os-release; echo ${ID}${VERSION_ID//.})
curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/${distribution}/x86_64/cuda-keyring_1.1-1_all.deb -o /tmp/cuda-keyring.deb
sudo dpkg -i /tmp/cuda-keyring.deb
sudo apt-get update
```

### 7-2. DCGM (NVIDIA Data Center GPU Manager)

```bash
sudo apt-get install -y datacenter-gpu-manager
sudo systemctl enable nvidia-dcgm
sudo systemctl start nvidia-dcgm
```

> `datacenter-gpu-manager`가 `libdcgm.so`를 제공. 미설치 시 dcgm-exporter 시작 실패.

### 7-3. Go + build-essential (dcgm-exporter 소스 빌드용)

```bash
sudo snap install go --classic
sudo apt-get install -y make build-essential
go version
```

### 7-4. DCGM Exporter (GPU 메트릭, :9400)

> **중요**: dcgm-exporter 버전과 DCGM 버전을 맞춰야 함. DCGM 3.x → dcgm-exporter `3.3.9-3.6.1` 태그 사용. main 브랜치(4.x)는 `libdcgm.so.4`를 요구하므로 DCGM 3.x와 호환 불가.

```bash
cd /tmp
git clone https://github.com/NVIDIA/dcgm-exporter.git
cd dcgm-exporter
git checkout 3.3.9-3.6.1
make binary
sudo cp cmd/dcgm-exporter/dcgm-exporter /usr/local/bin/
sudo ldconfig
```

카운터 설정 파일:

```bash
sudo mkdir -p /etc/dcgm-exporter
sudo tee /etc/dcgm-exporter/default-counters.csv > /dev/null << 'EOF'
# Format,,
DCGM_FI_DEV_GPU_TEMP,      gauge, GPU temperature (in C).
DCGM_FI_DEV_GPU_UTIL,      gauge, GPU utilization (in %).
DCGM_FI_DEV_MEM_COPY_UTIL, gauge, Memory utilization (in %).
DCGM_FI_DEV_FB_FREE,       gauge, Framebuffer memory free (in MiB).
DCGM_FI_DEV_FB_USED,       gauge, Framebuffer memory used (in MiB).
DCGM_FI_DEV_POWER_USAGE,   gauge, Power draw (in W).
EOF
```

systemd 서비스:

```bash
sudo tee /etc/systemd/system/dcgm-exporter.service > /dev/null << 'EOF'
[Unit]
Description=DCGM Exporter
After=nvidia-dcgm.service
Requires=nvidia-dcgm.service

[Service]
User=root
ExecStart=/usr/local/bin/dcgm-exporter -f /etc/dcgm-exporter/default-counters.csv
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable dcgm-exporter
sudo systemctl start dcgm-exporter
```

검증 (시작 후 **10초 이상 대기** 필요):

```bash
sleep 10
curl -s http://localhost:9400/metrics | grep DCGM
```

### 7-5. Node Exporter (시스템 메트릭, :9100)

```bash
cd /tmp
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.9.0/node_exporter-1.9.0.linux-amd64.tar.gz
tar xzf node_exporter-1.9.0.linux-amd64.tar.gz
sudo cp node_exporter-1.9.0.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-1.9.0.linux-amd64*

sudo tee /etc/systemd/system/node_exporter.service > /dev/null << 'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/node_exporter
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
```

검증:

```bash
curl -s http://localhost:9100/metrics | head -5
```

### 7-6. Promtail (로그 전송 → Loki, :9080)

```bash
cd /tmp
sudo apt-get install -y unzip
curl -LO https://github.com/grafana/loki/releases/download/v3.4.2/promtail-linux-amd64.zip
unzip promtail-linux-amd64.zip
sudo cp promtail-linux-amd64 /usr/local/bin/promtail
sudo chmod +x /usr/local/bin/promtail
rm -f promtail-linux-amd64.zip promtail-linux-amd64
```

설정 파일 (`<LOKI_URL>`을 실제 Loki 주소로 교체):

```bash
sudo mkdir -p /etc/promtail
sudo mkdir -p /var/log/dojangkok/production

sudo tee /etc/promtail/config.yml > /dev/null << 'EOF'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml
/
clients:
  - url: <LOKI_URL>/loki/api/v1/push

scrape_configs:
  - job_name: ai-server
    journal:
      matches: _SYSTEMD_UNIT=ai-server.service
      labels:
        job: ai-server
        host: ai-server-l4
      path: /var/log/journal
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: 'unit'
    pipeline_stages:
      - match:
          selector: '{unit="ai-server.service"}'
          stages:
            - static_labels:
                service: ai-server

  - job_name: vllm
    journal:
      matches: _SYSTEMD_UNIT=vllm.service
      labels:
        job: vllm
        host: ai-server-l4
      path: /var/log/journal
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: 'unit'
    pipeline_stages:
      - match:
          selector: '{unit="vllm.service"}'
          stages:
            - static_labels:
                service: vllm

  - job_name: dojangkok-ai
    static_configs:
      - targets:
          - localhost
        labels:
          job: dojangkok-ai
          host: ai-server-l4
          __path__: /var/log/dojangkok/production/*.log
EOF
```

systemd 서비스:

```bash
sudo tee /etc/systemd/system/promtail.service > /dev/null << 'EOF'
[Unit]
Description=Promtail
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/config.yml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable promtail
sudo systemctl start promtail
```

검증:

```bash
sudo systemctl status promtail
sudo journalctl -u promtail --no-pager -n 10
```

> Promtail은 아웃바운드로 Loki에 push. 인바운드 방화벽 불필요.

<br>

## 8. 정리 명령어

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

### B-6. DCGM 패키지 미설치 (Unable to locate package)

**증상**: `sudo apt-get install -y datacenter-gpu-manager` → `Unable to locate package`

**원인**: ubuntu-accelerator 이미지에 NVIDIA CUDA repo가 기본 등록되어 있지 않음

**해결**: §7-1의 CUDA keyring 등록 후 재시도

### B-7. dcgm-exporter libdcgm.so.4 not found

**증상**: dcgm-exporter 시작 시 `the libdcgm.so.4 library was not found`

**원인**: 설치된 DCGM이 3.x (`libdcgm.so.3`). dcgm-exporter main 브랜치(4.x)는 `libdcgm.so.4` 요구.

**해결**: dcgm-exporter를 DCGM 3.x 호환 태그(`3.3.9-3.6.1`)로 빌드. §7-4 참조.

### B-8. dcgm-exporter 빌드 시 make 미설치

**증상**: `make binary` → `make: command not found`

**원인**: ubuntu-accelerator 이미지에 build-essential 미포함

**해결**: `sudo apt-get install -y make build-essential`

### B-9. dcgm-exporter metrics 빈 응답

**증상**: `curl localhost:9400/metrics` → 빈 응답

**원인**: 시작 직후 첫 수집 주기 미완료

**해결**: 시작 후 약 10초 대기 후 재확인

### B-10. vLLM torch.compile 크래시 (enforce-eager)

**증상**: 모델 로딩 후 `Not enough SMs to use max_autotune_gemm mode` → Engine core initialization failed

**원인**: L4 GPU의 SM 수가 torch inductor의 max_autotune_gemm 요구사항 미충족 (vLLM 0.15.x)

**해결**: `--enforce-eager` 옵션으로 torch.compile 비활성화
```ini
ExecStart=... --enforce-eager \
```

> 2.4B 모델에서는 성능 차이 미미. vLLM 업데이트로 해결 시 제거 가능.

### B-11. EXAONE 모델 Transformers v5 호환성 오류

**증상**: `ImportError: cannot import name 'RopeParameters' from 'transformers.modeling_rope_utils'`

**원인**: EXAONE 모델 repo가 Transformers v5용으로 업데이트됨 (2026-02-06). vLLM에 포함된 transformers 4.x와 비호환.

**해결**: 이전 커밋 리비전 지정
```ini
ExecStart=... --revision e949c91dec92095908d34e6b560af77dd0c993f8 \
```

> transformers가 v5로 업그레이드되면 `--revision` 제거 가능.

### B-12. 첫 기동 시 오래 걸림

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

### B-13. python3-venv 미설치

**증상**: `python3 -m venv venv` 실행 시 `ensurepip is not available` 에러

**원인**: ubuntu-accelerator 이미지에 python3.10-venv 패키지 미포함

**해결**:
```bash
sudo apt-get install -y python3.10-venv
```

### B-14. pyproject.toml 의존성 누락

**증상**: ai-server 시작 시 `ModuleNotFoundError: No module named 'prometheus_fastapi_instrumentator'`, `No module named 'pythonjsonlogger'`

**원인**: `pyproject.toml`에 해당 의존성이 누락되어 `uv sync`로 설치되지 않음

**해결**: 수동 설치
```bash
uv pip install prometheus-fastapi-instrumentator python-json-logger
```

> 근본 해결은 `pyproject.toml`의 `[project.dependencies]`에 추가 후 `uv sync`.

### B-15. VLLM_API_KEY 빈값 → httpx 에러

**증상**: FastAPI에서 vLLM 호출 시 `httpx.InvalidHeaderValue: Invalid header value b'Bearer '`

**원인**: `.env`에서 `VLLM_API_KEY=` (빈값)으로 설정하면 `Authorization: Bearer ` 헤더가 빈 토큰으로 전송되어 httpx가 거부

**해결**: 더미 키라도 반드시 설정
```bash
VLLM_API_KEY=your-vllm-api-key  # 빈값 금지
```

> vLLM 서버와 클라이언트(FastAPI)의 API 키를 동일하게 맞출 것.

### B-16. SSD 할당 쿼터 초과

**증상**: VM 생성 시 `SSD_TOTAL_GB quota exceeded (Limit: 250.0) in region asia-northeast3`

**원인**: 해당 리전의 SSD 총 용량 할당량(250GB)을 기존 디스크가 이미 차지하고 있어 추가 할당 불가

**해결**:
1. 미사용 디스크 확인 및 삭제
```bash
gcloud compute disks list \
  --filter="zone:asia-northeast3" \
  --format="table(name,sizeGb,status,users)"
```
2. 또는 GCP Console → IAM & Admin → Quotas에서 `SSD_TOTAL_GB` 할당량 증가 요청

### B-17. Promtail → Loki 연결 실패

**증상**: Promtail 로그에 `context deadline exceeded` 반복

**원인**: Loki 서버(AWS)의 보안그룹에 GCP VM의 외부 IP가 허용되지 않음

**해결**: AWS 보안그룹에 GCP 외부 IP 인바운드 허용 (포트 3100)

> GCP 프로젝트 변경 등으로 외부 IP가 바뀌면 AWS 보안그룹도 함께 업데이트 필요.

### B-18. 로그 디렉토리 미생성

**증상**: `/var/log/dojangkok/production/*.log`에 로그가 기록되지 않음

**원인**: 로그 디렉토리가 사전 생성되지 않아 파일 생성 실패

**해결**:
```bash
sudo mkdir -p /var/log/dojangkok/production
sudo chmod 777 /var/log/dojangkok /var/log/dojangkok/production
```

> Promtail의 파일 로그 수집도 이 경로에 의존하므로 반드시 사전 생성.

### B-19. Promtail journal 로그 혼합

**증상**: Loki에서 ai-server와 vllm 로그가 구분 없이 혼합되어 표시

**원인**: Promtail journal 설정에 `matches` 필터가 없으면 모든 systemd 유닛 로그가 혼합 수집됨

**해결**: 각 journal job에 `matches` 필터 추가
```yaml
- job_name: ai-server
  journal:
    matches: _SYSTEMD_UNIT=ai-server.service
- job_name: vllm
  journal:
    matches: _SYSTEMD_UNIT=vllm.service
```

> §7-6의 Promtail 설정 참조.

<br>

## 부록 C: max_model_len 선택 가이드

| max_model_len | 동시 처리량 | 용도 |
|---------------|------------|------|
| 4096 | 높음 | 짧은 요청 다량 처리 |
| 6144 | 중간 | 균형 |
| 8192 | 낮음 | 긴 컨텍스트 필요 |

> `max_model_len`은 2의 거듭제곱 제한 없음. 임의의 정수 설정 가능.
> 값이 클수록 요청당 KV 캐시 할당 증가 → 동시 처리량 감소.
