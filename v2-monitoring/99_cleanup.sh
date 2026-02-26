#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 99_cleanup.sh - Reverse cleanup of V2 monitoring infrastructure
# =============================================================================
# Tears down all resources created by the monitoring-v2 scripts, in reverse
# order. Each destructive step asks for confirmation.
#
# Order:
#   1. Stop/remove Alloy on all target instances
#   2. Clean S3 prefix (shared bucket, only remove our prefix)
#   3. Delete S3 VPC Endpoint
#   4. Release Elastic IP (disassociate + release)
#   5. Terminate EC2 monitor instance + wait
#   6. Delete instance profile (remove role, delete profile)
#   7. Delete IAM role (detach policy, delete role)
#   8. Delete Security Group
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# 1. Source .env
# ---------------------------------------------------------------------------
if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
  echo "ERROR: $SCRIPT_DIR/.env not found."
  exit 1
fi

# shellcheck source=/dev/null
source "$SCRIPT_DIR/.env"

# ---------------------------------------------------------------------------
# 2. AWS CLI shorthand
# ---------------------------------------------------------------------------
AWS="aws --profile $AWS_PROFILE --region $AWS_REGION"

# ---------------------------------------------------------------------------
# 3. Color helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "  ${YELLOW}[SKIP]${NC} $1"; }
err()   { echo -e "  ${RED}[ERROR]${NC} $1"; }

