#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 00_preflight.sh - Pre-flight checks for V2 monitoring server setup
# =============================================================================
# Validates environment variables, AWS credentials, and target resources
# before proceeding with infrastructure creation.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

pass()  { echo -e "  ${GREEN}[PASS]${NC} $1"; }
fail()  { echo -e "  ${RED}[FAIL]${NC} $1"; ERRORS=$((ERRORS + 1)); }
info()  { echo -e "  ${CYAN}[INFO]${NC} $1"; }
header(){ echo -e "\n${BOLD}$1${NC}"; }

ERRORS=0

# ---------------------------------------------------------------------------
# 1. Load .env
# ---------------------------------------------------------------------------
header "1. Loading environment file"

if [[ ! -f "$ENV_FILE" ]]; then
    fail ".env file not found at ${ENV_FILE}"
    echo -e "\n${RED}Create it first:${NC}  cp env.example .env  then fill in blank values."
    exit 1
fi

# Source .env (skip comments and blank lines)
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

pass ".env loaded from ${ENV_FILE}"

# ---------------------------------------------------------------------------
# 2. Validate required variables are set (non-empty)
# ---------------------------------------------------------------------------
header "2. Validating required environment variables"

REQUIRED_VARS=(
    AWS_PROFILE
    AWS_REGION
    VPC_ID
    SUBNET_ID
    INSTANCE_TYPE
    VOLUME_SIZE
    AMI_ID
    S3_BUCKET
    S3_PREFIX
    NAME_PREFIX
    ADMIN_IP
    DEV_VPC_CIDR
    GCP_NAT_IP
    GRAFANA_ADMIN_PASSWORD
    TARGET_MYSQL_IP
    TARGET_REDIS_IP
    TARGET_MQ_IP
    TARGET_MYSQL_INSTANCE_ID
    TARGET_REDIS_INSTANCE_ID
    TARGET_MQ_INSTANCE_ID
    BE_LAUNCH_TEMPLATE_ID
    FE_LAUNCH_TEMPLATE_ID
)

MISSING=0
for var in "${REQUIRED_VARS[@]}"; do
    val="${!var:-}"
    if [[ -z "$val" ]]; then
        fail "${var} is not set"
        MISSING=$((MISSING + 1))
    fi
done

if [[ $MISSING -eq 0 ]]; then
    pass "All ${#REQUIRED_VARS[@]} required variables are set"
else
    fail "${MISSING}/${#REQUIRED_VARS[@]} required variables are missing"
fi

# ---------------------------------------------------------------------------
# AWS CLI common flags
# ---------------------------------------------------------------------------
AWS_OPTS="--profile ${AWS_PROFILE} --region ${AWS_REGION}"

# ---------------------------------------------------------------------------
# 3. Verify AWS credentials
# ---------------------------------------------------------------------------
header "3. Verifying AWS credentials"

if CALLER_IDENTITY=$(aws sts get-caller-identity ${AWS_OPTS} --output json 2>&1); then
    ACCOUNT=$(echo "$CALLER_IDENTITY" | python3 -c "import sys,json; print(json.load(sys.stdin)['Account'])" 2>/dev/null || echo "unknown")
    ARN=$(echo "$CALLER_IDENTITY" | python3 -c "import sys,json; print(json.load(sys.stdin)['Arn'])" 2>/dev/null || echo "unknown")
    pass "Authenticated  Account=${ACCOUNT}  ARN=${ARN}"
else
    fail "AWS authentication failed: ${CALLER_IDENTITY}"
fi

# ---------------------------------------------------------------------------
# 4. Check VPC exists
# ---------------------------------------------------------------------------
header "4. Checking VPC"

if VPC_OUT=$(aws ec2 describe-vpcs --vpc-ids "${VPC_ID}" ${AWS_OPTS} --output json 2>&1); then
    VPC_CIDR=$(echo "$VPC_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Vpcs'][0]['CidrBlock'])" 2>/dev/null || echo "unknown")
    VPC_STATE=$(echo "$VPC_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Vpcs'][0]['State'])" 2>/dev/null || echo "unknown")
    pass "VPC ${VPC_ID}  CIDR=${VPC_CIDR}  State=${VPC_STATE}"
else
    fail "VPC ${VPC_ID} not found: ${VPC_OUT}"
fi

# ---------------------------------------------------------------------------
# 5. Check subnet exists
# ---------------------------------------------------------------------------
header "5. Checking Subnet"

