#!/bin/bash
# 앱 배포 완료 검증 (CP에서 실행, ALB_DNS는 인자로 전달)
set -euo pipefail

ALB_DNS=${1:-""}

echo "=== Pod 상태 ==="
kubectl get pods -n dojangkok -o wide
POD_READY=$(kubectl get pods -n dojangkok --no-headers | grep -c "Running" || true)
[ "$POD_READY" -eq 3 ] && echo "  ✅ Backend 3개 Running" || echo "  ❌ Running: $POD_READY/3"

echo ""
echo "=== Pod AZ 분포 ==="
kubectl get pods -n dojangkok -o custom-columns='NAME:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP'
NODES=$(kubectl get pods -n dojangkok -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | wc -l | tr -d ' ')
[ "$NODES" -eq 3 ] && echo "  ✅ 3개 워커에 분산" || echo "  ⚠️ ${NODES}개 노드에 배치 (수동 재배치 필요)"

echo ""
echo "=== Endpoints ==="
kubectl get endpoints -n dojangkok backend

echo ""
echo "=== Gateway + HTTPRoute ==="
kubectl get gateway -n dojangkok
kubectl get httproute -n dojangkok

if [ -n "$ALB_DNS" ]; then
  echo ""
  echo "=== ALB E2E 테스트 ==="
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${ALB_DNS}/actuator/health" || echo "000")
  [ "$STATUS" = "200" ] && echo "  ✅ /actuator/health → 200" || echo "  ❌ /actuator/health → $STATUS"

  STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${ALB_DNS}/api/v1/members/me" || echo "000")
  [ "$STATUS" = "401" ] && echo "  ✅ /api/v1/members/me → 401 (라우팅 정상)" || echo "  ⚠️ /api/v1/members/me → $STATUS"
fi
