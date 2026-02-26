#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 02_install_stack.sh - Install monitoring stack on V2 monitor server via SSM
# =============================================================================
# Installs Docker, uploads config files, and deploys the monitoring stack
# (Prometheus, Loki, Tempo, Grafana) using docker compose.
#
# Prerequisites:
#   - 01_create_monitor.sh has been run (MONITOR_INSTANCE_ID in .env)
#   - SSM agent is registered (~2 min after instance launch)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="${SCRIPT_DIR}/configs"

# ---------------------------------------------------------------------------
# 1. Source .env
# ---------------------------------------------------------------------------
if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
  echo "ERROR: $SCRIPT_DIR/.env not found. Copy env.example to .env and fill in values."
  exit 1
fi

# shellcheck source=/dev/null
source "$SCRIPT_DIR/.env"

# ---------------------------------------------------------------------------
# 2. Validate required variables
# ---------------------------------------------------------------------------
if [[ -z "${MONITOR_INSTANCE_ID:-}" ]]; then
  echo "ERROR: MONITOR_INSTANCE_ID is not set in .env."
  echo "       Run 01_create_monitor.sh first."
  exit 1
fi

if [[ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
  echo "ERROR: GRAFANA_ADMIN_PASSWORD is not set in .env."
  exit 1
fi

# ---------------------------------------------------------------------------
# 3. AWS CLI shorthand
# ---------------------------------------------------------------------------
AWS="aws --profile ${AWS_PROFILE} --region ${AWS_REGION}"

echo "============================================="
echo " V2 Monitoring Server - Stack Installation"
echo "============================================="
echo "Instance : $MONITOR_INSTANCE_ID"
echo "Profile  : $AWS_PROFILE"
echo "Region   : $AWS_REGION"
echo ""

# ---------------------------------------------------------------------------
# 4. SSM helper functions
# ---------------------------------------------------------------------------

# ssm_run: Execute a command on the remote instance via SSM.
#   - Sends the command via send-command
#   - Polls for completion with a configurable timeout (default 120s)
#   - Prints stdout/stderr
#   - Returns 0 on Success, 1 otherwise
ssm_run() {
  local cmd="$1"
  local timeout="${2:-120}"
  local cmd_id

  cmd_id=$($AWS ssm send-command \
    --instance-ids "$MONITOR_INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --timeout-seconds 300 \
    --parameters "{\"commands\":[\"set -e\",$(echo "$cmd" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")]}" \
    --output text --query 'Command.CommandId')

  if [[ -z "$cmd_id" ]]; then
    echo "ERROR: Failed to send SSM command."
    return 1
  fi

  # Poll for completion
  local elapsed=0
  local status=""
  while [[ $elapsed -lt $timeout ]]; do
    sleep 5
    elapsed=$((elapsed + 5))

    status=$($AWS ssm get-command-invocation \
      --command-id "$cmd_id" \
      --instance-id "$MONITOR_INSTANCE_ID" \
      --query 'Status' \
      --output text 2>/dev/null || echo "Pending")

    case "$status" in
      Success|Failed|TimedOut|Cancelled)
        break
        ;;
      *)
        # InProgress, Pending, Delayed - keep waiting
        if (( elapsed % 15 == 0 )); then
          echo "       ... still running (${elapsed}s elapsed, status: ${status})"
        fi
        ;;
    esac
  done

  # Retrieve output
  local result
  result=$($AWS ssm get-command-invocation \
    --command-id "$cmd_id" \
    --instance-id "$MONITOR_INSTANCE_ID" \
    --output json 2>/dev/null || echo "{}")

  local stdout stderr
  stdout=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('StandardOutputContent',''))" 2>/dev/null || true)
  stderr=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('StandardErrorContent',''))" 2>/dev/null || true)

  if [[ -n "$stdout" ]]; then
    echo "$stdout"
  fi
  if [[ -n "$stderr" ]]; then
    echo "       [stderr] $stderr"
  fi

  if [[ "$status" == "Success" ]]; then
    return 0
  else
    echo "ERROR: SSM command finished with status: $status (timeout=${timeout}s, elapsed=${elapsed}s)"
    return 1
  fi
}

