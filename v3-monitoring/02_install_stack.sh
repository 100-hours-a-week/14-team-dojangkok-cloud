#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 02_install_stack.sh - Install V3 monitoring stack via SSM
# =============================================================================
# Uploads config files (with S3 bucket name substituted) and deploys
# Prometheus + Thanos Sidecar + Loki(S3) + Tempo(S3) + Grafana
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="${SCRIPT_DIR}/configs"

source "$SCRIPT_DIR/.env"

if [[ -z "${MONITOR_INSTANCE_ID:-}" ]]; then
  echo "ERROR: MONITOR_INSTANCE_ID not set. Run 01_create_monitor.sh first."
  exit 1
fi

AWS="aws --profile ${AWS_PROFILE} --region ${AWS_REGION}"

echo "============================================="
echo " V3 Monitoring Server - Stack Installation"
echo "============================================="
echo "Instance : $MONITOR_INSTANCE_ID"
echo "S3 Bucket: $S3_MONITORING_BUCKET"
echo "Env Name : $ENV_NAME"
echo ""

# --- SSM helpers (same as v2) ---
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

  local elapsed=0 status=""
  while [[ $elapsed -lt $timeout ]]; do
    sleep 5; elapsed=$((elapsed + 5))
    status=$($AWS ssm get-command-invocation \
      --command-id "$cmd_id" --instance-id "$MONITOR_INSTANCE_ID" \
      --query 'Status' --output text 2>/dev/null || echo "Pending")
    case "$status" in Success|Failed|TimedOut|Cancelled) break ;; esac
    (( elapsed % 15 == 0 )) && echo "       ... still running (${elapsed}s, status: ${status})"
  done

  local result stdout stderr
  result=$($AWS ssm get-command-invocation \
    --command-id "$cmd_id" --instance-id "$MONITOR_INSTANCE_ID" --output json 2>/dev/null || echo "{}")
  stdout=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('StandardOutputContent',''))" 2>/dev/null || true)
  stderr=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('StandardErrorContent',''))" 2>/dev/null || true)
  [[ -n "$stdout" ]] && echo "$stdout"
  [[ -n "$stderr" ]] && echo "       [stderr] $stderr"
  [[ "$status" == "Success" ]]
}

ssm_upload_file() {
  local local_path="$1" remote_path="$2"
  local content
  content=$(base64 < "$local_path")
  echo "       Uploading: $(basename "$local_path") -> $remote_path"
  ssm_run "echo '${content}' | base64 -d > ${remote_path} && echo 'Wrote ${remote_path} ($(wc -c < ${remote_path}) bytes)'" 30
}

# --- 0. SSM check ---
echo "[0/6] Verifying SSM connectivity ..."
if ! ssm_run "echo 'SSM OK - $(hostname) - $(uname -m)'" 30; then
  echo "ERROR: Cannot reach instance via SSM. Wait ~2 min after creation."
  exit 1
fi
echo ""

# --- 1. Docker check ---
echo "[1/6] Verifying Docker ..."
if ! ssm_run "docker --version && docker compose version" 30; then
  echo "ERROR: Docker not found. Expected AMI with Docker pre-installed."
  exit 1
fi
echo ""

# --- 2. Create remote dir ---
echo "[2/6] Creating /opt/monitoring directory ..."
ssm_run "mkdir -p /opt/monitoring && echo 'Directory created'" 30
echo ""

# --- 3. Prepare and upload configs ---
echo "[3/6] Preparing configs (substituting S3 bucket name + env name) ..."

TMPDIR_CONFIGS=$(mktemp -d)
trap "rm -rf '$TMPDIR_CONFIGS'" EXIT

# Copy all configs to temp dir and substitute placeholders
for cfg in docker-compose.yml prometheus.yml loki-config.yml tempo-config.yml \
           thanos-bucket.yml grafana-datasources.yml grafana-dashboards.yml alert-rules.yml; do
  src="${CONFIGS_DIR}/${cfg}"
  if [[ ! -f "$src" ]]; then
    echo "  WARNING: ${cfg} not found, skipping."
    continue
  fi
  sed -e "s/S3_BUCKET_PLACEHOLDER/${S3_MONITORING_BUCKET}/g" \
      -e "s/ENV_NAME_PLACEHOLDER/${ENV_NAME}/g" \
      "$src" > "${TMPDIR_CONFIGS}/${cfg}"
done

echo "  Placeholders substituted:"
echo "    S3_BUCKET_PLACEHOLDER -> ${S3_MONITORING_BUCKET}"
echo "    ENV_NAME_PLACEHOLDER  -> ${ENV_NAME}"
echo ""

