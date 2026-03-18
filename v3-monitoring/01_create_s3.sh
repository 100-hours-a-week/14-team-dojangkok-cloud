#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 01_create_s3.sh - S3 모니터링 버킷 생성 + IAM 정책 연결
# =============================================================================
# EC2 인스턴스는 수동 생성 후 .env에 기입.
# 이 스크립트는 S3 버킷 + Lifecycle + IAM 정책만 생성한다.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

for var in AWS_PROFILE AWS_REGION S3_MONITORING_BUCKET MONITOR_IAM_ROLE; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set in .env"
    exit 1
  fi
done

AWS="aws --profile $AWS_PROFILE --region $AWS_REGION"

echo "============================================="
echo " V3 Monitoring - S3 Bucket Setup"
echo "============================================="
echo "Bucket   : $S3_MONITORING_BUCKET"
echo "IAM Role : $MONITOR_IAM_ROLE"
echo ""

# --- 1. S3 버킷 생성 ---
echo "[1/3] Creating S3 bucket: $S3_MONITORING_BUCKET ..."

if $AWS s3api head-bucket --bucket "$S3_MONITORING_BUCKET" 2>/dev/null; then
  echo "       Bucket already exists, skipping."
else
  $AWS s3api create-bucket \
    --bucket "$S3_MONITORING_BUCKET" \
    --create-bucket-configuration LocationConstraint="${AWS_REGION}"
  echo "       Bucket created."

  # Block public access
  $AWS s3api put-public-access-block \
    --bucket "$S3_MONITORING_BUCKET" \
    --public-access-block-configuration \
      BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  echo "       Public access blocked."
fi

# --- 2. Lifecycle 정책 ---
echo "[2/3] Applying lifecycle rules ..."

$AWS s3api put-bucket-lifecycle-configuration \
  --bucket "$S3_MONITORING_BUCKET" \
  --lifecycle-configuration '{
  "Rules": [
    {
      "ID": "loki-lifecycle",
      "Status": "Enabled",
      "Filter": { "Prefix": "loki/" },
      "Transitions": [{ "Days": 30, "StorageClass": "STANDARD_IA" }],
      "Expiration": { "Days": 90 }
    },
    {
      "ID": "tempo-lifecycle",
      "Status": "Enabled",
      "Filter": { "Prefix": "tempo/" },
      "Expiration": { "Days": 30 }
    },
    {
      "ID": "prometheus-lifecycle",
      "Status": "Enabled",
      "Filter": { "Prefix": "prometheus/" },
      "Transitions": [{ "Days": 30, "StorageClass": "STANDARD_IA" }],
      "Expiration": { "Days": 90 }
    }
  ]
}'

echo "       Lifecycle rules applied:"
echo "         loki/       → 30d IA, 90d 삭제"
echo "         tempo/      → 30d 삭제"
echo "         prometheus/ → 30d IA, 90d 삭제"

# --- 3. IAM 정책 연결 ---
echo "[3/3] Attaching S3 policy to IAM role: $MONITOR_IAM_ROLE ..."

POLICY_NAME="${S3_MONITORING_BUCKET}-s3-access"

$AWS iam put-role-policy \
  --role-name "$MONITOR_IAM_ROLE" \
  --policy-name "$POLICY_NAME" \
  --policy-document "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [{
    \"Effect\": \"Allow\",
    \"Action\": [\"s3:GetObject\", \"s3:PutObject\", \"s3:DeleteObject\", \"s3:ListBucket\"],
    \"Resource\": [
      \"arn:aws:s3:::${S3_MONITORING_BUCKET}\",
      \"arn:aws:s3:::${S3_MONITORING_BUCKET}/*\"
    ]
  }]
}"

echo "       IAM inline policy attached: $POLICY_NAME"

echo ""
echo "============================================="
echo " S3 Setup Complete"
echo "============================================="
echo " Bucket    : $S3_MONITORING_BUCKET"
echo " Lifecycle : loki(90d) / tempo(30d) / prometheus(90d)"
echo " IAM       : $MONITOR_IAM_ROLE → $POLICY_NAME"
echo "============================================="
echo ""
echo "Next: ./02_install_stack.sh"
