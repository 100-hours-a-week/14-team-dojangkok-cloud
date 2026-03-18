#!/usr/bin/env bash
set -eo pipefail

# =============================================================================
# 04_verify.sh - Verify V3 monitoring stack, S3 storage, and Alloy agents
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

REQUIRED_VARS=(
  AWS_PROFILE AWS_REGION MONITOR_INSTANCE_ID VPC_ID S3_MONITORING_BUCKET
  TARGET_MYSQL_INSTANCE_ID TARGET_REDIS_INSTANCE_ID TARGET_MQ_INSTANCE_ID
)
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set in .env"
    exit 1
  fi
done

AWS="aws --profile $AWS_PROFILE --region $AWS_REGION"

RED='\033[0;31m'; GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'
PASS_COUNT=0; FAIL_COUNT=0; SUMMARY=""

pass()   { echo -e "  ${GREEN}[PASS]${NC} $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail()   { echo -e "  ${RED}[FAIL]${NC} $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
record() { SUMMARY="${SUMMARY}${1}|${2}|${3}\n"; }

echo "============================================="
echo " V3 Monitoring - Verification"
echo "============================================="
echo "Monitor  : $MONITOR_INSTANCE_ID"
echo "S3 Bucket: $S3_MONITORING_BUCKET"
echo ""

# --- SSM helper ---
ssm_check() {
  local instance_id="$1" cmd="$2" timeout="${3:-30}"
  local cmd_id
  cmd_id=$($AWS ssm send-command \
    --instance-ids "$instance_id" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":[\"set -e\",$(echo "$cmd" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")]}" \
    --timeout-seconds "$timeout" \
    --output text --query 'Command.CommandId' 2>/dev/null) || return 1

  local status="InProgress" waited=0
  while [[ "$status" == "InProgress" || "$status" == "Pending" ]] && (( waited < timeout )); do
    sleep 3; waited=$((waited + 3))
    status=$($AWS ssm get-command-invocation \
      --command-id "$cmd_id" --instance-id "$instance_id" \
      --query 'Status' --output text 2>/dev/null || echo "InProgress")
  done

  if [[ "$status" == "Success" ]]; then
    $AWS ssm get-command-invocation \
      --command-id "$cmd_id" --instance-id "$instance_id" \
      --query 'StandardOutputContent' --output text 2>/dev/null
    return 0
  fi
  return 1
}

# =============================================================
# Monitor Server Checks
# =============================================================
echo -e "${BOLD}[Monitor Server] ${MONITOR_INSTANCE_ID}${NC}"
echo ""

# Docker containers (expect 5: prometheus, thanos-sidecar, loki, tempo, grafana)
docker_output=$(ssm_check "$MONITOR_INSTANCE_ID" "docker ps --format '{{.Names}}' | wc -l" 30) || docker_output="0"
docker_count=$(echo "$docker_output" | tr -d '[:space:]')
if [[ "$docker_count" -ge 5 ]]; then
  pass "Docker: ${docker_count} containers running (expected >= 5)"
  record "monitor" "Docker (>= 5)" "PASS"
else
  fail "Docker: ${docker_count} containers running (expected >= 5)"
  record "monitor" "Docker (>= 5)" "FAIL"
fi

# Prometheus
if ssm_check "$MONITOR_INSTANCE_ID" "curl -sf localhost:9090/-/ready" 30 >/dev/null 2>&1; then
  pass "Prometheus (9090): ready"
  record "monitor" "Prometheus" "PASS"
else
  fail "Prometheus (9090): not ready"
  record "monitor" "Prometheus" "FAIL"
fi

# Thanos Sidecar
if ssm_check "$MONITOR_INSTANCE_ID" "curl -sf localhost:10902/-/healthy" 30 >/dev/null 2>&1; then
  pass "Thanos Sidecar (10902): healthy"
  record "monitor" "Thanos Sidecar" "PASS"
else
  fail "Thanos Sidecar (10902): not healthy"
  record "monitor" "Thanos Sidecar" "FAIL"
fi

# Loki
if ssm_check "$MONITOR_INSTANCE_ID" "curl -sf localhost:3100/ready" 30 >/dev/null 2>&1; then
  pass "Loki (3100): ready"
  record "monitor" "Loki" "PASS"
else
  fail "Loki (3100): not ready"
  record "monitor" "Loki" "FAIL"
fi

# Tempo
if ssm_check "$MONITOR_INSTANCE_ID" "curl -sf localhost:3200/ready" 30 >/dev/null 2>&1; then
  pass "Tempo (3200): ready"
  record "monitor" "Tempo" "PASS"
else
  fail "Tempo (3200): not ready"
  record "monitor" "Tempo" "FAIL"
fi

# Grafana
if ssm_check "$MONITOR_INSTANCE_ID" "curl -sf localhost:3000/api/health" 30 >/dev/null 2>&1; then
  pass "Grafana (3000): healthy"
  record "monitor" "Grafana" "PASS"
else
  fail "Grafana (3000): not healthy"
  record "monitor" "Grafana" "FAIL"
fi
echo ""

# =============================================================
# S3 Storage Checks
# =============================================================
echo -e "${BOLD}[S3 Storage] ${S3_MONITORING_BUCKET}${NC}"
echo ""

# Check bucket exists
if $AWS s3api head-bucket --bucket "$S3_MONITORING_BUCKET" 2>/dev/null; then
  pass "S3 bucket exists: ${S3_MONITORING_BUCKET}"
  record "s3" "Bucket exists" "PASS"
