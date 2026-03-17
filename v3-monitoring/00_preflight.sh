#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 00_preflight.sh - Pre-flight checks for V3 monitoring server setup
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
pass()  { echo -e "  ${GREEN}[PASS]${NC} $1"; }
fail()  { echo -e "  ${RED}[FAIL]${NC} $1"; ERRORS=$((ERRORS + 1)); }
info()  { echo -e "  ${CYAN}[INFO]${NC} $1"; }
header(){ echo -e "\n${BOLD}$1${NC}"; }

ERRORS=0

# --- 1. Load .env ---
header "1. Loading environment file"
if [[ ! -f "$ENV_FILE" ]]; then
    fail ".env file not found at ${ENV_FILE}"
    echo -e "\n${RED}Create it first:${NC}  cp env.example .env  then fill in blank values."
    exit 1
fi
set -a; source "$ENV_FILE"; set +a
pass ".env loaded"

# --- 2. Required variables ---
header "2. Validating required environment variables"
REQUIRED_VARS=(
    AWS_PROFILE AWS_REGION VPC_ID SUBNET_ID INSTANCE_TYPE AMI_ID
    NAME_PREFIX ENV_NAME S3_MONITORING_BUCKET S3_CONFIG_BUCKET S3_CONFIG_PREFIX
    ADMIN_IP VPC_CIDR GRAFANA_ADMIN_PASSWORD
    TARGET_MYSQL_INSTANCE_ID TARGET_REDIS_INSTANCE_ID TARGET_MQ_INSTANCE_ID
    BE_LAUNCH_TEMPLATE_ID FE_LAUNCH_TEMPLATE_ID
)

MISSING=0
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        fail "${var} is not set"
        MISSING=$((MISSING + 1))
    fi
done
[[ $MISSING -eq 0 ]] && pass "All ${#REQUIRED_VARS[@]} required variables are set"

AWS_OPTS="--profile ${AWS_PROFILE} --region ${AWS_REGION}"

# --- 3. AWS credentials ---
header "3. Verifying AWS credentials"
if CALLER_IDENTITY=$(aws sts get-caller-identity ${AWS_OPTS} --output json 2>&1); then
    ACCOUNT=$(echo "$CALLER_IDENTITY" | python3 -c "import sys,json; print(json.load(sys.stdin)['Account'])" 2>/dev/null || echo "unknown")
    pass "Authenticated  Account=${ACCOUNT}"
else
    fail "AWS authentication failed"
fi

# --- 4. VPC ---
header "4. Checking VPC"
if VPC_OUT=$(aws ec2 describe-vpcs --vpc-ids "${VPC_ID}" ${AWS_OPTS} --output json 2>&1); then
    VPC_CIDR_ACTUAL=$(echo "$VPC_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Vpcs'][0]['CidrBlock'])" 2>/dev/null || echo "unknown")
    pass "VPC ${VPC_ID}  CIDR=${VPC_CIDR_ACTUAL}"
else
    fail "VPC ${VPC_ID} not found"
fi

# --- 5. Subnet ---
header "5. Checking Subnet"
if SUBNET_OUT=$(aws ec2 describe-subnets --subnet-ids "${SUBNET_ID}" ${AWS_OPTS} --output json 2>&1); then
    SUBNET_AZ=$(echo "$SUBNET_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Subnets'][0]['AvailabilityZone'])" 2>/dev/null || echo "unknown")
    pass "Subnet ${SUBNET_ID}  AZ=${SUBNET_AZ}"
else
    fail "Subnet ${SUBNET_ID} not found"
fi

# --- 6. AMI ---
header "6. Checking AMI"
if AMI_OUT=$(aws ec2 describe-images --image-ids "${AMI_ID}" ${AWS_OPTS} --output json 2>&1); then
    AMI_ARCH=$(echo "$AMI_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Images'][0].get('Architecture','unknown'))" 2>/dev/null || echo "unknown")
    pass "AMI ${AMI_ID}  Arch=${AMI_ARCH}"
else
    fail "AMI ${AMI_ID} not found"
fi

# --- 7. Terraform ---
header "7. Checking Terraform"
if command -v terraform &>/dev/null; then
    TF_VERSION=$(terraform version -json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['terraform_version'])" 2>/dev/null || terraform version | head -1)
    pass "Terraform: ${TF_VERSION}"
else
    fail "Terraform not installed"
fi

# --- 8. S3 Config Bucket ---
header "8. Checking S3 Config Bucket"
if aws s3api head-bucket --bucket "${S3_CONFIG_BUCKET}" ${AWS_OPTS} 2>/dev/null; then
    pass "S3 config bucket ${S3_CONFIG_BUCKET} exists"
else
    info "S3 config bucket ${S3_CONFIG_BUCKET} does not exist"
fi

# --- 9. Summary ---
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
echo -e "    Subnet:        ${SUBNET_ID}"
echo -e "    Instance Type: ${INSTANCE_TYPE}"
echo -e "    Name Prefix:   ${NAME_PREFIX}"
echo -e "    Env Name:      ${ENV_NAME}"
echo -e "    S3 Monitoring: ${S3_MONITORING_BUCKET}"
echo ""
exit $ERRORS
