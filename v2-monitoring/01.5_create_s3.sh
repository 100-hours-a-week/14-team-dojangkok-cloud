#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 01.5_create_s3.sh - Verify S3 Bucket & Create Gateway VPC Endpoint
# =============================================================================
# Assumes the S3 bucket already exists (ktb-team14-dojangkok-deploy).
# Verifies the bucket is reachable, ensures the prefix exists, and creates
# a Gateway VPC Endpoint so private-subnet instances can reach S3 without NAT.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# 1. Source .env & validate
# ---------------------------------------------------------------------------
if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
  echo "ERROR: $SCRIPT_DIR/.env not found. Copy env.example to .env and fill in values."
  exit 1
fi

# shellcheck source=/dev/null
source "$SCRIPT_DIR/.env"

for var in AWS_PROFILE AWS_REGION S3_BUCKET S3_PREFIX VPC_ID; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Required variable $var is not set in .env"
    exit 1
  fi
done

AWS="aws --profile $AWS_PROFILE --region $AWS_REGION"

echo "============================================="
echo " V2 Monitoring - S3 Verify & VPC Endpoint"
echo "============================================="
echo "Bucket  : $S3_BUCKET"
echo "Prefix  : $S3_PREFIX"
echo "VPC     : $VPC_ID"
echo ""

# ---------------------------------------------------------------------------
# 2. Verify bucket exists
# ---------------------------------------------------------------------------
echo "[1/3] Verifying S3 bucket: $S3_BUCKET ..."

if ! $AWS s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
  echo "ERROR: Bucket $S3_BUCKET does not exist or is not accessible."
  echo "       Create it manually or check AWS_PROFILE permissions."
  exit 1
fi

echo "       Bucket confirmed."

# ---------------------------------------------------------------------------
# 3. Ensure prefix exists
# ---------------------------------------------------------------------------
echo "[2/3] Checking prefix: s3://${S3_BUCKET}/${S3_PREFIX}/ ..."

EXISTING=$($AWS s3api list-objects-v2 \
  --bucket "$S3_BUCKET" \
  --prefix "${S3_PREFIX}/" \
  --max-items 1 \
  --query 'KeyCount' \
  --output text 2>/dev/null) || true
EXISTING="${EXISTING:-0}"
[[ "$EXISTING" == "None" ]] && EXISTING=0

if [[ "$EXISTING" -gt 0 ]]; then
  echo "       Prefix already has objects, skipping marker."
else
  echo "       Prefix empty — uploading marker object ..."
  $AWS s3api put-object \
    --bucket "$S3_BUCKET" \
    --key "${S3_PREFIX}/.keep" \
    --content-length 0 \
    > /dev/null
  echo "       Marker created: s3://${S3_BUCKET}/${S3_PREFIX}/.keep"
fi

# ---------------------------------------------------------------------------
# 4. S3 Gateway VPC Endpoint
# ---------------------------------------------------------------------------
echo "[3/3] Checking S3 Gateway VPC Endpoint ..."

EXISTING_VPCE=$($AWS ec2 describe-vpc-endpoints \
  --filters \
    "Name=service-name,Values=com.amazonaws.${AWS_REGION}.s3" \
    "Name=vpc-id,Values=${VPC_ID}" \
  --query 'VpcEndpoints[0].VpcEndpointId' \
  --output text)

if [[ -n "$EXISTING_VPCE" && "$EXISTING_VPCE" != "None" ]]; then
  echo "       Endpoint already exists: $EXISTING_VPCE — skipping."
else
  ROUTE_TABLE_IDS=$($AWS ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'RouteTables[*].RouteTableId' \
    --output text)

  if [[ -z "$ROUTE_TABLE_IDS" ]]; then
    echo "ERROR: No route tables found for VPC $VPC_ID"
    exit 1
  fi

  echo "       Route tables: $ROUTE_TABLE_IDS"

  VPCE_OUT=$($AWS ec2 create-vpc-endpoint \
    --vpc-id "$VPC_ID" \
    --service-name "com.amazonaws.${AWS_REGION}.s3" \
    --route-table-ids $ROUTE_TABLE_IDS \
    --vpc-endpoint-type Gateway \
    --output json)

  EXISTING_VPCE=$(echo "$VPCE_OUT" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['VpcEndpoint']['VpcEndpointId'])" \
    2>/dev/null || echo "unknown")

  echo "       VPC Endpoint created: $EXISTING_VPCE"

  $AWS ec2 create-tags \
    --resources "$EXISTING_VPCE" \
    --tags "Key=Name,Value=dojangkok-v2-s3-gateway" "Key=Project,Value=dojangkok"

  echo "       Endpoint tagged."
fi

# ---------------------------------------------------------------------------
# 5. Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================="
echo " S3 & VPC Endpoint - Setup Complete"
echo "============================================="
echo " Bucket       : $S3_BUCKET"
echo " Prefix       : $S3_PREFIX"
echo " VPC Endpoint : $EXISTING_VPCE"
echo "============================================="
