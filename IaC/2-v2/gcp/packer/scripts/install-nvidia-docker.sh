#!/bin/bash
set -euxo pipefail

# Docker CE + compose-plugin + NVIDIA Container Toolkit 설치 스크립트 (GPU VM용)
# 소스 이미지: ubuntu-accelerator (NVIDIA 드라이버 사전 설치됨)

export DEBIAN_FRONTEND=noninteractive

# ============================================
# Docker CE 설치
# ============================================
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ============================================
# NVIDIA Container Toolkit 설치
# ============================================
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

# Docker 런타임에 NVIDIA 등록
sudo nvidia-ctk runtime configure --runtime=docker

# ============================================
# 서비스 활성화
# ============================================
sudo systemctl enable docker
sudo systemctl start docker

# gcloud credential helper (Artifact Registry)
sudo gcloud auth configure-docker asia-northeast3-docker.pkg.dev --quiet 2>/dev/null || true

# 정리
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
