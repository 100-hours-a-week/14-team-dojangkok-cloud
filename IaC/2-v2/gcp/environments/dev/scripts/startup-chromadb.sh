#!/bin/bash
set -euo pipefail

# docker-compose.yml + Alloy 설정 작성
mkdir -p /opt/app

cat > /opt/app/config.alloy << 'ALLOY'
${alloy_config}
ALLOY

cat > /opt/app/docker-compose.yml << 'COMPOSE'
${compose_content}
COMPOSE

# 컨테이너 실행
cd /opt/app && docker compose up -d
