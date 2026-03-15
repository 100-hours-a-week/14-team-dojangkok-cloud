#!/bin/bash
set -euo pipefail

REGION="${region}"
ENVIRONMENT="${environment}"
ECR_REGISTRY="${ecr_registry}"
S3_BUCKET="${s3_bucket}"

# --- 1. SSM Parameter Store → .env (시크릿) ---
mkdir -p /opt/app

cat > /opt/app/.env << EOF
VLLM_API_KEY=$(aws ssm get-parameter --name "/dojangkok/$ENVIRONMENT/ai/vllm-api-key" --with-decryption --query "Parameter.Value" --output text --region $REGION)
BACKEND_INTERNAL_TOKEN=$(aws ssm get-parameter --name "/dojangkok/$ENVIRONMENT/ai/backend-internal-token" --with-decryption --query "Parameter.Value" --output text --region $REGION)
OCR_API=$(aws ssm get-parameter --name "/dojangkok/$ENVIRONMENT/ai/ocr-api" --with-decryption --query "Parameter.Value" --output text --region $REGION)
RABBITMQ_URL=$(aws ssm get-parameter --name "/dojangkok/$ENVIRONMENT/ai/rabbitmq-url" --with-decryption --query "Parameter.Value" --output text --region $REGION)
EOF
chmod 600 /opt/app/.env

# --- 2. S3 → docker-compose.yml + config.alloy (비민감 설정) ---
aws s3 cp "s3://$S3_BUCKET/ai/$ENVIRONMENT/docker-compose.yml" /opt/app/docker-compose.yml --region "$REGION"
aws s3 cp "s3://$S3_BUCKET/ai/$ENVIRONMENT/config.alloy" /opt/app/config.alloy --region "$REGION"

# --- 3. App log directory ---
mkdir -p /var/log/dojangkok

# --- 4. Stop host Alloy (Packer AMI default) to avoid port conflict with container ---
systemctl stop alloy 2>/dev/null || true
systemctl disable alloy 2>/dev/null || true

# --- 5. ECR Login + Start ---
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
cd /opt/app && docker compose up -d
