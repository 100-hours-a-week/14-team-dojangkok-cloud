#!/bin/bash
# 클러스터 구성 검증 (CP에서 실행)
set -euo pipefail

echo "=== 노드 상태 ==="
kubectl get nodes -o wide
NODE_READY=$(kubectl get nodes --no-headers | grep -c " Ready" || true)
[ "$NODE_READY" -eq 4 ] && echo "  ✅ 노드 4개 Ready" || echo "  ❌ Ready 노드: $NODE_READY/4"

echo ""
echo "=== Calico ==="
kubectl get pods -n calico-system --no-headers
CALICO_RUNNING=$(kubectl get pods -n calico-system --no-headers | grep -c "Running" || true)
echo "  Calico Running: $CALICO_RUNNING"

echo ""
echo "=== NGF DaemonSet ==="
kubectl get pods -n nginx-gateway --no-headers
NGF_READY=$(kubectl get pods -n nginx-gateway --no-headers | grep -c "Running" || true)
[ "$NGF_READY" -eq 3 ] && echo "  ✅ NGF 3개 Running" || echo "  ❌ NGF Running: $NGF_READY/3"

echo ""
echo "=== GatewayClass ==="
kubectl get gatewayclass

echo ""
echo "=== CoreDNS ==="
kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers

echo ""
echo "=== ArgoCD ==="
kubectl get pods -n argocd --no-headers

echo ""
echo "=== 노드 AZ 분포 ==="
kubectl get nodes -o custom-columns='NAME:.metadata.name,AZ:.metadata.labels.topology\.kubernetes\.io/zone'

echo ""
echo "=== Data 인스턴스 연결 테스트 ==="
kubectl run db-test --image=busybox --restart=Never --rm -it --command -- nc -zv 10.0.0.202 3306 2>&1 || echo "  ⚠️ 연결 실패 (SG 확인 필요)"