# ---------------------------------------------------------------------------
# 4. Confirmation helper
# ---------------------------------------------------------------------------
confirm() {
  local msg="$1"
  echo ""
  echo -e "${YELLOW}${BOLD}$msg${NC}"
  read -rp "  Proceed? [y/N] " answer
  case "$answer" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# 5. SSM helper (for Alloy removal)
# ---------------------------------------------------------------------------
ssm_run() {
  local instance_id="$1"
  local commands="$2"
  local timeout="${3:-60}"

  local cmd_id
  cmd_id=$($AWS ssm send-command \
    --instance-ids "$instance_id" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":[$commands]}" \
    --timeout-seconds "$timeout" \
    --output text --query 'Command.CommandId' 2>/dev/null) || return 1

  local status="InProgress"
  local waited=0
  while [[ "$status" == "InProgress" || "$status" == "Pending" ]] && (( waited < timeout )); do
    sleep 5
    waited=$((waited + 5))
    status=$($AWS ssm get-command-invocation \
      --command-id "$cmd_id" \
      --instance-id "$instance_id" \
      --query 'Status' --output text 2>/dev/null || echo "InProgress")
  done

  if [[ "$status" == "Success" ]]; then
    return 0
  else
    return 1
  fi
}

echo "============================================="
echo " V2 Monitoring - Cleanup"
echo "============================================="
echo "Profile  : $AWS_PROFILE"
echo "Region   : $AWS_REGION"
echo "Prefix   : ${NAME_PREFIX}"
echo ""
echo -e "${RED}${BOLD}WARNING: This will destroy monitoring infrastructure.${NC}"

# ---------------------------------------------------------------------------
# 6. Step 1: Stop Alloy on target instances
# ---------------------------------------------------------------------------
if confirm "Step 1/8: Stop and remove Alloy on all target instances?"; then
  echo ""
  echo "[1/8] Removing Alloy from target instances ..."

  declare -A TARGETS=(
    [be]="${TARGET_BE_INSTANCE_ID:-}"
    [fe]="${TARGET_FE_INSTANCE_ID:-}"
    [mysql]="${TARGET_MYSQL_INSTANCE_ID:-}"
    [redis]="${TARGET_REDIS_INSTANCE_ID:-}"
    [mq]="${TARGET_MQ_INSTANCE_ID:-}"
  )

  ALLOY_REMOVE_CMD="\"systemctl stop alloy 2>/dev/null || true\",\"systemctl disable alloy 2>/dev/null || true\",\"rm -f /etc/systemd/system/alloy.service /usr/local/bin/alloy\",\"rm -rf /etc/alloy /var/lib/alloy\",\"systemctl daemon-reload\",\"echo Alloy removed\""

  for target in "${!TARGETS[@]}"; do
    instance_id="${TARGETS[$target]}"
    if [[ -z "$instance_id" ]]; then
      warn "${target}: instance ID not set, skipping"
      continue
    fi

    echo "  Removing Alloy from ${target} (${instance_id}) ..."

    # Check if instance is reachable via SSM
    if ! ssm_run "$instance_id" "\"echo OK\"" 15 2>/dev/null; then
      warn "${target} (${instance_id}): not reachable via SSM, skipping"
      continue
    fi

    if ssm_run "$instance_id" "$ALLOY_REMOVE_CMD" 60; then
      info "${target}: Alloy removed"
    else
      err "${target}: failed to remove Alloy (non-fatal, continuing)"
    fi
  done
else
  warn "Step 1 skipped"
fi

# ---------------------------------------------------------------------------
# 7. Step 2: Clean S3 prefix
# ---------------------------------------------------------------------------
if confirm "Step 2/8: Clean S3 prefix ${S3_PREFIX} in ${S3_BUCKET}?"; then
  echo ""
  echo "[2/8] Cleaning S3 prefix ${S3_PREFIX}/ in bucket ${S3_BUCKET} ..."

  $AWS s3 rm "s3://${S3_BUCKET}/${S3_PREFIX}/" --recursive
  info "S3 prefix cleaned: s3://${S3_BUCKET}/${S3_PREFIX}/"
else
  warn "Step 2 skipped"
fi

# ---------------------------------------------------------------------------
# 8. Step 3: Delete S3 VPC Endpoint
# ---------------------------------------------------------------------------
if confirm "Step 3/8: Delete S3 VPC Endpoint?"; then
  echo ""
  echo "[3/8] Deleting S3 VPC Endpoint ..."

  VPCE_ID=$($AWS ec2 describe-vpc-endpoints \
    --filters "Name=service-name,Values=com.amazonaws.${AWS_REGION}.s3" "Name=vpc-id,Values=${VPC_ID}" \
    --query 'VpcEndpoints[0].VpcEndpointId' --output text 2>/dev/null) || VPCE_ID="None"
  if [[ "$VPCE_ID" != "None" && -n "$VPCE_ID" ]]; then
    $AWS ec2 delete-vpc-endpoints --vpc-endpoint-ids "$VPCE_ID"
    info "VPC Endpoint deleted: $VPCE_ID"
  else
    warn "No S3 VPC Endpoint found"
  fi
else
  warn "Step 3 skipped"
fi

# ---------------------------------------------------------------------------
# 9. Step 4: Release Elastic IP
# ---------------------------------------------------------------------------
if confirm "Step 4/8: Release Elastic IP for ${NAME_PREFIX}?"; then
  echo ""
  echo "[4/8] Releasing Elastic IP ..."

  # Find allocation by tag
  ALLOC_ID=$($AWS ec2 describe-addresses \
    --filters "Name=tag:Name,Values=${NAME_PREFIX}-eip" \
    --query 'Addresses[0].AllocationId' --output text 2>/dev/null) || ALLOC_ID="None"

  if [[ "$ALLOC_ID" == "None" || -z "$ALLOC_ID" ]]; then
    warn "No EIP found with tag ${NAME_PREFIX}-eip"
  else
    # Disassociate first
    ASSOC_ID=$($AWS ec2 describe-addresses \
      --allocation-ids "$ALLOC_ID" \
      --query 'Addresses[0].AssociationId' --output text 2>/dev/null) || ASSOC_ID="None"

    if [[ "$ASSOC_ID" != "None" && -n "$ASSOC_ID" ]]; then
      echo "  Disassociating EIP (association: ${ASSOC_ID}) ..."
      $AWS ec2 disassociate-address --association-id "$ASSOC_ID"
      info "EIP disassociated"
    fi

    echo "  Releasing EIP (allocation: ${ALLOC_ID}) ..."
    $AWS ec2 release-address --allocation-id "$ALLOC_ID"
    info "EIP released: $ALLOC_ID"
  fi
else
  warn "Step 4 skipped"
fi

# ---------------------------------------------------------------------------
# 10. Step 5: Terminate EC2 instance
# ---------------------------------------------------------------------------
if confirm "Step 5/8: Terminate EC2 instance ${MONITOR_INSTANCE_ID:-'(not set)'}?"; then
  echo ""
  echo "[5/8] Terminating EC2 instance ..."

  INSTANCE_ID="${MONITOR_INSTANCE_ID:-}"

  if [[ -z "$INSTANCE_ID" ]]; then
    warn "MONITOR_INSTANCE_ID not set in .env, skipping"
  else
    # Check if instance exists and is not already terminated
    INSTANCE_STATE=$($AWS ec2 describe-instances \
      --instance-ids "$INSTANCE_ID" \
      --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null) || INSTANCE_STATE="not-found"

    if [[ "$INSTANCE_STATE" == "terminated" ]]; then
      warn "Instance ${INSTANCE_ID} is already terminated"
    elif [[ "$INSTANCE_STATE" == "not-found" ]]; then
      warn "Instance ${INSTANCE_ID} not found"
    else
      echo "  Terminating instance ${INSTANCE_ID} (current state: ${INSTANCE_STATE}) ..."
      $AWS ec2 terminate-instances --instance-ids "$INSTANCE_ID" --output text >/dev/null
      echo "  Waiting for termination ..."
      $AWS ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
      info "Instance terminated: $INSTANCE_ID"
    fi
  fi
else
  warn "Step 5 skipped"
fi

# ---------------------------------------------------------------------------
# 11. Step 6: Delete instance profile
# ---------------------------------------------------------------------------
PROFILE_NAME="${NAME_PREFIX}-profile"
ROLE_NAME="${NAME_PREFIX}-role"

if confirm "Step 6/8: Delete instance profile ${PROFILE_NAME}?"; then
  echo ""
  echo "[6/8] Deleting instance profile ..."

  # Check if instance profile exists
  if $AWS iam get-instance-profile --instance-profile-name "$PROFILE_NAME" >/dev/null 2>&1; then
    # Remove role from profile
    echo "  Removing role ${ROLE_NAME} from profile ..."
    $AWS iam remove-role-from-instance-profile \
      --instance-profile-name "$PROFILE_NAME" \
      --role-name "$ROLE_NAME" 2>/dev/null || warn "Role not attached to profile (already removed?)"

    echo "  Deleting instance profile ..."
    $AWS iam delete-instance-profile --instance-profile-name "$PROFILE_NAME"
    info "Instance profile deleted: $PROFILE_NAME"
  else
    warn "Instance profile ${PROFILE_NAME} does not exist"
  fi
else
  warn "Step 6 skipped"
fi

# ---------------------------------------------------------------------------
# 12. Step 7: Delete IAM role
# ---------------------------------------------------------------------------
if confirm "Step 7/8: Delete IAM role ${ROLE_NAME}?"; then
  echo ""
  echo "[7/8] Deleting IAM role ..."

  # Check if role exists
  if $AWS iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    # Delete known inline policy (S3 read)
    S3_INLINE_POLICY="${NAME_PREFIX}-s3-read"
    echo "  Checking inline policy ${S3_INLINE_POLICY} ..."
    if $AWS iam get-role-policy --role-name "$ROLE_NAME" --policy-name "$S3_INLINE_POLICY" >/dev/null 2>&1; then
      echo "    Deleting inline policy: $S3_INLINE_POLICY"
      $AWS iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$S3_INLINE_POLICY"
      info "Inline policy deleted: $S3_INLINE_POLICY"
    else
      warn "Inline policy ${S3_INLINE_POLICY} not found (already removed?)"
    fi

    # Detach managed policies
    echo "  Detaching managed policies ..."
    POLICIES=$($AWS iam list-attached-role-policies \
      --role-name "$ROLE_NAME" \
      --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null) || POLICIES=""

    for policy_arn in $POLICIES; do
      echo "    Detaching: $policy_arn"
      $AWS iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$policy_arn"
    done

    # Delete remaining inline policies (if any)
    INLINE_POLICIES=$($AWS iam list-role-policies \
      --role-name "$ROLE_NAME" \
      --query 'PolicyNames[*]' --output text 2>/dev/null) || INLINE_POLICIES=""

    for policy_name in $INLINE_POLICIES; do
      echo "    Deleting inline policy: $policy_name"
      $AWS iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$policy_name"
    done

    echo "  Deleting role ..."
    $AWS iam delete-role --role-name "$ROLE_NAME"
    info "IAM role deleted: $ROLE_NAME"
  else
    warn "IAM role ${ROLE_NAME} does not exist"
  fi
else
  warn "Step 7 skipped"
fi

# ---------------------------------------------------------------------------
# 13. Step 8: Delete Security Group
# ---------------------------------------------------------------------------
SG_NAME="${NAME_PREFIX}-sg"

if confirm "Step 8/8: Delete Security Group ${SG_NAME}?"; then
  echo ""
  echo "[8/8] Deleting Security Group ..."

  # Find SG by name in the VPC
  SG_ID=$($AWS ec2 describe-security-groups \
    --filters "Name=group-name,Values=${SG_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null) || SG_ID="None"

  if [[ "$SG_ID" == "None" || -z "$SG_ID" ]]; then
    warn "Security Group ${SG_NAME} not found in VPC ${VPC_ID}"
  else
    echo "  Deleting SG ${SG_ID} (${SG_NAME}) ..."
    if $AWS ec2 delete-security-group --group-id "$SG_ID"; then
      info "Security Group deleted: $SG_ID ($SG_NAME)"
    else
      err "Failed to delete SG. It may have dependencies (ENIs, instances)."
      echo "  If the instance was just terminated, wait a minute and retry."
    fi
  fi
else
  warn "Step 8 skipped"
fi

# ---------------------------------------------------------------------------
# 14. Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================="
echo " V2 Monitoring - Cleanup Complete"
echo "============================================="
echo ""
echo "  Cleared .env values to update manually:"
echo "    MONITOR_INSTANCE_ID"
echo "    MONITOR_PUBLIC_IP"
echo "    MONITOR_PRIVATE_IP"
echo ""
echo "  If you plan to re-deploy, run scripts in order:"
echo "    00_preflight.sh -> 01_create_monitor.sh -> 02_install_stack.sh -> 03_install_alloy.sh"
echo ""