# ssm_upload_file: Upload a local file to the remote instance via SSM.
#   Uses base64 encoding to safely transfer file contents.
ssm_upload_file() {
  local local_path="$1"
  local remote_path="$2"
  local filename
  filename=$(basename "$local_path")

  local content
  content=$(base64 < "$local_path")

  echo "       Uploading: $filename -> $remote_path"

  # Split base64 content into chunks if necessary (SSM parameter limit ~24KB).
  # For config files this should be well under the limit.
  ssm_run "echo '${content}' | base64 -d > ${remote_path} && echo 'Wrote ${remote_path} ($(wc -c < ${remote_path}) bytes)'" 30
}

# ---------------------------------------------------------------------------
# 5. Verify SSM connectivity
# ---------------------------------------------------------------------------
echo "[0/5] Verifying SSM connectivity ..."

if ! ssm_run "echo 'SSM connection OK - $(hostname) - $(uname -m)'" 30; then
  echo ""
  echo "ERROR: Cannot reach instance via SSM."
  echo "       Wait ~2 minutes after instance creation for SSM agent to register."
  echo "       Verify the instance has the AmazonSSMManagedInstanceCore policy."
  exit 1
fi

echo "       SSM connectivity verified."
echo ""

# ---------------------------------------------------------------------------
# 6. Step 1: Install Docker
# ---------------------------------------------------------------------------
echo "[1/5] Verifying Docker ..."

if ! ssm_run "docker --version && docker compose version" 30; then
  echo "ERROR: Docker not found on the instance."
  echo "       Expected AMI with Docker pre-installed."
  exit 1
fi

echo "       Docker verified."
echo ""

# ---------------------------------------------------------------------------
# 7. Step 2: Create remote directory
# ---------------------------------------------------------------------------
echo "[2/5] Creating /opt/monitoring directory ..."

if ! ssm_run "mkdir -p /opt/monitoring && echo 'Directory created: /opt/monitoring'" 30; then
  echo "ERROR: Failed to create /opt/monitoring."
  exit 1
fi

echo ""

# ---------------------------------------------------------------------------
# 8. Step 3: Upload config files
# ---------------------------------------------------------------------------
echo "[3/5] Uploading config files ..."

CONFIG_FILES=(
  "docker-compose.yml"
  "prometheus.yml"
  "loki-config.yml"
  "tempo-config.yml"
  "grafana-datasources.yml"
  "grafana-dashboards.yml"
)

UPLOAD_ERRORS=0
for cfg in "${CONFIG_FILES[@]}"; do
  local_file="${CONFIGS_DIR}/${cfg}"
  if [[ ! -f "$local_file" ]]; then
    echo "       WARNING: ${cfg} not found in configs/, skipping."
    UPLOAD_ERRORS=$((UPLOAD_ERRORS + 1))
    continue
  fi
  if ! ssm_upload_file "$local_file" "/opt/monitoring/${cfg}"; then
    echo "       ERROR: Failed to upload ${cfg}"
    UPLOAD_ERRORS=$((UPLOAD_ERRORS + 1))
  fi
done

if [[ $UPLOAD_ERRORS -gt 0 ]]; then
  echo "ERROR: ${UPLOAD_ERRORS} config file(s) failed to upload."
  exit 1
fi

echo "       All ${#CONFIG_FILES[@]} config files uploaded."

# Also sync configs to S3 for reference
if [[ -n "${S3_BUCKET:-}" ]]; then
  echo "       Syncing configs to S3 ..."
  $AWS s3 sync "$CONFIGS_DIR/" "s3://${S3_BUCKET}/${S3_PREFIX}/monitor/" --quiet
fi

echo ""

# ---------------------------------------------------------------------------
# 9. Step 4: Create .env on server for docker compose
# ---------------------------------------------------------------------------
echo "[4/5] Creating .env on server (GRAFANA_ADMIN_PASSWORD) ..."

# Escape special characters in password for safe shell injection
ESCAPED_PASSWORD=$(printf '%s' "$GRAFANA_ADMIN_PASSWORD" | sed "s/'/'\\\\''/g")

