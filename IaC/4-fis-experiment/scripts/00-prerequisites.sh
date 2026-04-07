#!/bin/bash
# 사전 요건 확인
set -euo pipefail

echo "=== 로컬 도구 확인 ==="
for cmd in aws terraform ansible jq; do
  if command -v $cmd &>/dev/null; then
    echo "  ✅ $cmd: $(command -v $cmd)"
  else
    echo "  ❌ $cmd: 설치 필요"
    exit 1
  fi
done

echo ""
echo "=== AWS 계정 확인 ==="
ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "FAILED")
if [ "$ACCOUNT" = "920624925547" ]; then
  echo "  ✅ AWS Account: $ACCOUNT"
else
  echo "  ❌ 예상: 920624925547, 실제: $ACCOUNT"
  exit 1
fi

echo ""
echo "=== VPC 확인 ==="
VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids vpc-01300a19edfeff324 --query 'Vpcs[0].CidrBlock' --output text 2>/dev/null || echo "FAILED")
echo "  VPC CIDR: $VPC_CIDR"

echo ""
echo "=== IGW 확인 ==="
IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=vpc-01300a19edfeff324" --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || echo "FAILED")
echo "  IGW ID: $IGW_ID  ← terraform.tfvars에 입력"

echo ""
echo "=== Key Pair 확인 ==="
KEY=$(aws ec2 describe-key-pairs --key-names dojangkok-key --query 'KeyPairs[0].KeyName' --output text 2>/dev/null || echo "NOT FOUND")
echo "  Key Pair: $KEY"

echo ""
echo "=== Data 인스턴스 SG 확인 ==="
DATA_SG=$(aws ec2 describe-instances --filters "Name=private-ip-address,Values=10.0.0.202" --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "NOT FOUND")
echo "  Data SG: $DATA_SG  ← terraform.tfvars에 입력"

echo ""
echo "=== 사전 요건 확인 완료 ==="
echo ""
echo "terraform.tfvars에 입력할 값:"
echo "  igw_id                 = \"$IGW_ID\""
echo "  data_security_group_id = \"$DATA_SG\""