if [[ -n "${SUBNET_ID:-}" ]]; then
    if SUBNET_OUT=$(aws ec2 describe-subnets --subnet-ids "${SUBNET_ID}" ${AWS_OPTS} --output json 2>&1); then
        SUBNET_CIDR=$(echo "$SUBNET_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Subnets'][0]['CidrBlock'])" 2>/dev/null || echo "unknown")
        SUBNET_AZ=$(echo "$SUBNET_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Subnets'][0]['AvailabilityZone'])" 2>/dev/null || echo "unknown")
        SUBNET_PUBLIC=$(echo "$SUBNET_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Subnets'][0].get('MapPublicIpOnLaunch', False))" 2>/dev/null || echo "unknown")
        pass "Subnet ${SUBNET_ID}  CIDR=${SUBNET_CIDR}  AZ=${SUBNET_AZ}  AutoPublicIP=${SUBNET_PUBLIC}"
    else
        fail "Subnet ${SUBNET_ID} not found: ${SUBNET_OUT}"
    fi
else
    fail "SUBNET_ID is empty, skipping subnet check"
fi

# ---------------------------------------------------------------------------
# 6. List all subnets in VPC (for reference)
# ---------------------------------------------------------------------------
header "6. Subnets in VPC ${VPC_ID} (reference)"

if SUBNETS_OUT=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    ${AWS_OPTS} \
    --query 'Subnets[*].[SubnetId,CidrBlock,AvailabilityZone,Tags[?Key==`Name`].Value | [0]]' \
    --output text 2>&1); then
    if [[ -n "$SUBNETS_OUT" ]]; then
        echo ""
        printf "  ${CYAN}%-25s %-18s %-25s %s${NC}\n" "SubnetId" "CIDR" "AZ" "Name"
        echo "  ------------------------------------------------------------------------------------"
        while IFS=$'\t' read -r sid cidr az name; do
            printf "  %-25s %-18s %-25s %s\n" "$sid" "$cidr" "$az" "${name:-N/A}"
        done <<< "$SUBNETS_OUT"
        echo ""
    else
        info "No subnets found in VPC ${VPC_ID}"
    fi
else
    fail "Failed to list subnets: ${SUBNETS_OUT}"
fi

# ---------------------------------------------------------------------------
# 7. Check AMI exists
# ---------------------------------------------------------------------------
header "7. Checking AMI"

if [[ -n "${AMI_ID:-}" ]]; then
    if AMI_OUT=$(aws ec2 describe-images --image-ids "${AMI_ID}" ${AWS_OPTS} --output json 2>&1); then
        AMI_NAME=$(echo "$AMI_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Images'][0].get('Name','unknown'))" 2>/dev/null || echo "unknown")
        AMI_ARCH=$(echo "$AMI_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Images'][0].get('Architecture','unknown'))" 2>/dev/null || echo "unknown")
        AMI_STATE=$(echo "$AMI_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Images'][0].get('State','unknown'))" 2>/dev/null || echo "unknown")
        pass "AMI ${AMI_ID}  Name=${AMI_NAME}  Arch=${AMI_ARCH}  State=${AMI_STATE}"
    else
        fail "AMI ${AMI_ID} not found: ${AMI_OUT}"
    fi
else
    fail "AMI_ID is empty, skipping AMI check"
fi

# ---------------------------------------------------------------------------
# 8. Check S3 Bucket
# ---------------------------------------------------------------------------
header "8. Checking S3 Bucket"

if aws s3api head-bucket --bucket "${S3_BUCKET}" ${AWS_OPTS} 2>/dev/null; then
    pass "S3 bucket ${S3_BUCKET} exists"

    # Check if prefix exists
    obj_count=$(aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" ${AWS_OPTS} 2>/dev/null | wc -l || echo "0")
    info "S3 prefix ${S3_PREFIX}/ has ${obj_count} objects"
else
    info "S3 bucket ${S3_BUCKET} does not exist (will be created by 01.5_create_s3.sh)"
fi

# ---------------------------------------------------------------------------
# 9. Summary
# ---------------------------------------------------------------------------
header "========================================="
header " Pre-flight Check Summary"
header "========================================="

echo ""
if [[ $ERRORS -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}All checks passed.${NC} Ready to proceed."
else
    echo -e "  ${RED}${BOLD}${ERRORS} check(s) failed.${NC} Fix the issues above before continuing."
fi

echo ""
echo -e "  ${BOLD}Configuration:${NC}"
echo -e "    Profile:       ${AWS_PROFILE}"
echo -e "    Region:        ${AWS_REGION}"
echo -e "    VPC:           ${VPC_ID}"
echo -e "    Subnet:        ${SUBNET_ID:-${RED}NOT SET${NC}}"
echo -e "    Instance Type: ${INSTANCE_TYPE}"
echo -e "    Volume Size:   ${VOLUME_SIZE} GB"
echo -e "    AMI:           ${AMI_ID:-${RED}NOT SET${NC}}"
echo -e "    Name Prefix:   ${NAME_PREFIX}"
echo ""

exit $ERRORS
