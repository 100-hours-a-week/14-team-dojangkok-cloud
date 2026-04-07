# FIS 실험 환경 — 워커 노드 장애 시 트래픽 라우팅 실험 (v1.0.0)

- 작성일: 2026-04-07
- 최종수정일: 2026-04-07
- 작성자: jsh (waf.jung)
- 상태: draft
- 관련문서: `../../../docs/technical/fis_series_plan_v1_0_0.md`

---

## 개요

AWS FIS로 워커 노드를 정지시키고, ALB → NodePort → NGF → Backend Pod 트래픽 경로에서 Endpoints 갱신 및 NGF upstream 반영 타이밍을 실측하는 실험 환경.

**AWS 계정**: 920624925547 | **리전**: ap-northeast-2
**기존 VPC**: vpc-01300a19edfeff324 (10.0.0.0/24)에 Secondary CIDR 추가
**Stateful**: 기존 data 인스턴스(10.0.0.202) 활용, 실험 대상 아님

---

## 아키텍처

```
Client → ALB(:80) → NodePort(30080) → NGF DaemonSet → Backend Pod → data(10.0.0.202)

클러스터: 1 CP + 3 Worker (t4g.medium, 3-AZ)
네트워크: VPC Secondary CIDR 10.1.0.0/16, public subnet (NAT 불필요)
```

---

## 디렉토리 구조

```
4-fis-experiment/
├── README.md
├── terraform/                     # Step 1: 인프라 생성
│   ├── versions.tf
│   ├── variables.tf
│   ├── terraform.tfvars
│   ├── main.tf
│   ├── outputs.tf
│   └── modules/
│       ├── networking/            # Secondary CIDR + 3 public subnets
│       ├── security-groups/       # ALB, CP, Worker, data SG 룰
│       ├── iam/                   # ECR pull 전용
│       ├── k8s-nodes/             # 1 CP + 3 Worker
│       └── alb/                   # HTTP only
├── ansible/                       # Step 2-3: K8S 부트스트랩
│   ├── ansible.cfg
│   ├── inventory/hosts.ini
│   ├── group_vars/all.yml
│   ├── playbooks/
│   │   ├── site.yml
│   │   ├── 01-common.yml
│   │   ├── 02-init-cp.yml
│   │   ├── 03-join-workers.yml
│   │   └── 04-cluster-components.yml
│   └── roles/
│       ├── common/
│       ├── containerd/
│       ├── kubeadm-prereqs/
│       ├── ecr-credential-provider/
│       ├── kubeadm-init/
│       ├── kubeadm-join/
│       ├── calico/
│       ├── coredns-config/
│       ├── gateway-fabric/
│       └── argocd/
├── k8s/                           # Step 4: 앱 배포
│   ├── base/
│   │   ├── 00-namespace.yaml
│   │   ├── 01-backend-secret.yaml
│   │   ├── 02-backend-service.yaml
│   │   ├── 03-gateway.yaml
│   │   └── 04-httproute.yaml
│   ├── exp-a/                     # baseline (replica 3, spread/PDB 없음)
│   │   └── backend-deployment.yaml
│   └── exp-b/                     # 개선 (spread + PDB + proxy_next_upstream)
│       ├── backend-deployment.yaml
│       ├── backend-pdb.yaml
│       └── nginx-proxy.yaml
├── fis/                           # Step 5: FIS 구성
│   ├── fis-trust-policy.json
│   ├── fis-role-policy.json
│   ├── fis-template-a.json       # PT15M (장기 관찰)
│   └── fis-template-b.json       # PT10M (개선 검증)
├── k6/                            # 부하 테스트
│   └── scenario-fis-availability.js
└── scripts/                       # 실행 스크립트
    ├── 00-prerequisites.sh
    ├── 01-terraform-apply.sh
    ├── 02-generate-inventory.sh
    ├── 03-ansible-bootstrap.sh
    ├── verify-cluster.sh
    ├── 04-deploy-exp-a.sh
    ├── verify-app.sh
    ├── 05-setup-fis.sh
    ├── 06-run-exp-a.sh
    ├── 07-deploy-exp-b.sh
    ├── 08-run-exp-b.sh
    └── 99-teardown.sh
```

---

## 실행 순서

### 필요 도구

**로컬(Mac)**: aws-cli, terraform, ansible, jq
**CP(자동 설치)**: kubectl, helm
**k6**: 로컬 또는 CP

### 단계별 실행

