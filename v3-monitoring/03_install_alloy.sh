#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 03_install_alloy.sh - Deploy Alloy configs to all targets
# =============================================================================
# Same as v2: S3 upload + LT update + SSM deploy to running instances
# Alloy configs are unchanged from v2 (push target is the same)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOY_DIR="${SCRIPT_DIR}/alloy"

source "$SCRIPT_DIR/.env"

REQUIRED_VARS=(
  AWS_PROFILE AWS_REGION MONITOR_PRIVATE_IP MONITOR_INSTANCE_ID
  S3_CONFIG_BUCKET S3_CONFIG_PREFIX VPC_ID NAME_PREFIX
  BE_LAUNCH_TEMPLATE_ID FE_LAUNCH_TEMPLATE_ID BE_ASG_NAME FE_ASG_NAME
  TARGET_MYSQL_INSTANCE_ID TARGET_REDIS_INSTANCE_ID TARGET_MQ_INSTANCE_ID
)
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set in .env"
    exit 1
  fi
done

AWS="aws --profile $AWS_PROFILE --region $AWS_REGION"
S3_PATH="s3://${S3_CONFIG_BUCKET}/${S3_CONFIG_PREFIX}"
ENV_PREFIX="${NAME_PREFIX}"

echo "============================================="
echo " V3 Monitoring - Alloy Deployment"
echo "============================================="
echo "Monitor IP : $MONITOR_PRIVATE_IP"
echo "S3 Path    : $S3_PATH"
echo "Env Prefix : $ENV_PREFIX"
echo ""

# --- SSM helper ---
ssm_run() {
  local instance_id="$1" cmd="$2" timeout="${3:-120}"
  local cmd_id
  cmd_id=$($AWS ssm send-command \
    --instance-ids "$instance_id" \
    --document-name "AWS-RunShellScript" \
    --timeout-seconds "$timeout" \
    --parameters "{\"commands\":[\"set -e\",$(echo "$cmd" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")]}" \
    --output text --query 'Command.CommandId')

  local status="InProgress" waited=0
  while [[ "$status" == "InProgress" || "$status" == "Pending" ]] && (( waited < timeout )); do
    sleep 5; waited=$((waited + 5))
    status=$($AWS ssm get-command-invocation \
      --command-id "$cmd_id" --instance-id "$instance_id" \
      --query 'Status' --output text 2>/dev/null || echo "InProgress")
  done

  local result stdout stderr
  result=$($AWS ssm get-command-invocation \
    --command-id "$cmd_id" --instance-id "$instance_id" --output json 2>/dev/null || echo "{}")
  stdout=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('StandardOutputContent',''))" 2>/dev/null || true)
  stderr=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('StandardErrorContent',''))" 2>/dev/null || true)
  [[ -n "$stdout" ]] && echo "$stdout"
  [[ -n "$stderr" ]] && echo "  [stderr] $stderr"
  [[ "$status" == "Success" ]]
}

# ============================================================
# Step 1: Prepare and upload configs to S3
# ============================================================
echo "[1/4] Uploading Alloy configs to S3 ..."

TMPDIR_CONFIGS=$(mktemp -d)
trap "rm -rf '$TMPDIR_CONFIGS'" EXIT

for entry in be:config-be.alloy fe:config-fe.alloy mysql:config-mysql.alloy \
             redis:config-redis.alloy mq:config-mq.alloy monitor:config-monitor.alloy; do
  target="${entry%%:*}"
  config_file="${entry##*:}"
  src="${ALLOY_DIR}/${config_file}"

  if [[ ! -f "$src" ]]; then
    echo "  ERROR: Config not found: $src"
    exit 1
  fi

  sed -e "s/MONITOR_IP_PLACEHOLDER/${MONITOR_PRIVATE_IP}/g" \
      -e "s/ENV_PREFIX_PLACEHOLDER/${ENV_PREFIX}/g" \
      "$src" > "${TMPDIR_CONFIGS}/${target}.alloy"
  echo "  Prepared: ${target}.alloy"
