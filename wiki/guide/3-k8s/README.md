# V3 K8S 클러스터 가이드

> 이 문서만 보면 클러스터를 재현하고 운영할 수 있다.

## 아키텍처

```
Client → Route53 → ALB (HTTPS:443)
                      │
                      ▼
              NodePort 30080
              NGINX Gateway Fabric (DaemonSet)
                      │
          ┌───────────┼───────────┐
          ▼           ▼           ▼
    /api → BE:8080  /chat → Chat  / → FE:3000
          │
          ▼
    EC2 External Services
    MySQL / Redis / MongoDB / RabbitMQ
```

## 노드 구성

| 노드 | 인스턴스 | 수량 | AZ |
|------|---------|------|-----|
| Control Plane | t4g.medium | 1 | 2a |
| Worker | t4g.large | 3+ (1+/AZ) | 2a, 2b, 2c |
| NAT | t4g.nano | 1 | 2a |

## 네트워크

| CIDR | 용도 |
|------|------|
| 10.0.0.0/18 | VPC |
| 10.0.48-50.0/24 | K8S 서브넷 (3 AZ) |
| 192.168.0.0/16 | Pod CIDR (Calico) |
| 10.96.0.0/12 | Service CIDR |

## 핵심 컴포넌트

| 컴포넌트 | 버전 | 역할 |
|---------|------|------|
| kubeadm/kubelet/kubectl | 1.31.0 | K8S 관리 |
| Calico | v3.28.0 | CNI, VXLAN, NetworkPolicy |
| NGINX Gateway Fabric | 2.4.2 | Gateway API 인그레스 |
| ArgoCD | — | GitOps 자동 배포 |
| External Secrets Operator | — | AWS SM → K8S Secret |
| EBS CSI Driver | — | PersistentVolume |
| containerd | 1.7 | 컨테이너 런타임 |
| Metrics Server | 3.12.2 | HPA용 메트릭 수집 |

## 가이드 목차

| # | 문서 | 설명 |
|---|------|------|
| 01 | [클러스터 구축](01-cluster-bootstrap.md) | Terraform → Ansible → 클러스터 완성 |
| 02 | [워커노드 충원](02-worker-node-setup.md) | 수동 워커 추가 런북 |
| 03 | [GitHub Actions](03-github-actions.md) | Terraform/Ansible/CI-CD 워크플로우 사용법 |
| 04 | [앱 배포](04-app-deployment.md) | ArgoCD GitOps + Kustomize overlay |
| 05 | [운영](05-operations.md) | 스케일링, 로그, 시크릿, 리소스 |
| 06 | [트러블슈팅](06-troubleshooting.md) | 자주 발생하는 문제 + 해결 |
| 07 | [장애 복구](07-disaster-recovery.md) | etcd 백업/복구, 노드 복구, 클러스터 재구축 |

## 파일 경로

| 구분 | 경로 |
|------|------|
| Terraform | `IaC/3-v3/aws/` |
| Ansible | `IaC/3-v3/ansible/` |
| K8S 매니페스트 | `k8s/apps/`, `k8s/infra/` |
| CI/CD 워크플로우 | `.github/workflows/`, `workflows/3-v3/` |
| 모니터링 | `v3-monitoring/` |
