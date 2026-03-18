#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 99_cleanup.sh - Destroy V3 monitoring infrastructure
# =============================================================================
# 1. Stop Alloy on target instances
# 2. Empty S3 monitoring bucket (required before terraform destroy)
# 3. Terraform destroy (EC2, SG, EIP, S3, IAM)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

source "$SCRIPT_DIR/.env"

AWS="aws --profile $AWS_PROFILE --region $AWS_REGION"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "  ${YELLOW}[SKIP]${NC} $1"; }

confirm() {
  echo -e "\n${YELLOW}${BOLD}$1${NC}"
  read -rp "  Proceed? [y/N] " answer
  case "$answer" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

ssm_run() {
  local instance_id="$1" commands="$2" timeout="${3:-60}"
  local cmd_id
  cmd_id=$($AWS ssm send-command \
    --instance-ids "$instance_id" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":[$commands]}" \
    --timeout-seconds "$timeout" \
    --output text --query 'Command.CommandId' 2>/dev/null) || return 1

  local status="InProgress" waited=0
  while [[ "$status" == "InProgress" || "$status" == "Pending" ]] && (( waited < timeout )); do
    sleep 5; waited=$((waited + 5))
    status=$($AWS ssm get-command-invocation \
      --command-id "$cmd_id" --instance-id "$instance_id" \
      --query 'Status' --output text 2>/dev/null || echo "InProgress")
  done
  [[ "$status" == "Success" ]]
}

echo "============================================="
echo " V3 Monitoring - Cleanup"
echo "============================================="
echo "Prefix  : ${NAME_PREFIX}"
echo "S3      : ${S3_MONITORING_BUCKET}"
echo ""
echo -e "${RED}${BOLD}WARNING: This will destroy ALL monitoring infrastructure.${NC}"

# --- Step 1: Stop Alloy ---
if confirm "Step 1/3: Stop Alloy on target instances?"; then
  echo "[1/3] Removing Alloy ..."
  ALLOY_CMD="\"systemctl stop alloy 2>/dev/null || true\",\"systemctl disable alloy 2>/dev/null || true\",\"rm -f /etc/systemd/system/alloy.service /usr/local/bin/alloy\",\"rm -rf /etc/alloy /var/lib/alloy\",\"systemctl daemon-reload\",\"echo Alloy removed\""

  for target_var in TARGET_MYSQL_INSTANCE_ID TARGET_REDIS_INSTANCE_ID TARGET_MQ_INSTANCE_ID; do
    instance_id="${!target_var:-}"
    [[ -z "$instance_id" ]] && continue
    echo "  Removing from ${target_var} (${instance_id}) ..."
    ssm_run "$instance_id" "$ALLOY_CMD" 60 && info "Removed" || warn "Not reachable"
  done
else
  warn "Step 1 skipped"
fi

# --- Step 2: Empty S3 bucket ---
if confirm "Step 2/3: Empty S3 bucket ${S3_MONITORING_BUCKET}?"; then
  echo "[2/3] Emptying S3 bucket ..."
  if $AWS s3api head-bucket --bucket "$S3_MONITORING_BUCKET" 2>/dev/null; then
    $AWS s3 rm "s3://${S3_MONITORING_BUCKET}/" --recursive
    info "S3 bucket emptied"
  else
    warn "Bucket not found"
  fi

  # Also clean config prefix
  if [[ -n "${S3_CONFIG_BUCKET:-}" && -n "${S3_CONFIG_PREFIX:-}" ]]; then
    echo "  Cleaning config prefix: s3://${S3_CONFIG_BUCKET}/${S3_CONFIG_PREFIX}/"
    $AWS s3 rm "s3://${S3_CONFIG_BUCKET}/${S3_CONFIG_PREFIX}/" --recursive 2>/dev/null || true
    info "Config prefix cleaned"
  fi
else
  warn "Step 2 skipped"
fi

# --- Step 3: Terraform destroy ---
if confirm "Step 3/3: Run terraform destroy?"; then
  echo "[3/3] Running terraform destroy ..."
  cd "$TF_DIR"

  if [[ ! -f "terraform.tfvars" ]]; then
    echo "ERROR: terraform.tfvars not found. Run 01_create_monitor.sh first."
    exit 1
  fi

  terraform destroy -input=false -auto-approve
  info "Terraform destroy complete"
  cd "$SCRIPT_DIR"
else
  warn "Step 3 skipped"
fi

echo ""
echo "============================================="
echo " V3 Monitoring - Cleanup Complete"
echo "============================================="
echo ""
echo "  Clear .env values manually:"
echo "    MONITOR_INSTANCE_ID"
echo "    MONITOR_PUBLIC_IP"
echo "    MONITOR_PRIVATE_IP"
echo ""
echo "  To re-deploy: 00_preflight.sh -> 01_create_monitor.sh -> 02_install_stack.sh -> 03_install_alloy.sh"
echo ""
