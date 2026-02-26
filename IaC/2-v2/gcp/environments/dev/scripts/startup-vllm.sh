#!/bin/bash
set -euo pipefail

PROJECT_ID="${project_id}"

# Secret Manager → .env (vLLM API 키)
mkdir -p /opt/app
cat > /opt/app/.env << EOF
VLLM_API_KEY=$(gcloud secrets versions access latest --secret=dojangkok-vllm-api-key --project=$PROJECT_ID)
EOF
chmod 600 /opt/app/.env

# Alloy 설정 파일 작성
cat > /opt/app/config.alloy << 'ALLOY'
${alloy_config}
ALLOY

# docker-compose.yml 작성
cat > /opt/app/docker-compose.yml << 'COMPOSE'
${compose_content}
COMPOSE

# 컨테이너 실행
cd /opt/app && docker compose up -d
