#!/bin/bash
set -euo pipefail

# docker-compose.yml 작성
mkdir -p /opt/app
cat > /opt/app/docker-compose.yml << 'COMPOSE'
${compose_content}
COMPOSE

# Artifact Registry 인증 (private image pull)
gcloud auth configure-docker ${ar_host} --quiet

# 컨테이너 실행
cd /opt/app && docker compose up -d