else
  fail "S3 bucket not found: ${S3_MONITORING_BUCKET}"
  record "s3" "Bucket exists" "FAIL"
fi

# Check Loki objects
loki_count=$($AWS s3 ls "s3://${S3_MONITORING_BUCKET}/loki/" --recursive 2>/dev/null | wc -l || echo "0")
loki_count=$(echo "$loki_count" | tr -d '[:space:]')
if [[ "$loki_count" -gt 0 ]]; then
  pass "Loki S3: ${loki_count} objects in loki/"
  record "s3" "Loki objects" "PASS"
else
  fail "Loki S3: no objects in loki/ (logs may take a few minutes to flush)"
  record "s3" "Loki objects" "FAIL"
fi

# Check Tempo objects
tempo_count=$($AWS s3 ls "s3://${S3_MONITORING_BUCKET}/tempo/" --recursive 2>/dev/null | wc -l || echo "0")
tempo_count=$(echo "$tempo_count" | tr -d '[:space:]')
if [[ "$tempo_count" -gt 0 ]]; then
  pass "Tempo S3: ${tempo_count} objects in tempo/"
  record "s3" "Tempo objects" "PASS"
else
  fail "Tempo S3: no objects in tempo/ (traces may take 5 minutes to flush)"
  record "s3" "Tempo objects" "FAIL"
fi

# Check Thanos/Prometheus objects (takes 2 hours after start)
prom_count=$($AWS s3 ls "s3://${S3_MONITORING_BUCKET}/prometheus/" --recursive 2>/dev/null | wc -l || echo "0")
prom_count=$(echo "$prom_count" | tr -d '[:space:]')
if [[ "$prom_count" -gt 0 ]]; then
  pass "Thanos S3: ${prom_count} objects in prometheus/"
  record "s3" "Thanos objects" "PASS"
else
  echo -e "  ${RED}[WAIT]${NC} Thanos S3: no objects yet (first upload after 2 hours)"
  record "s3" "Thanos objects" "WAIT"
fi
echo ""

# =============================================================
# Alloy Agent Checks
# =============================================================
echo -e "${BOLD}[Alloy Agents]${NC}"
echo ""

# Discover BE/FE instances
BE_INSTANCE_ID=$($AWS ec2 describe-instances \
  --filters "Name=tag:Name,Values=*be*" "Name=vpc-id,Values=${VPC_ID}" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null) || BE_INSTANCE_ID="None"
FE_INSTANCE_ID=$($AWS ec2 describe-instances \
  --filters "Name=tag:Name,Values=*fe*" "Name=vpc-id,Values=${VPC_ID}" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null) || FE_INSTANCE_ID="None"

declare -A TARGETS=(
  [be]="$BE_INSTANCE_ID"
  [fe]="$FE_INSTANCE_ID"
  [mysql]="$TARGET_MYSQL_INSTANCE_ID"
  [redis]="$TARGET_REDIS_INSTANCE_ID"
  [mq]="$TARGET_MQ_INSTANCE_ID"
  [monitor]="$MONITOR_INSTANCE_ID"
)

for target in be fe mysql redis mq monitor; do
  instance_id="${TARGETS[$target]}"
  echo -e "  ${BOLD}${target}${NC} (${instance_id})"

  if [[ "$instance_id" == "None" || -z "$instance_id" ]]; then
    fail "${target}: instance not found"
    record "$target" "Alloy" "FAIL"
    continue
  fi

  alloy_status=$(ssm_check "$instance_id" "systemctl is-active alloy" 30 2>/dev/null) || alloy_status="unknown"
  alloy_status=$(echo "$alloy_status" | tr -d '[:space:]')
  if [[ "$alloy_status" == "active" ]]; then
    pass "${target}: Alloy active"
    record "$target" "Alloy" "PASS"
  else
    fail "${target}: Alloy ${alloy_status}"
    record "$target" "Alloy" "FAIL"
  fi
done
echo ""

# =============================================================
# Summary
# =============================================================
echo -e "${BOLD}=============================================${NC}"
echo -e "${BOLD} Verification Summary${NC}"
echo -e "${BOLD}=============================================${NC}"
echo ""

printf "  ${BOLD}%-12s %-25s %s${NC}\n" "Component" "Check" "Result"
echo "  ----------------------------------------------------------"

echo -e "$SUMMARY" | while IFS='|' read -r comp check result; do
  [[ -z "$comp" ]] && continue
  if [[ "$result" == "PASS" ]]; then
    printf "  %-12s %-25s ${GREEN}%s${NC}\n" "$comp" "$check" "$result"
  elif [[ "$result" == "WAIT" ]]; then
    printf "  %-12s %-25s %s\n" "$comp" "$check" "$result"
  else
    printf "  %-12s %-25s ${RED}%s${NC}\n" "$comp" "$check" "$result"
  fi
done

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo ""
echo -e "  Total: ${BOLD}${TOTAL}${NC} checks  |  ${GREEN}${PASS_COUNT} passed${NC}  |  ${RED}${FAIL_COUNT} failed${NC}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}All checks passed. V3 monitoring is operational.${NC}"
else
  echo -e "  ${RED}${BOLD}${FAIL_COUNT} check(s) failed. Review output above.${NC}"
fi
echo ""
exit $FAIL_COUNT