done

cp "${ALLOY_DIR}/install-alloy.sh" "${TMPDIR_CONFIGS}/install-alloy.sh"
$AWS s3 sync "${TMPDIR_CONFIGS}/" "${S3_PATH}/" --quiet
echo "  Uploaded to ${S3_PATH}/"
echo ""

# ============================================================
# Step 2: BE/FE - Update Launch Template + SSM deploy
# ============================================================
echo "[2/4] Updating BE/FE Launch Templates ..."
ERRORS=0

update_launch_template() {
  local lt_id="$1" target="$2" asg_name="$3"
  echo "  --- ${target} LT (${lt_id}) ---"

  local userdata
  userdata=$(cat <<USERDATA_EOF
#!/bin/bash
set -e
TOKEN=\$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PRIVATE_IP=\$(curl -s -H "X-aws-ec2-metadata-token: \$TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
aws s3 cp s3://${S3_CONFIG_BUCKET}/${S3_CONFIG_PREFIX}/${target}.alloy /etc/alloy/config.alloy --region ${AWS_REGION}
sed -i "s/INSTANCE_LABEL/${ENV_PREFIX}-${target}-\${PRIVATE_IP}/g" /etc/alloy/config.alloy
systemctl restart alloy
USERDATA_EOF
)

  local userdata_b64 new_version
  userdata_b64=$(echo "$userdata" | base64)
  new_version=$($AWS ec2 create-launch-template-version \
    --launch-template-id "$lt_id" \
    --source-version '$Default' \
    --launch-template-data "{\"UserData\":\"${userdata_b64}\"}" \
    --query 'LaunchTemplateVersion.VersionNumber' --output text)

  $AWS ec2 modify-launch-template --launch-template-id "$lt_id" --default-version "$new_version"
  echo "  New LT version: $new_version (set as default)"
}

update_launch_template "$BE_LAUNCH_TEMPLATE_ID" "be" "$BE_ASG_NAME" || ERRORS=$((ERRORS + 1))
update_launch_template "$FE_LAUNCH_TEMPLATE_ID" "fe" "$FE_ASG_NAME" || ERRORS=$((ERRORS + 1))

# SSM deploy to running BE/FE instances
echo ""
echo "  Deploying to running BE/FE instances ..."
for target in be fe; do
  instance_ids=$($AWS ec2 describe-instances \
    --filters "Name=tag:Name,Values=*${target}*" "Name=vpc-id,Values=${VPC_ID}" "Name=instance-state-name,Values=running" \
    --query 'Reservations[*].Instances[*].InstanceId' --output text)

  [[ -z "$instance_ids" ]] && echo "  No running ${target} instances, skipping." && continue

  for iid in $instance_ids; do
    echo "  Deploying to ${target} (${iid}) ..."
    DEPLOY_CMD="TOKEN=\$(curl -s -X PUT \"http://169.254.169.254/latest/api/token\" -H \"X-aws-ec2-metadata-token-ttl-seconds: 21600\")
PRIVATE_IP=\$(curl -s -H \"X-aws-ec2-metadata-token: \$TOKEN\" http://169.254.169.254/latest/meta-data/local-ipv4)
aws s3 cp s3://${S3_CONFIG_BUCKET}/${S3_CONFIG_PREFIX}/${target}.alloy /etc/alloy/config.alloy --region ${AWS_REGION}
sed -i \"s/INSTANCE_LABEL/${ENV_PREFIX}-${target}-\${PRIVATE_IP}/g\" /etc/alloy/config.alloy
systemctl restart alloy && sleep 2
systemctl is-active alloy && echo 'Alloy OK' || echo 'Alloy FAILED'"
    ssm_run "$iid" "$DEPLOY_CMD" 60 || ERRORS=$((ERRORS + 1))
  done
done
echo ""

# ============================================================
# Step 3: MySQL/Redis/MQ
# ============================================================
echo "[3/4] Deploying to MySQL/Redis/MQ ..."

INSTALL_SCRIPT_B64=$(base64 < "${ALLOY_DIR}/install-alloy.sh")

for entry in mysql:${TARGET_MYSQL_INSTANCE_ID} redis:${TARGET_REDIS_INSTANCE_ID} mq:${TARGET_MQ_INSTANCE_ID}; do
  target="${entry%%:*}"
  instance_id="${entry##*:}"
  echo ""
  echo "  --- ${target} (${instance_id}) ---"

  # Install AWS CLI if missing
  cli_check=$(ssm_run "$instance_id" "command -v aws && echo 'EXISTS' || echo 'MISSING'" 30 2>/dev/null) || cli_check="MISSING"
  if echo "$cli_check" | grep -q "MISSING"; then
    echo "  Installing AWS CLI ..."
    ssm_run "$instance_id" "apt-get install -y -qq unzip curl
curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp/ && /tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws" 120 || { ERRORS=$((ERRORS + 1)); continue; }
  fi

  # Install Alloy if missing
  alloy_check=$(ssm_run "$instance_id" "command -v alloy && echo 'EXISTS' || echo 'MISSING'" 30 2>/dev/null) || alloy_check="MISSING"
  if echo "$alloy_check" | grep -q "MISSING"; then
    echo "  Installing Alloy ..."
    ssm_run "$instance_id" "echo '${INSTALL_SCRIPT_B64}' | base64 -d > /tmp/install-alloy.sh
chmod +x /tmp/install-alloy.sh && bash /tmp/install-alloy.sh && rm -f /tmp/install-alloy.sh" 180 || { ERRORS=$((ERRORS + 1)); continue; }
  fi

  # Deploy config
  DEPLOY_CMD="aws s3 cp s3://${S3_CONFIG_BUCKET}/${S3_CONFIG_PREFIX}/${target}.alloy /etc/alloy/config.alloy --region ${AWS_REGION}
systemctl restart alloy && sleep 2
systemctl is-active alloy && echo 'Alloy OK' || echo 'Alloy FAILED'"
  ssm_run "$instance_id" "$DEPLOY_CMD" 60 || ERRORS=$((ERRORS + 1))
done
echo ""

# ============================================================
# Step 4: Monitor Server
# ============================================================
echo "[4/4] Deploying to Monitor Server ..."

alloy_check=$(ssm_run "$MONITOR_INSTANCE_ID" "command -v alloy && echo 'EXISTS' || echo 'MISSING'" 30 2>/dev/null) || alloy_check="MISSING"
if echo "$alloy_check" | grep -q "MISSING"; then
  echo "  Installing Alloy ..."
  ssm_run "$MONITOR_INSTANCE_ID" "echo '${INSTALL_SCRIPT_B64}' | base64 -d > /tmp/install-alloy.sh
chmod +x /tmp/install-alloy.sh && bash /tmp/install-alloy.sh && rm -f /tmp/install-alloy.sh" 180 || ERRORS=$((ERRORS + 1))
fi

DEPLOY_CMD="aws s3 cp s3://${S3_CONFIG_BUCKET}/${S3_CONFIG_PREFIX}/monitor.alloy /etc/alloy/config.alloy --region ${AWS_REGION}
systemctl restart alloy && sleep 2
systemctl is-active alloy && echo 'Alloy OK' || echo 'Alloy FAILED'"
ssm_run "$MONITOR_INSTANCE_ID" "$DEPLOY_CMD" 60 || ERRORS=$((ERRORS + 1))

echo ""
echo "============================================="
echo " V3 Alloy Deployment Summary"
echo "============================================="
echo " S3 configs : ${S3_PATH}/"
echo " Failed     : $ERRORS"
echo "============================================="

if [[ $ERRORS -gt 0 ]]; then
  echo "WARNING: ${ERRORS} target(s) failed."
  exit 1
else
  echo "All targets deployed. Run 04_verify.sh to validate."
fi