echo "[4/6] Uploading config files ..."

UPLOAD_ERRORS=0
for cfg in docker-compose.yml prometheus.yml loki-config.yml tempo-config.yml \
           thanos-bucket.yml grafana-datasources.yml grafana-dashboards.yml alert-rules.yml; do
  local_file="${TMPDIR_CONFIGS}/${cfg}"
  if [[ ! -f "$local_file" ]]; then
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
echo "       All config files uploaded."
echo ""

# --- 4. Upload dashboards ---
echo "[5/6] Uploading dashboards ..."
ssm_run "mkdir -p /opt/monitoring/dashboards" 30

DASHBOARD_DIR="${CONFIGS_DIR}/dashboards"
if [[ -d "$DASHBOARD_DIR" ]]; then
  for dashboard in "$DASHBOARD_DIR"/*.json; do
    [[ ! -f "$dashboard" ]] && continue
    ssm_upload_file "$dashboard" "/opt/monitoring/dashboards/$(basename "$dashboard")"
  done
  echo "       Dashboards uploaded."
else
  echo "       No dashboards directory found, skipping."
fi
echo ""

# --- 5. Create .env + docker compose up ---
echo "[6/6] Creating .env and starting stack ..."

ssm_run "cat > /opt/monitoring/.env << 'ENVEOF'
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
ENVEOF
chmod 600 /opt/monitoring/.env && echo '.env created'" 30

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

# --- 6. Verify ---
echo ""
echo "Verifying deployment (waiting 20 seconds) ..."
sleep 20

VERIFY_CMD=$(cat <<'SCRIPT'
echo "=== Container Status ==="
docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || docker ps

RUNNING=$(docker ps --format '{{.Names}}' | wc -l)
echo ""
echo "Running containers: ${RUNNING}"
echo ""
echo "=== Health Checks ==="

curl -sf localhost:9090/-/ready > /dev/null 2>&1 && echo "  Prometheus (9090)     : OK" || echo "  Prometheus (9090)     : NOT READY"
curl -sf localhost:3100/ready > /dev/null 2>&1 && echo "  Loki       (3100)     : OK" || echo "  Loki       (3100)     : NOT READY"
curl -sf localhost:3200/ready > /dev/null 2>&1 && echo "  Tempo      (3200)     : OK" || echo "  Tempo      (3200)     : NOT READY"
curl -sf localhost:3000/api/health > /dev/null 2>&1 && echo "  Grafana    (3000)     : OK" || echo "  Grafana    (3000)     : NOT READY"
curl -sf localhost:10902/-/healthy > /dev/null 2>&1 && echo "  Thanos Sidecar (10902): OK" || echo "  Thanos Sidecar (10902): NOT READY"

[[ $RUNNING -ge 5 ]] && echo "" && echo "All 5 containers running." && exit 0
echo "" && echo "WARNING: Expected 5 containers, found ${RUNNING}." && exit 1
SCRIPT
)

if ssm_run "$VERIFY_CMD" 60; then
  echo ""
  echo "============================================="
  echo " V3 Monitoring Stack - Installation Complete"
  echo "============================================="
  echo " Instance   : $MONITOR_INSTANCE_ID"
  echo " Public IP  : ${MONITOR_PUBLIC_IP:-unknown}"
  echo ""
  echo " Endpoints:"
  echo "   Grafana        : http://${MONITOR_PUBLIC_IP:-<IP>}:3000"
  echo "   Prometheus     : http://${MONITOR_PUBLIC_IP:-<IP>}:9090"
  echo "   Loki (push)    : http://${MONITOR_PUBLIC_IP:-<IP>}:3100"
  echo "   Tempo gRPC     : ${MONITOR_PUBLIC_IP:-<IP>}:4317"
  echo "   Thanos Sidecar : http://${MONITOR_PUBLIC_IP:-<IP>}:10902"
  echo ""
  echo " S3 Storage:"
  echo "   Bucket: ${S3_MONITORING_BUCKET}"
  echo "   Loki   -> s3://${S3_MONITORING_BUCKET}/loki/"
  echo "   Tempo  -> s3://${S3_MONITORING_BUCKET}/tempo/"
  echo "   Thanos -> s3://${S3_MONITORING_BUCKET}/prometheus/"
  echo "============================================="
  echo ""
  echo "Next: Run 03_install_alloy.sh"
else
  echo "WARNING: Verification found issues. Check logs:"
  echo "  $AWS ssm start-session --target $MONITOR_INSTANCE_ID"
  echo "  cd /opt/monitoring && docker compose logs"
fi