if ! ssm_run "cat > /opt/monitoring/.env << 'ENVEOF'
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
ENVEOF
chmod 600 /opt/monitoring/.env && echo '.env created (mode 600)'" 30; then
  echo "ERROR: Failed to create .env on server."
  exit 1
fi

echo ""

# ---------------------------------------------------------------------------
# 10. Step 5: docker compose up
# ---------------------------------------------------------------------------
echo "[5/5] Starting monitoring stack with docker compose ..."

COMPOSE_CMD=$(cat <<'SCRIPT'
cd /opt/monitoring

echo "Pulling images ..."
docker compose pull

echo "Starting containers ..."
docker compose up -d

echo "Containers started."
SCRIPT
)

if ! ssm_run "$COMPOSE_CMD" 300; then
  echo "ERROR: docker compose up failed."
  exit 1
fi

echo ""

# ---------------------------------------------------------------------------
# 11. Verify deployment
# ---------------------------------------------------------------------------
echo "Verifying deployment (waiting 15 seconds for containers to stabilize) ..."
sleep 15

VERIFY_CMD=$(cat <<'SCRIPT'
echo "=== Container Status ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || \
  docker ps

RUNNING=$(docker ps --format '{{.Names}}' | wc -l)
echo ""
echo "Running containers: ${RUNNING}"

echo ""
echo "=== Health Checks ==="

# Prometheus
if curl -sf http://localhost:9090/-/ready > /dev/null 2>&1; then
  echo "  Prometheus (9090)  : OK"
else
  echo "  Prometheus (9090)  : NOT READY"
fi

# Loki
if curl -sf http://localhost:3100/ready > /dev/null 2>&1; then
  echo "  Loki       (3100)  : OK"
else
  echo "  Loki       (3100)  : NOT READY"
fi

# Tempo
if curl -sf http://localhost:3200/ready > /dev/null 2>&1; then
  echo "  Tempo      (3200)  : OK"
else
  echo "  Tempo      (3200)  : NOT READY"
fi

# Grafana
if curl -sf http://localhost:3000/api/health > /dev/null 2>&1; then
  echo "  Grafana    (3000)  : OK"
else
  echo "  Grafana    (3000)  : NOT READY"
fi

if [[ $RUNNING -ge 4 ]]; then
  echo ""
  echo "All 4 containers are running."
  exit 0
else
  echo ""
  echo "WARNING: Expected 4 containers, found ${RUNNING}."
  echo "Check logs: cd /opt/monitoring && docker compose logs"
  exit 1
fi
SCRIPT
)

if ssm_run "$VERIFY_CMD" 60; then
  echo ""
  echo "============================================="
  echo " V2 Monitoring Stack - Installation Complete"
  echo "============================================="
  echo " Instance   : $MONITOR_INSTANCE_ID"
  echo " Public IP  : ${MONITOR_PUBLIC_IP:-unknown}"
  echo ""
  echo " Endpoints:"
  echo "   Grafana      : http://${MONITOR_PUBLIC_IP:-<IP>}:3000"
  echo "   Prometheus   : http://${MONITOR_PUBLIC_IP:-<IP>}:9090"
  echo "   Loki (push)  : http://${MONITOR_PUBLIC_IP:-<IP>}:3100"
  echo "   Tempo gRPC   : ${MONITOR_PUBLIC_IP:-<IP>}:4317"
  echo "   Tempo HTTP   : http://${MONITOR_PUBLIC_IP:-<IP>}:4318"
  echo "============================================="
  echo ""
  echo "Next steps:"
  echo "  1. Access Grafana at http://${MONITOR_PUBLIC_IP:-<IP>}:3000"
  echo "     Username: admin / Password: (from .env GRAFANA_ADMIN_PASSWORD)"
  echo "  2. Configure Alloy/agents to push to this server"
  echo "  3. Run 03_install_exporters.sh to set up node exporters on targets"
else
  echo ""
  echo "WARNING: Verification found issues. Check container logs via SSM:"
  echo "  $AWS ssm start-session --target $MONITOR_INSTANCE_ID"
  echo "  cd /opt/monitoring && docker compose logs"
fi
