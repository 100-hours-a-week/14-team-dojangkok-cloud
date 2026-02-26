#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 03_install_alloy.sh - Deploy Alloy configs to all V2 dev targets
# =============================================================================
# 1. Uploads templated Alloy configs to S3
# 2. BE/FE: Updates Launch Template user data (new instances get Alloy on boot)
#           + SSM deploys to currently running instances
# 3. MySQL/MQ/Redis: Installs Alloy if missing, pulls config from S3 via SSM
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOY_DIR="${SCRIPT_DIR}/alloy"

source "$SCRIPT_DIR/.env"

REQUIRED_VARS=(
  AWS_PROFILE AWS_REGION MONITOR_PRIVATE_IP MONITOR_INSTANCE_ID S3_BUCKET S3_PREFIX VPC_ID
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
S3_PATH="s3://${S3_BUCKET}/${S3_PREFIX}"

echo "============================================="
echo " V2 Monitoring - Alloy Deployment"
echo "============================================="
echo "Monitor IP : $MONITOR_PRIVATE_IP"
echo "S3 Path    : $S3_PATH"
echo ""

# --- SSM helper ---
ssm_run() {
  local instance_id="$1"
  local cmd="$2"
  local timeout="${3:-120}"

  local cmd_id
  cmd_id=$($AWS ssm send-command \
    --instance-ids "$instance_id" \
    --document-name "AWS-RunShellScript" \
    --timeout-seconds "$timeout" \
    --parameters "{\"commands\":[\"set -e\",$(echo "$cmd" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")]}" \
    --output text --query 'Command.CommandId')

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

  local result
  result=$($AWS ssm get-command-invocation \
    --command-id "$cmd_id" \
    --instance-id "$instance_id" \
    --output json 2>/dev/null || echo "{}")

  local stdout
  stdout=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('StandardOutputContent',''))" 2>/dev/null || true)
  [[ -n "$stdout" ]] && echo "$stdout"

  if [[ "$status" == "Success" ]]; then
    return 0
  else
    local stderr
    stderr=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('StandardErrorContent',''))" 2>/dev/null || true)
    [[ -n "$stderr" ]] && echo "  [stderr] $stderr"
    return 1
  fi
}

# ============================================================
# Step 1: Prepare and upload configs to S3
# ============================================================
echo "[1/4] Uploading Alloy configs to S3 ..."

TMPDIR_CONFIGS=$(mktemp -d)
trap "rm -rf '$TMPDIR_CONFIGS'" EXIT

for entry in be:config-be.alloy fe:config-fe.alloy mysql:config-mysql.alloy redis:config-redis.alloy mq:config-mq.alloy monitor:config-monitor.alloy; do
  target="${entry%%:*}"
  config_file="${entry##*:}"
  src="${ALLOY_DIR}/${config_file}"

  if [[ ! -f "$src" ]]; then
    echo "  ERROR: Config not found: $src"
    exit 1
  fi

  sed "s/MONITOR_IP_PLACEHOLDER/${MONITOR_PRIVATE_IP}/g" "$src" > "${TMPDIR_CONFIGS}/${target}.alloy"
  echo "  Prepared: ${target}.alloy"
done

# Upload install script too
cp "${ALLOY_DIR}/install-alloy.sh" "${TMPDIR_CONFIGS}/install-alloy.sh"

$AWS s3 sync "${TMPDIR_CONFIGS}/" "${S3_PATH}/" --quiet
echo "  Uploaded to ${S3_PATH}/"
echo ""

# ============================================================
# Step 2: BE/FE - Update Launch Template user data + SSM deploy
# ============================================================
echo "[2/4] Updating BE/FE Launch Templates + deploying to running instances ..."

ERRORS=0

