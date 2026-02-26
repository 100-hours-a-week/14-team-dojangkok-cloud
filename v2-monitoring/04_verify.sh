#!/usr/bin/env bash
set -eo pipefail

# =============================================================================
# 04_verify.sh - Verify V2 monitoring stack and Alloy agents
# =============================================================================
# Checks:
#   Monitor server  : docker ps, Prometheus, Loki, Tempo, Grafana
#   Target instances: Alloy systemd status, Alloy /ready endpoint
#
# Prerequisites:
#   - 02_install_stack.sh completed (monitoring stack running)
#   - 03_install_alloy.sh completed (Alloy on all targets)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
REQUIRED_VARS=(
  AWS_PROFILE AWS_REGION MONITOR_INSTANCE_ID VPC_ID
  TARGET_MYSQL_INSTANCE_ID TARGET_REDIS_INSTANCE_ID TARGET_MQ_INSTANCE_ID
)
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Required variable $var is not set in .env"
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# 3. AWS CLI shorthand
# ---------------------------------------------------------------------------
AWS="aws --profile $AWS_PROFILE --region $AWS_REGION"

# ---------------------------------------------------------------------------
# 4. Color helpers + counters
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
SUMMARY=""

pass() {
  echo -e "  ${GREEN}[PASS]${NC} $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}
fail() {
  echo -e "  ${RED}[FAIL]${NC} $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}
record() {
  local component="$1" check="$2" result="$3"
  SUMMARY="${SUMMARY}${component}|${check}|${result}\n"
}

echo "============================================="
echo " V2 Monitoring - Verification"
echo "============================================="
echo "Monitor  : $MONITOR_INSTANCE_ID"
echo "Profile  : $AWS_PROFILE"
echo "Region   : $AWS_REGION"
echo ""

# ---------------------------------------------------------------------------
# 5. SSM helper
# ---------------------------------------------------------------------------
ssm_check() {
  local instance_id="$1"
  local cmd="$2"
  local timeout="${3:-30}"

  local cmd_id
  cmd_id=$($AWS ssm send-command \
    --instance-ids "$instance_id" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":[\"set -e\",$(echo "$cmd" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")]}" \
    --timeout-seconds "$timeout" \
    --output text --query 'Command.CommandId' 2>/dev/null) || return 1

  local status="InProgress"
  local waited=0
  while [[ "$status" == "InProgress" || "$status" == "Pending" ]] && (( waited < timeout )); do
    sleep 3
    waited=$((waited + 3))
    status=$($AWS ssm get-command-invocation \
      --command-id "$cmd_id" \
      --instance-id "$instance_id" \
      --query 'Status' --output text 2>/dev/null || echo "InProgress")
  done

  if [[ "$status" == "Success" ]]; then
    $AWS ssm get-command-invocation \
      --command-id "$cmd_id" \
      --instance-id "$instance_id" \
      --query 'StandardOutputContent' --output text 2>/dev/null
    return 0
  else
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 6. Monitor Server Checks
# ---------------------------------------------------------------------------
echo -e "${BOLD}[Monitor Server] ${MONITOR_INSTANCE_ID}${NC}"
echo ""

# Check 1: docker ps
echo "  Checking Docker containers ..."
docker_output=$(ssm_check "$MONITOR_INSTANCE_ID" "docker ps --format '{{.Names}}' | wc -l" 30) || docker_output="0"
docker_count=$(echo "$docker_output" | tr -d '[:space:]')
if [[ "$docker_count" -ge 4 ]]; then
  pass "Docker: ${docker_count} containers running (expected >= 4)"
  record "monitor" "Docker (>= 4)" "PASS"
else
  fail "Docker: ${docker_count} containers running (expected >= 4)"
  record "monitor" "Docker (>= 4)" "FAIL"
fi

# Check 2: Prometheus
echo "  Checking Prometheus ..."
if ssm_check "$MONITOR_INSTANCE_ID" "curl -sf localhost:9090/-/ready" 30 >/dev/null 2>&1; then
  pass "Prometheus (9090): ready"
  record "monitor" "Prometheus (9090)" "PASS"
else
  fail "Prometheus (9090): not ready"
  record "monitor" "Prometheus (9090)" "FAIL"
fi

# Check 3: Loki
echo "  Checking Loki ..."
if ssm_check "$MONITOR_INSTANCE_ID" "curl -sf localhost:3100/ready" 30 >/dev/null 2>&1; then
  pass "Loki (3100): ready"
  record "monitor" "Loki (3100)" "PASS"
else
  fail "Loki (3100): not ready"
  record "monitor" "Loki (3100)" "FAIL"
fi

# Check 4: Tempo
echo "  Checking Tempo ..."
if ssm_check "$MONITOR_INSTANCE_ID" "curl -sf localhost:3200/ready" 30 >/dev/null 2>&1; then
  pass "Tempo (3200): ready"
  record "monitor" "Tempo (3200)" "PASS"
else
  fail "Tempo (3200): not ready"
  record "monitor" "Tempo (3200)" "FAIL"
fi

# Check 5: Grafana
echo "  Checking Grafana ..."
if ssm_check "$MONITOR_INSTANCE_ID" "curl -sf localhost:3000/api/health" 30 >/dev/null 2>&1; then
  pass "Grafana (3000): healthy"
  record "monitor" "Grafana (3000)" "PASS"
else
  fail "Grafana (3000): not healthy"
  record "monitor" "Grafana (3000)" "FAIL"
fi

echo ""

# ---------------------------------------------------------------------------
# 7. Target Instance Checks
# ---------------------------------------------------------------------------
echo "  Discovering BE/FE instances by tag ..."
BE_INSTANCE_ID=$($AWS ec2 describe-instances \
  --filters "Name=tag:Name,Values=dev-dojangkok-v2-be" "Name=vpc-id,Values=${VPC_ID}" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null) || BE_INSTANCE_ID="None"

FE_INSTANCE_ID=$($AWS ec2 describe-instances \
  --filters "Name=tag:Name,Values=dev-dojangkok-v2-fe" "Name=vpc-id,Values=${VPC_ID}" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null) || FE_INSTANCE_ID="None"

TARGET_be="$BE_INSTANCE_ID"
TARGET_fe="$FE_INSTANCE_ID"
TARGET_mysql="$TARGET_MYSQL_INSTANCE_ID"
TARGET_redis="$TARGET_REDIS_INSTANCE_ID"
TARGET_mq="$TARGET_MQ_INSTANCE_ID"
TARGET_monitor="$MONITOR_INSTANCE_ID"

for target in be fe mysql redis mq monitor; do
  varname="TARGET_${target}"
  instance_id="${!varname}"
  echo -e "${BOLD}[${target}] ${instance_id}${NC}"

  if [[ "$instance_id" == "None" || -z "$instance_id" ]]; then
    fail "${target}: instance not found"
    record "$target" "Alloy service" "FAIL"
    record "$target" "Alloy ready (12345)" "FAIL"
    echo ""
    continue
  fi

  # Check 1: systemctl is-active alloy
  echo "  Checking Alloy service ..."
  alloy_status=$(ssm_check "$instance_id" "systemctl is-active alloy" 30 2>/dev/null) || alloy_status="unknown"
  alloy_status=$(echo "$alloy_status" | tr -d '[:space:]')
  if [[ "$alloy_status" == "active" ]]; then
    pass "Alloy systemd: active"
    record "$target" "Alloy service" "PASS"
  else
    fail "Alloy systemd: ${alloy_status} (expected active)"
    record "$target" "Alloy service" "FAIL"
  fi

  # Check 2: curl localhost:12345/ready
  echo "  Checking Alloy readiness ..."
  if ssm_check "$instance_id" "curl -sf localhost:12345/ready" 30 >/dev/null 2>&1; then
    pass "Alloy ready (12345): OK"
    record "$target" "Alloy ready (12345)" "PASS"
  else
    fail "Alloy ready (12345): not ready"
    record "$target" "Alloy ready (12345)" "FAIL"
  fi

  echo ""
done

# ---------------------------------------------------------------------------
# 8. Summary Table
# ---------------------------------------------------------------------------
echo -e "${BOLD}=============================================${NC}"
echo -e "${BOLD} Verification Summary${NC}"
echo -e "${BOLD}=============================================${NC}"
echo ""

fmt_result() {
  if [[ "$1" == "PASS" ]]; then
    echo -e "${GREEN}PASS${NC}"
  else
    echo -e "${RED}FAIL${NC}"
  fi
}

printf "  ${BOLD}%-12s %-25s %s${NC}\n" "Component" "Check" "Result"
echo "  ----------------------------------------------------------"

echo -e "$SUMMARY" | while IFS='|' read -r comp check result; do
  [[ -z "$comp" ]] && continue
  printf "  %-12s %-25s %b\n" "$comp" "$check" "$(fmt_result "$result")"
done

TOTAL_CHECKS=$((PASS_COUNT + FAIL_COUNT))
echo ""
echo -e "  Total: ${BOLD}${TOTAL_CHECKS}${NC} checks  |  ${GREEN}${PASS_COUNT} passed${NC}  |  ${RED}${FAIL_COUNT} failed${NC}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}All checks passed. Monitoring stack is fully operational.${NC}"
else
  echo -e "  ${RED}${BOLD}${FAIL_COUNT} check(s) failed. Review output above for details.${NC}"
fi

echo ""
exit $FAIL_COUNT
