#!/bin/bash
set -euo pipefail

REGION="${region}"
ECR_REGISTRY="${ecr_registry}"

# --- 1. SSM Parameter Store → .env ---
mkdir -p /opt/app

cat > /opt/app/.env << EOF
VLLM_API_KEY=$(aws ssm get-parameter --name "/dojangkok/${environment}/ai/vllm-api-key" --with-decryption --query "Parameter.Value" --output text --region $REGION)
BACKEND_INTERNAL_TOKEN=$(aws ssm get-parameter --name "/dojangkok/${environment}/ai/backend-internal-token" --with-decryption --query "Parameter.Value" --output text --region $REGION)
OCR_API=$(aws ssm get-parameter --name "/dojangkok/${environment}/ai/ocr-api" --with-decryption --query "Parameter.Value" --output text --region $REGION)
RABBITMQ_URL=$(aws ssm get-parameter --name "/dojangkok/${environment}/ai/rabbitmq-url" --with-decryption --query "Parameter.Value" --output text --region $REGION)
EOF
chmod 600 /opt/app/.env

# --- 2. Alloy monitoring config ---
cat > /opt/app/config.alloy << 'ALLOY'
${alloy_config}
ALLOY

# --- 3. App log directory ---
mkdir -p /var/log/dojangkok

# --- 4. Docker Compose ---
cat > /opt/app/docker-compose.yml << 'COMPOSE'
${compose_content}
COMPOSE

# --- 5. Stop host Alloy (Packer AMI default) to avoid port conflict with container ---
systemctl stop alloy 2>/dev/null || true
systemctl disable alloy 2>/dev/null || true

# --- 6. ECR Login + Start ---
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
cd /opt/app && docker compose up -d