update_launch_template() {
  local lt_id="$1"
  local target="$2"
  local asg_name="$3"

  echo ""
  echo "  --- ${target} LT (${lt_id}) ---"

  # Create user data script that pulls Alloy config on boot
  local userdata
  userdata=$(cat <<USERDATA_EOF
#!/bin/bash
set -e

# Get Private IP via IMDSv2
TOKEN=\$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PRIVATE_IP=\$(curl -s -H "X-aws-ec2-metadata-token: \$TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

# Pull Alloy config from S3 and inject instance label
aws s3 cp s3://${S3_BUCKET}/${S3_PREFIX}/${target}.alloy /etc/alloy/config.alloy --region ${AWS_REGION}
sed -i "s/INSTANCE_LABEL/dev-dojangkok-v2-${target}-\${PRIVATE_IP}/g" /etc/alloy/config.alloy

# Restart Alloy
systemctl restart alloy
USERDATA_EOF
)

  # Base64 encode
  local userdata_b64
  userdata_b64=$(echo "$userdata" | base64)

  # Create new LT version with user data
  local new_version
  new_version=$($AWS ec2 create-launch-template-version \
    --launch-template-id "$lt_id" \
    --source-version '$Default' \
    --launch-template-data "{\"UserData\":\"${userdata_b64}\"}" \
    --query 'LaunchTemplateVersion.VersionNumber' --output text)

  echo "  New LT version: $new_version"

  # Set as default
  $AWS ec2 modify-launch-template \
    --launch-template-id "$lt_id" \
    --default-version "$new_version"

  echo "  Set as default version"
  echo "  ASG ($asg_name) will use new version on next instance launch"
}

if update_launch_template "$BE_LAUNCH_TEMPLATE_ID" "be" "$BE_ASG_NAME"; then
  echo "  BE LT: OK"
else
  echo "  BE LT: FAILED"
  ERRORS=$((ERRORS + 1))
fi

if update_launch_template "$FE_LAUNCH_TEMPLATE_ID" "fe" "$FE_ASG_NAME"; then
  echo "  FE LT: OK"
else
  echo "  FE LT: FAILED"
  ERRORS=$((ERRORS + 1))
fi

# Also deploy to currently running BE/FE instances via SSM
echo ""
echo "  Deploying to running BE/FE instances via SSM ..."

for target in be fe; do
  instance_ids=$($AWS ec2 describe-instances \
    --filters "Name=tag:Name,Values=dev-dojangkok-v2-${target}" "Name=vpc-id,Values=${VPC_ID}" "Name=instance-state-name,Values=running" \
    --query 'Reservations[*].Instances[*].InstanceId' --output text)

  if [[ -z "$instance_ids" ]]; then
    echo "  No running ${target} instances found, skipping SSM deploy."
    continue
  fi

  for iid in $instance_ids; do
    echo "  Deploying to ${target} (${iid}) ..."
    DEPLOY_CMD="TOKEN=\$(curl -s -X PUT \"http://169.254.169.254/latest/api/token\" -H \"X-aws-ec2-metadata-token-ttl-seconds: 21600\")
PRIVATE_IP=\$(curl -s -H \"X-aws-ec2-metadata-token: \$TOKEN\" http://169.254.169.254/latest/meta-data/local-ipv4)
aws s3 cp s3://${S3_BUCKET}/${S3_PREFIX}/${target}.alloy /etc/alloy/config.alloy --region ${AWS_REGION}
sed -i \"s/INSTANCE_LABEL/dev-dojangkok-v2-${target}-\${PRIVATE_IP}/g\" /etc/alloy/config.alloy
systemctl restart alloy
sleep 2
systemctl is-active alloy && echo 'Alloy OK' || echo 'Alloy FAILED'"

    if ssm_run "$iid" "$DEPLOY_CMD" 60; then
      echo "  ${target} (${iid}): OK"
    else
      echo "  ${target} (${iid}): FAILED"
      ERRORS=$((ERRORS + 1))
    fi
  done
done

echo ""

# ============================================================
# Step 3: MySQL/Redis/MQ - Install AWS CLI + Alloy, S3 pull
# ============================================================
echo "[3/4] Deploying to MySQL/Redis/MQ ..."

FIXED_mysql="$TARGET_MYSQL_INSTANCE_ID"
FIXED_redis="$TARGET_REDIS_INSTANCE_ID"
FIXED_mq="$TARGET_MQ_INSTANCE_ID"

# Base64-encode install script for delivery via SSM (target may lack AWS CLI)
INSTALL_SCRIPT_B64=$(base64 < "${ALLOY_DIR}/install-alloy.sh")

for target in mysql redis mq; do
  varname="FIXED_${target}"
  instance_id="${!varname}"
  echo ""
  echo "  --- ${target} (${instance_id}) ---"

  # 3-a. Install AWS CLI if missing
  cli_check=$(ssm_run "$instance_id" "command -v aws && echo 'AWS_CLI_EXISTS' || echo 'AWS_CLI_MISSING'" 30 2>/dev/null) || cli_check="AWS_CLI_MISSING"

  if echo "$cli_check" | grep -q "AWS_CLI_MISSING"; then
    echo "  AWS CLI not found, installing v2 ..."
    AWSCLI_CMD="apt-get install -y -qq unzip curl
curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp/
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws
aws --version"
    if ! ssm_run "$instance_id" "$AWSCLI_CMD" 120; then
      echo "  ${target}: AWS CLI install FAILED"
      ERRORS=$((ERRORS + 1))
      continue
    fi
    echo "  AWS CLI installed."
  else
    echo "  AWS CLI already installed."
  fi

  # 3-b. Install Alloy if missing
  alloy_check=$(ssm_run "$instance_id" "command -v alloy && echo 'ALLOY_EXISTS' || echo 'ALLOY_MISSING'" 30 2>/dev/null) || alloy_check="ALLOY_MISSING"

  if echo "$alloy_check" | grep -q "ALLOY_MISSING"; then
    echo "  Alloy not found, installing ..."

    INSTALL_CMD="echo '${INSTALL_SCRIPT_B64}' | base64 -d > /tmp/install-alloy.sh
chmod +x /tmp/install-alloy.sh
bash /tmp/install-alloy.sh
rm -f /tmp/install-alloy.sh"

    if ! ssm_run "$instance_id" "$INSTALL_CMD" 180; then
      echo "  ${target}: Alloy install FAILED"
      ERRORS=$((ERRORS + 1))
      continue
    fi
    echo "  Alloy installed."
  else
    echo "  Alloy already installed."
  fi

  # 3-c. Pull config from S3 + restart (same as BE/FE)
  DEPLOY_CMD="aws s3 cp s3://${S3_BUCKET}/${S3_PREFIX}/${target}.alloy /etc/alloy/config.alloy --region ${AWS_REGION}
systemctl restart alloy
sleep 2
systemctl is-active alloy && echo 'Alloy OK' || echo 'Alloy FAILED'"

  if ssm_run "$instance_id" "$DEPLOY_CMD" 60; then
    echo "  ${target}: OK"
  else
    echo "  ${target}: FAILED"
    ERRORS=$((ERRORS + 1))
  fi
done

# ============================================================
# Step 4: Monitor Server - Install Alloy + deploy config
# ============================================================
echo "[4/4] Deploying to Monitor Server (${MONITOR_INSTANCE_ID}) ..."
echo ""

# 4-a. Install Alloy if missing (same pattern as MySQL/Redis/MQ)
alloy_check=$(ssm_run "$MONITOR_INSTANCE_ID" "command -v alloy && echo 'ALLOY_EXISTS' || echo 'ALLOY_MISSING'" 30 2>/dev/null) || alloy_check="ALLOY_MISSING"

if echo "$alloy_check" | grep -q "ALLOY_MISSING"; then
  echo "  Alloy not found on monitor server, installing ..."

  INSTALL_CMD="echo '${INSTALL_SCRIPT_B64}' | base64 -d > /tmp/install-alloy.sh
chmod +x /tmp/install-alloy.sh
bash /tmp/install-alloy.sh
rm -f /tmp/install-alloy.sh"

  if ! ssm_run "$MONITOR_INSTANCE_ID" "$INSTALL_CMD" 180; then
    echo "  monitor: Alloy install FAILED"
    ERRORS=$((ERRORS + 1))
  else
    echo "  Alloy installed."
  fi
else
  echo "  Alloy already installed."
fi

# 4-b. Pull config from S3 + restart (monitor uses localhost, no placeholder substitution needed)
DEPLOY_CMD="aws s3 cp s3://${S3_BUCKET}/${S3_PREFIX}/monitor.alloy /etc/alloy/config.alloy --region ${AWS_REGION}
systemctl restart alloy
sleep 2
systemctl is-active alloy && echo 'Alloy OK' || echo 'Alloy FAILED'"

if ssm_run "$MONITOR_INSTANCE_ID" "$DEPLOY_CMD" 60; then
  echo "  monitor: OK"
else
  echo "  monitor: FAILED"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ============================================================
# Summary
# ============================================================
echo ""
echo "============================================="
echo " Alloy Deployment Summary"
echo "============================================="
echo " S3 configs : ${S3_PATH}/"
echo " BE LT      : ${BE_LAUNCH_TEMPLATE_ID}"
echo " FE LT      : ${FE_LAUNCH_TEMPLATE_ID}"
echo " Failed     : $ERRORS"
echo "============================================="

if [[ $ERRORS -gt 0 ]]; then
  echo "WARNING: ${ERRORS} target(s) failed."
  exit 1
else
  echo "All targets deployed. Run 04_verify.sh to validate."
fi
