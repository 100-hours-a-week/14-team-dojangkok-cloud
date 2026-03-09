#!/bin/bash
set -euo pipefail

PROJECT_ID="${project_id}"

# Secret Manager → .env (시크릿 주입)
mkdir -p /opt/app
cat > /opt/app/.env << EOF
VLLM_API_KEY=$(gcloud secrets versions access latest --secret=dojangkok-vllm-api-key --project=$PROJECT_ID)
BACKEND_INTERNAL_TOKEN=$(gcloud secrets versions access latest --secret=dojangkok-backend-internal-token --project=$PROJECT_ID)
OCR_API=$(gcloud secrets versions access latest --secret=dojangkok-ocr-api --project=$PROJECT_ID)
RABBITMQ_URL=$(gcloud secrets versions access latest --secret=dojangkok-rabbitmq-url --project=$PROJECT_ID)
EOF
chmod 600 /opt/app/.env

# Alloy 설정 파일 작성
cat > /opt/app/config.alloy << 'ALLOY'
${alloy_config}
ALLOY

# 앱 로그 디렉토리 생성
mkdir -p /var/log/dojangkok

# docker-compose.yml 작성
cat > /opt/app/docker-compose.yml << 'COMPOSE'
${compose_content}
COMPOSE

# Artifact Registry 인증 (크로스 프로젝트 image pull)
gcloud auth configure-docker ${ar_host} --quiet

# 컨테이너 실행
cd /opt/app && docker compose up -d