| Step | 내용 | 실행 위치 | 스크립트 |
|------|------|----------|---------|
| 0 | 사전 요건 확인 (AWS 계정, 도구) | 로컬 | `00-prerequisites.sh` |
| 1 | Terraform — VPC/SG/EC2/ALB 생성 | 로컬 | `01-terraform-apply.sh` |
| 2 | TF output → Ansible inventory | 로컬 | `02-generate-inventory.sh` |
| 3 | Ansible — K8S 부트스트랩 | 로컬→EC2 | `03-ansible-bootstrap.sh` |
| 3.5 | 클러스터 구성 검증 (자동+수동) | CP | `verify-cluster.sh` |
| 4 | K8S 앱 배포 (실험 A 구성) | CP | `04-deploy-exp-a.sh` |
| 4.5 | 앱 배포 완료 검증 (자동+수동) | CP+로컬 | `verify-app.sh` |
| 5 | FIS IAM/템플릿/CloudWatch 구성 | 로컬 | `05-setup-fis.sh` |
| **6** | **실험 A**: baseline 측정 | CP+로컬 | `06-run-exp-a.sh` |
| 7 | 개선사항 적용 (exp-b) | CP | `07-deploy-exp-b.sh` |
| **8** | **실험 B**: 개선 후 비교 | CP+로컬 | `08-run-exp-b.sh` |
| **C** | **실험 C**: HPA vs ArgoCD auto-sync | CP | (수동) |
| 9 | 전체 정리 (terraform destroy) | 로컬 | `99-teardown.sh` |

---

## 실험 설계

### 실험 A — baseline (replicas 3, 개선 없음)

Worker 2c를 15분간 정지. 각 워커에 Pod 1개씩 배치된 상태.

**핵심 질문**:
1. t+0 ~ t+40s (Endpoints 갱신 전): 에러율? (이론 ~33%, stale upstream hit)
2. t+40s (Endpoints 갱신 후): 에러율이 0%로 떨어지는가?
3. NGF가 Endpoints 변경을 얼마나 빨리 반영하는가?
4. Pod eviction → 재스케줄 후 upstream 3개 복원 타이밍

**예상 타임라인**:
```
0:00   k6 시작 (30 VU, 20분)
2:00   FIS — Worker 2c stop (PT15M)
2:40   Node NotReady → Endpoints에서 pod-2c 제거
3:40   toleration 60s → eviction → 재스케줄
4:20   새 Pod Ready → upstream 3개 복원
17:00  FIS 종료 — Worker 재시작
20:00  k6 종료
```

### 실험 B — 개선 (topologySpread + PDB + proxy_next_upstream)

실험 A 결과를 기반으로 개선사항 적용 후 Worker 2c를 10분간 정지.

| 실험 A 관찰 | 실험 B 개선 |
|------------|-----------|
| t+40s에 에러 0% | topologySpread만 추가 |
| t+40s 이후에도 에러 | proxy_next_upstream 추가 필수 |
| stale 구간 에러 ~33% | proxy_next_upstream으로 retry |

### 실험 C — HPA vs ArgoCD auto-sync

| 단계 | Git 상태 | HPA | 관찰 |
|------|---------|-----|------|
| C-1 | replicas 미지정 | min:1, max:3 | 충돌 없음 |
| C-2 | replicas: 1 명시 | min:1, max:3 | oscillation 발생? |
| C-3 | + ignoreDifferences | min:1, max:3 | 충돌 해소 |

---

## 비용

- EC2 4대 (t4g.medium): ~$0.134/hr
- ALB: ~$0.023/hr
- **총합: ~$0.16/hr ≈ 2-3시간 실험 시 $0.50**

---

## 주의사항

1. **Secondary CIDR**: 같은 VPC → 10.1.x ↔ 10.0.0.202 자동 라우팅. data SG 인바운드 추가 필수
2. **ECR**: 920624925547 계정의 `dev-dojangkok-be` 사용 (없으면 cross-account pull → push)
3. **Backend config**: application.yaml에 data 인스턴스 DB 비밀번호 필요 (S3: dojangkok-deploy)
4. **SSH 키**: `dojangkok-key` 키페어 로컬 필요
5. **정리**: 실험 후 반드시 `99-teardown.sh` 실행 (비용 누적 방지)

---

## 참조

| 용도 | 경로 |
|------|------|
| 연재 계획 | `docs/technical/fis_series_plan_v1_0_0.md` |
| V3 Terraform | `IaC/3-v3/aws/environments/k8s-dev/main.tf` |
| V3 Ansible | `IaC/3-v3/ansible/playbooks/site.yml` |
| Backend deployment | `k8s/apps/base/backend/deployment.yaml` |
| NGF values | `k8s/infra/gateway-fabric/values.yaml` |
| k6 chaos scenario | `../../../load-test-code/load-test-share/scenarios/scenario-chaos-availability.js` |
| FIS 실험 교훈 | `../../../docs/technical/fis_az2c_failure_v2_0_0.md` |
