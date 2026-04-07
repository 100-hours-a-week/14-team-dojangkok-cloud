#!/bin/bash
# 전체 정리 — FIS + Terraform destroy
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"

echo "=== FIS 템플릿 삭제 ==="
for id in $(aws fis list-experiment-templates --query 'experimentTemplates[?tags.Project==`dojangkok`].id' --output text 2>/dev/null); do
  echo "  삭제: $id"
  aws fis delete-experiment-template --id "$id" 2>/dev/null || true
done

echo ""
echo "=== FIS IAM Role 삭제 ==="
aws iam delete-role-policy --role-name fis-exp-role --policy-name fis-ec2-actions 2>/dev/null || true
aws iam delete-role --role-name fis-exp-role 2>/dev/null || true
echo "  ✅ fis-exp-role 삭제 완료"

echo ""
echo "=== Terraform Destroy ==="
cd "$TF_DIR"
terraform destroy -auto-approve

echo ""
echo "=== 정리 완료 ==="
echo "  남은 리소스 확인: aws ec2 describe-instances --filters 'Name=tag:k8s:cluster-name,Values=fis-exp'"
