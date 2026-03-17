#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 00_preflight.sh - Pre-flight checks for V3 monitoring setup
# =============================================================================
# EC2 인스턴스는 수동 생성 후 .env에 기입.
# 이 스크립트는 .env 값, AWS 자격증명, SSM 연결을 검증한다.
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
    AWS_PROFILE AWS_REGION VPC_ID
    NAME_PREFIX ENV_NAME S3_MONITORING_BUCKET MONITOR_IAM_ROLE
    S3_CONFIG_BUCKET S3_CONFIG_PREFIX
    GRAFANA_ADMIN_PASSWORD
    MONITOR_INSTANCE_ID MONITOR_PUBLIC_IP MONITOR_PRIVATE_IP
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

# --- 4. Monitor instance ---
header "4. Checking Monitor instance"
if INST_OUT=$(aws ec2 describe-instances --instance-ids "${MONITOR_INSTANCE_ID}" ${AWS_OPTS} --output json 2>&1); then
    INST_STATE=$(echo "$INST_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Reservations'][0]['Instances'][0]['State']['Name'])" 2>/dev/null || echo "unknown")
    INST_TYPE=$(echo "$INST_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Reservations'][0]['Instances'][0]['InstanceType'])" 2>/dev/null || echo "unknown")
    if [[ "$INST_STATE" == "running" ]]; then
        pass "Instance ${MONITOR_INSTANCE_ID}  Type=${INST_TYPE}  State=${INST_STATE}"
    else
        fail "Instance ${MONITOR_INSTANCE_ID} is ${INST_STATE} (expected running)"
    fi
else
    fail "Instance ${MONITOR_INSTANCE_ID} not found"
fi

# --- 5. SSM connectivity ---
header "5. Checking SSM connectivity"
SSM_STATUS=$(aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=${MONITOR_INSTANCE_ID}" \
  ${AWS_OPTS} \
  --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null) || SSM_STATUS="None"

if [[ "$SSM_STATUS" == "Online" ]]; then
    pass "SSM: Online"
else
    fail "SSM: ${SSM_STATUS} (expected Online, wait ~2 min after instance start)"
fi

# --- 6. IAM Role ---
header "6. Checking IAM Role"
if aws iam get-role --role-name "${MONITOR_IAM_ROLE}" ${AWS_OPTS%--region*} >/dev/null 2>&1; then
    pass "IAM Role: ${MONITOR_IAM_ROLE}"
else
    fail "IAM Role ${MONITOR_IAM_ROLE} not found"
fi

# --- 7. S3 Config Bucket ---
header "7. Checking S3 Config Bucket"
if aws s3api head-bucket --bucket "${S3_CONFIG_BUCKET}" ${AWS_OPTS} 2>/dev/null; then
    pass "S3 config bucket: ${S3_CONFIG_BUCKET}"
else
    fail "S3 config bucket ${S3_CONFIG_BUCKET} not found"
fi

# --- 8. Summary ---
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
echo -e "  ${BOLD}Monitor Server:${NC}"
echo -e "    Instance ID: ${MONITOR_INSTANCE_ID}"
echo -e "    Public IP:   ${MONITOR_PUBLIC_IP}"
echo -e "    Private IP:  ${MONITOR_PRIVATE_IP}"
echo ""
echo -e "  ${BOLD}Configuration:${NC}"
echo -e "    Profile:       ${AWS_PROFILE}"
echo -e "    Region:        ${AWS_REGION}"
echo -e "    Name Prefix:   ${NAME_PREFIX}"
echo -e "    Env Name:      ${ENV_NAME}"
echo -e "    S3 Monitoring: ${S3_MONITORING_BUCKET}"
echo -e "    IAM Role:      ${MONITOR_IAM_ROLE}"
echo ""
exit $ERRORS
