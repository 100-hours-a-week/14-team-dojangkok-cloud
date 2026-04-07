#!/bin/bash
# FIS IAM role + 템플릿 생성
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIS_DIR="${SCRIPT_DIR}/../fis"

echo "=== FIS IAM Role 생성 ==="
aws iam create-role \
  --role-name fis-exp-role \
  --assume-role-policy-document file://${FIS_DIR}/fis-trust-policy.json \
  --tags Key=Project,Value=dojangkok Key=Environment,Value=fis-experiment \
  2>/dev/null || echo "  (이미 존재)"

aws iam put-role-policy \
  --role-name fis-exp-role \
  --policy-name fis-ec2-actions \
  --policy-document file://${FIS_DIR}/fis-role-policy.json

ROLE_ARN=$(aws iam get-role --role-name fis-exp-role --query 'Role.Arn' --output text)
echo "  Role ARN: $ROLE_ARN"

echo ""
echo "=== FIS Template A 생성 (PT15M) ==="
TEMPLATE_A=$(cat ${FIS_DIR}/fis-template-a.json | sed "s|REPLACE_WITH_FIS_ROLE_ARN|${ROLE_ARN}|")
TEMPLATE_A_ID=$(echo "$TEMPLATE_A" | aws fis create-experiment-template --cli-input-json file:///dev/stdin --query 'experimentTemplate.id' --output text 2>/dev/null || echo "FAILED")
echo "  Template A ID: $TEMPLATE_A_ID"

echo ""
echo "=== FIS Template B 생성 (PT10M) ==="
TEMPLATE_B=$(cat ${FIS_DIR}/fis-template-b.json | sed "s|REPLACE_WITH_FIS_ROLE_ARN|${ROLE_ARN}|")
TEMPLATE_B_ID=$(echo "$TEMPLATE_B" | aws fis create-experiment-template --cli-input-json file:///dev/stdin --query 'experimentTemplate.id' --output text 2>/dev/null || echo "FAILED")
echo "  Template B ID: $TEMPLATE_B_ID"

echo ""
echo "=== FIS 구성 완료 ==="
echo "  실험 A 실행: aws fis start-experiment --experiment-template-id $TEMPLATE_A_ID"
echo "  실험 B 실행: aws fis start-experiment --experiment-template-id $TEMPLATE_B_ID"
