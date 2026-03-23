# 트러블슈팅

## Pod 문제

### Pending 상태

```bash
kubectl -n dojangkok describe pod <pod-name>
# Events 섹션 확인
```

| 메시지 | 원인 | 해결 |
|--------|------|------|
| Insufficient cpu/memory | 리소스 부족 | 노드 추가 또는 request 줄이기 |
| ErrImagePull | ECR 인증 or 태그 잘못 | ECR 레포 확인, credential provider 확인 |
| Secret not found | ExternalSecret 미동기화 | `kubectl get externalsecret -o wide` |
| node(s) had taints | tolerations 미설정 | tolerations 추가 또는 taint 제거 |

### CrashLoopBackOff

```bash
kubectl -n dojangkok logs <pod-name> --previous
```

| 원인 | 확인 |
|------|------|
| DB 연결 실패 | MySQL EC2 상태 + SG 확인 |
| 시크릿 누락 | ExternalSecret sync 상태 |
| OOM Kill | `kubectl describe pod` → Last State: OOMKilled → limit 증가 |
| 포트 충돌 | containerPort 중복 확인 |

### ImagePullBackOff

```bash
# ECR credential provider 확인 (워커에서)
ls -la /usr/local/bin/ecr-credential-provider
cat /etc/default/kubelet
systemctl restart kubelet
```

## 네트워크 문제

```bash
# Calico 상태
kubectl get pods -n calico-system

# NetworkPolicy 확인
kubectl -n dojangkok get networkpolicy

# DNS 확인
kubectl -n dojangkok exec <pod> -- nslookup backend.dojangkok.svc.cluster.local

# 외부 서비스 연결
kubectl -n dojangkok exec <pod> -- nc -zv <mysql-ip> 3306
```

### 주의: Calico egress DNAT

egress NetworkPolicy는 DNAT 전에 평가됨 → ClusterIP 대상 namespaceSelector 매칭 불가. VPC CIDR로 허용 필요.

## ArgoCD 문제

### Sync 실패

```bash
# 앱 상태 확인
kubectl -n argocd get application dojangkok-apps-dev -o wide

# 상세 에러
kubectl -n argocd get application dojangkok-apps-dev -o jsonpath='{.status.operationState.message}'
```

### OutOfSync 반복 (HPA 충돌)

HPA 관리 Deployment에 `spec.replicas`가 있으면 ArgoCD와 루프 발생.
→ Deployment에서 `spec.replicas` 제거 (HPA가 단독 관리)

### 504 Gateway Timeout

NGF controller → data plane gRPC 끊김 시 upstream stale → 504.
```bash
kubectl -n nginx-gateway rollout restart daemonset nginx-gateway-fabric
```

## 노드 문제

### NotReady

```bash
# 워커에서 kubelet 상태 확인
sudo systemctl status kubelet
sudo journalctl -u kubelet -n 50

# containerd 확인
sudo systemctl status containerd
```

### metrics-server unable to fetch

```bash
kubectl get pods -n kube-system | grep metrics-server
kubectl logs -n kube-system deployment/metrics-server
# → 특정 노드 kubelet 10250 연결 실패 시 SG 확인
```
