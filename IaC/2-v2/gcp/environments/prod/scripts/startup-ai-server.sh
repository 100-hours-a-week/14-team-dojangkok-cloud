#!/bin/bash
set -euo pipefail

PROJECT_ID="${project_id}"

# Secret Manager → .env (시크릿 주입)
mkdir -p /opt/app
cat > /opt/app/.env << EOF
VLLM_API_KEY=$(gcloud secrets versions access latest --secret=dojangkok-vllm-api-key --project=$PROJECT_ID)
BACKEND_INTERNAL_TOKEN=$(gcloud secrets versions access latest --secret=dojangkok-backend-internal-token --project=$PROJECT_ID)
OCR_API=$(gcloud secrets versions access latest --secret=dojangkok-ocr-api --project=$PROJECT_ID)
EOF
chmod 600 /opt/app/.env

# docker-compose.yml 작성
cat > /opt/app/docker-compose.yml << 'COMPOSE'
${compose_content}
COMPOSE

# Artifact Registry 인증 (private image pull)
gcloud auth configure-docker ${ar_host} --quiet

# 컨테이너 실행
cd /opt/app && docker compose up -d
