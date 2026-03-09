#!/bin/bash
set -euo pipefail

PROJECT_ID="${project_id}"

# ========================================
# 1. Docker 설치 (Packer 이미지 없으므로)
# ========================================
if ! command -v docker &> /dev/null; then
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable docker
  systemctl start docker
fi

# ========================================
# 2. Secret Manager → .env
# ========================================
mkdir -p /opt/app
cat > /opt/app/.env << EOF
VLLM_API_KEY=$(gcloud secrets versions access latest --secret=dojangkok-vllm-api-key --project=$PROJECT_ID)
BACKEND_INTERNAL_TOKEN=$(gcloud secrets versions access latest --secret=dojangkok-backend-internal-token --project=$PROJECT_ID)
OCR_API=$(gcloud secrets versions access latest --secret=dojangkok-ocr-api --project=$PROJECT_ID)
RABBITMQ_URL=$(gcloud secrets versions access latest --secret=dojangkok-rabbitmq-url --project=$PROJECT_ID)
EOF
chmod 600 /opt/app/.env

# ========================================
# 3. docker-compose.yml 작성
# ========================================
cat > /opt/app/docker-compose.yml << 'COMPOSE'
${compose_content}
COMPOSE

# ========================================
# 4. Artifact Registry 인증 (크로스 프로젝트)
# ========================================
gcloud auth configure-docker asia-northeast3-docker.pkg.dev --quiet

# ========================================
# 5. 컨테이너 실행
# ========================================
cd /opt/app && docker compose up -d
