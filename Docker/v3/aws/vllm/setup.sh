#!/bin/bash
# ============================================================
# vLLM GPU EC2 초기 설정 스크립트
# 대상: Ubuntu 24.04 LTS x86_64 + g6e.xlarge (L40S 48GB)
#
# 실행 순서:
#   1. EC2 생성 후 SSM 접속
#   2. sudo bash setup.sh
#   3. .env 파일 작성 (cp .env.example .env && vi .env)
#   4. docker compose up -d
#
# 소요 시간:
#   첫 실행: ~15-20분 (드라이버 + Docker + 모델 다운로드)
#   재실행: ~5분 (캐시 활용)
# ============================================================
set -euo pipefail

MODEL="LGAI-EXAONE/EXAONE-3.5-7.8B-Instruct"
REVISION="0ff6b5ec7c13b049b253a16a889aa269e6b79a94"
MODEL_DIR="/opt/models"
APP_DIR="/opt/vllm"

echo "=== [1/5] 시스템 패키지 업데이트 ==="
apt-get update -y
apt-get install -y curl unzip jq

# --------------------------------------------------------
# 2. NVIDIA 드라이버 + Container Toolkit
# --------------------------------------------------------
echo "=== [2/5] NVIDIA 드라이버 설치 ==="
if ! command -v nvidia-smi &> /dev/null; then
    # NVIDIA 드라이버 (headless, 서버용)
    apt-get install -y linux-headers-$(uname -r)
    apt-get install -y nvidia-driver-570-server
    echo ">>> NVIDIA 드라이버 설치 완료. 재부팅 후 nvidia-smi 확인 필요할 수 있음."
else
    echo ">>> NVIDIA 드라이버 이미 설치됨: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader)"
fi

# NVIDIA Container Toolkit (Docker에서 GPU 사용)
if ! dpkg -l | grep -q nvidia-container-toolkit; then
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    apt-get update -y
    apt-get install -y nvidia-container-toolkit
    nvidia-ctk runtime configure --runtime=docker
    echo ">>> NVIDIA Container Toolkit 설치 완료"
else
    echo ">>> NVIDIA Container Toolkit 이미 설치됨"
fi

# --------------------------------------------------------
# 3. Docker
# --------------------------------------------------------
echo "=== [3/5] Docker 설치 ==="
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    echo ">>> Docker 설치 완료"
else
    echo ">>> Docker 이미 설치됨: $(docker --version)"
fi

# Docker 재시작 (NVIDIA runtime 반영)
systemctl restart docker

# --------------------------------------------------------
# 4. EBS 모델 볼륨 마운트
# --------------------------------------------------------
echo "=== [4/5] 모델 캐시 볼륨 설정 ==="
mkdir -p "$MODEL_DIR"

# EBS 추가 볼륨 (/dev/xvdf 또는 /dev/nvme1n1) 확인 및 마운트
# g6e는 NVMe 디바이스명 사용
EBS_DEVICE=""
for dev in /dev/nvme1n1 /dev/xvdf; do
    if [ -b "$dev" ]; then
        EBS_DEVICE="$dev"
        break
    fi
done

if [ -n "$EBS_DEVICE" ]; then
    # 이미 마운트되어 있으면 스킵
    if ! mountpoint -q "$MODEL_DIR"; then
        # 파일시스템 없으면 생성
        if ! blkid "$EBS_DEVICE" | grep -q ext4; then
            mkfs.ext4 "$EBS_DEVICE"
            echo ">>> EBS 볼륨 포맷 완료: $EBS_DEVICE"
        fi
        mount "$EBS_DEVICE" "$MODEL_DIR"
        # fstab 등록 (재부팅 시 자동 마운트)
        if ! grep -q "$MODEL_DIR" /etc/fstab; then
            echo "$EBS_DEVICE $MODEL_DIR ext4 defaults,nofail 0 2" >> /etc/fstab
        fi
        echo ">>> EBS 볼륨 마운트 완료: $EBS_DEVICE → $MODEL_DIR"
    else
        echo ">>> $MODEL_DIR 이미 마운트됨"
    fi
else
    echo ">>> 추가 EBS 볼륨 없음. $MODEL_DIR를 루트 볼륨에서 사용."
fi

# --------------------------------------------------------
# 5. 모델 다운로드
# --------------------------------------------------------
echo "=== [5/5] 모델 다운로드 ==="
MODEL_CACHE="$MODEL_DIR/hub/models--$(echo $MODEL | tr '/' '--')"

if [ -d "$MODEL_CACHE" ]; then
    echo ">>> 모델 캐시 존재. 다운로드 스킵."
else
    # pip로 huggingface-cli 설치
    apt-get install -y python3-pip
    pip3 install --break-system-packages huggingface-hub

    export HF_HOME="$MODEL_DIR"
    huggingface-cli download "$MODEL" --revision "$REVISION"
    echo ">>> 모델 다운로드 완료: $MODEL ($REVISION)"
fi

# --------------------------------------------------------
# 앱 디렉토리 준비
# --------------------------------------------------------
mkdir -p "$APP_DIR"

# docker-compose.yml, .env를 /opt/vllm로 복사하라는 안내
echo ""
echo "============================================================"
echo "  설정 완료!"
echo ""
echo "  다음 단계:"
echo "    1. docker-compose.yml, .env.example → $APP_DIR 복사"
echo "    2. cp $APP_DIR/.env.example $APP_DIR/.env"
echo "    3. .env 파일에서 VLLM_API_KEY 설정"
echo "    4. cd $APP_DIR && docker compose up -d"
echo "    5. docker compose logs -f vllm  (서버 시작 확인)"
echo "    6. curl http://localhost:8000/health  (헬스체크)"
echo "============================================================"
