#!/bin/bash
set -euxo pipefail

# Docker CE + compose-plugin 설치 스크립트 (CPU VM용)

export DEBIAN_FRONTEND=noninteractive

# 사전 패키지 설치
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

# Docker GPG 키 등록
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Docker 저장소 추가
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Docker 설치
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Docker 서비스 활성화
sudo systemctl enable docker
sudo systemctl start docker

# gcloud credential helper (Artifact Registry)
sudo -u packer gcloud auth configure-docker asia-northeast3-docker.pkg.dev --quiet 2>/dev/null || true

# 정리
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
