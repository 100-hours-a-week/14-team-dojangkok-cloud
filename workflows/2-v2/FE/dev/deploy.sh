#!/bin/bash
LOG_FILE="/home/ubuntu/deploy.log"
exec > >(tee -a $LOG_FILE) 2>&1
echo "=== 배포 시작: $(date) ==="

# 1. 디렉토리가 없으면 생성하고 이동
TARGET_DIR="/home/ubuntu/dojangkok-fe"
mkdir -p $TARGET_DIR
cd $TARGET_DIR

sudo chown -R ubuntu:ubuntu $TARGET_DIR

# 2. .env 보안 세팅 (sudo 추가하여 권한 문제 해결)
if [ -f .env ]; then
    sudo chmod 600 .env
fi

# 3. AWS 로그인 정보 세팅 및 ECR_REGISTRY 변수 생성
REGION="ap-northeast-2"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
# docker-compose가 읽을 수 있도록 변수를 내보냄(export)
export ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# 4. AWS ECR 로그인
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# 5. Docker Compose 실행 (v2 명령어)
docker compose pull
docker compose down --remove-orphans || true
docker compose up -d

echo "=== 배포 완료 ==="