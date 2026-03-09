# 5단계: V3 IaC 설계 — Terraform + Ansible (v1.1.0)

- 작성일: 2026-03-09
- 최종수정일: 2026-03-09
- 작성자: infra (claude-code)
- 상태: draft
- 관련문서: `./design-step5.md` (v3.0.0), `./node-sizing.md` (v4.0.0), `./cost-comparison.md` (v3.0.0)

> **스코프**: Stateless 워크로드 K8S 클러스터 구축에 필요한 인프라 코드 설계.
> DB HA(Phase 1 EC2 → Phase 2 StatefulSet)는 별도 프로젝트로 분리 — 본 문서 범위 밖.

---

## 목차

**Part 1. Terraform — AWS 인프라 프로비저닝**

1. [디렉터리 구조](#1-디렉터리-구조)
2. [V2 모듈 재활용 분석](#2-v2-모듈-재활용-분석)
3. [네트워크 — VPC, 서브넷, 라우팅](#3-네트워크--vpc-서브넷-라우팅)
4. [보안그룹](#4-보안그룹)
5. [K8S 노드 (EC2)](#5-k8s-노드-ec2)
6. [ALB](#6-alb)
7. [NAT Instance](#7-nat-instance)
8. [IAM](#8-iam)
9. [기타 리소스](#9-기타-리소스)
10. [State 관리](#10-state-관리)

**태그 & 라벨 전략 — Terraform → Ansible → K8S**

- [기본 태그 정책](#기본-태그-정책)
- [K8S 클러스터 전용 태그](#k8s-클러스터-전용-태그)
- [노드 토폴로지 매핑](#노드-토폴로지-매핑)
- [자동화 파이프라인 연결](#자동화-파이프라인-연결)

**Part 2. Ansible — kubeadm 클러스터 부트스트랩**

11. [디렉터리 구조](#11-디렉터리-구조-1)
12. [공통 설정 (common)](#12-공통-설정-common)
13. [Control Plane 초기화](#13-control-plane-초기화)
14. [Worker Join](#14-worker-join)
15. [CNI — Calico VXLAN](#15-cni--calico-vxlan)
16. [EBS CSI Driver + StorageClass](#16-ebs-csi-driver--storageclass)
17. [NGINX Gateway Fabric](#17-nginx-gateway-fabric)
18. [실행 순서](#18-실행-순서)
19. [Fault Injection (장애 주입) 대응 아키텍처](#19-fault-injection-장애-주입-대응-아키텍처)

---

## Part 1. Terraform — AWS 인프라 프로비저닝

### 1. 디렉터리 구조

```
IaC/3-v3/aws/
├── modules/
│   ├── networking/          ← V2 재활용 (수정 없음)
│   ├── security-groups/     ← V2 재활용 (K8S 포트 추가)
│   ├── alb/                 ← V2 재활용 (NodePort TG로 변경)
│   ├── nat-instance/        ← V2 재활용 (3-AZ 확장)
│   ├── k8s-nodes/           ← 신규 (CP + Worker EC2)
│   └── iam/                 ← V2 재활용 (K8S 노드 역할 추가)
├── environments/
│   └── prod/
│       ├── main.tf          ← 모듈 조합
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars
└── backend.tf               ← S3 state
```

V2 경로: `IaC/2-v2/aws/`
V3 경로: `IaC/3-v3/aws/`

> V2 모듈을 복사하여 V3에서 독립 관리. V2 운영 중이므로 V2 모듈 직접 수정은 위험.

---

### 2. V2 모듈 재활용 분석

| V2 모듈 | V3 재활용 | 변경 수준 | 비고 |
|---------|----------|----------|------|
| `networking/` | **그대로** | 없음 | map 기반 서브넷, locals에서 2b 추가만 |
| `security-groups/` | **포트 추가** | 소 | K8S 전용 포트 규칙 추가 |
| `alb/` | **TG 변경** | 중 | Instance→NodePort, 경로 라우팅 제거 |
| `nat-instance/` | **AZ 확장** | 소 | 2→3 AZ, locals 변경만 |
| `iam/` | **역할 추가** | 소 | K8S 노드용 IAM 역할/정책 |
| `ecr/` | **사용 안함** | — | data source로 기존 ECR 참조 |
| `asg/` | **사용 안함** | — | K8S Worker는 고정 EC2 |
| `compute/` | **참고** | — | k8s-nodes 신규 모듈로 대체 |
| `nlb/` | **사용 안함** | — | RabbitMQ 내부화 (K8S Pod) |
| `codedeploy/` | **사용 안함** | — | ArgoCD로 대체 |

---

### 3. 네트워크 — VPC, 서브넷, 라우팅

design-step5.md §7 기반. V2 networking 모듈은 map 기반이므로 `locals`만 변경.

#### VPC

| 항목 | 값 |
|------|-----|
| CIDR | 10.10.0.0/18 |
| 리전 | ap-northeast-2 (Seoul) |
| DNS Hostnames | enabled |
| DNS Resolution | enabled |

#### 서브넷 정의

```hcl
locals {
  subnets = {
    # Public (ALB, NAT Instance)
    "public-2a" = { cidr = "10.10.0.0/24",  az = "a" }
    "public-2b" = { cidr = "10.10.2.0/24",  az = "b" }
    "public-2c" = { cidr = "10.10.1.0/24",  az = "c" }

    # Private — K8S 노드
    "k8s-2a"    = { cidr = "10.10.4.0/22",   az = "a" }  # CP, W1, W2
    "k8s-2b"    = { cidr = "10.10.12.0/22",  az = "b" }  # W3, W4
    "k8s-2c"    = { cidr = "10.10.8.0/22",   az = "c" }  # W5, W6
  }

  public_subnets  = { for k, v in local.subnets : k => v if startswith(k, "public") }
  private_subnets = { for k, v in local.subnets : k => v if startswith(k, "k8s") }
}
```

> Data 서브넷(DB HA용)은 별도 프로젝트에서 추가.

#### 라우팅

| 경로 | 대상 |
|------|------|
| Public → 0.0.0.0/0 | IGW |
| Private 2a → 0.0.0.0/0 | NAT-a (같은 AZ) |
| Private 2b → 0.0.0.0/0 | NAT-b (같은 AZ) |
| Private 2c → 0.0.0.0/0 | NAT-c (같은 AZ) |

V2 모듈이 이미 AZ별 private route table을 지원한다.

---

### 4. 보안그룹

design-step5.md §18, §8, §14 기반. V2 SG 모듈(map 기반) 재활용.

#### SG 정의

```hcl
locals {
  security_groups = {
    # ALB — 외부 트래픽 수신
    "alb" = {
      description = "K8S ALB"
      ingress_rules = [
        { from_port = 80,  to_port = 80,  protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] },
        { from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] },
      ]
    }

    # K8S Control Plane
    "k8s-cp" = {
      description = "K8S Control Plane"
      ingress_rules = [
        { from_port = 6443,  to_port = 6443,  protocol = "tcp", cidr_blocks = ["10.10.0.0/18"], description = "kube-apiserver" },
        { from_port = 2379,  to_port = 2380,  protocol = "tcp", cidr_blocks = ["10.10.0.0/18"], description = "etcd" },
        { from_port = 10250, to_port = 10250, protocol = "tcp", cidr_blocks = ["10.10.0.0/18"], description = "kubelet" },
        { from_port = 10257, to_port = 10257, protocol = "tcp", cidr_blocks = ["10.10.0.0/18"], description = "kube-controller-manager" },
        { from_port = 10259, to_port = 10259, protocol = "tcp", cidr_blocks = ["10.10.0.0/18"], description = "kube-scheduler" },
      ]
    }

    # K8S Worker 노드
    "k8s-worker" = {
      description = "K8S Worker"
      ingress_rules = [
        { from_port = 10250, to_port = 10250, protocol = "tcp", cidr_blocks = ["10.10.0.0/18"], description = "kubelet" },
        { from_port = 4789,  to_port = 4789,  protocol = "udp", cidr_blocks = ["10.10.0.0/18"], description = "Calico VXLAN" },
        { from_port = 30000, to_port = 32767, protocol = "tcp", description = "NodePort — ALB SG에서만 허용" },
      ]
    }

    # NAT Instance (V2와 동일)
    "nat" = {
      description = "NAT Instance"
      ingress_rules = [
        { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["10.10.0.0/18"], description = "VPC 내부 전체" },
      ]
    }
  }
}
```

#### SG-to-SG 규칙 (모듈 외부)

V2 패턴처럼 `aws_security_group_rule`로 별도 정의:

| 소스 SG | 대상 SG | 포트 | 용도 |
|---------|---------|------|------|
| alb | k8s-worker | 30000-32767 | ALB → NodePort |
| k8s-worker | k8s-cp | 6443 | Worker → API Server |
| k8s-cp | k8s-worker | 10250 | CP → Worker kubelet |

> **주의**: NodePort 소스는 `ALB SG ID`로 제한 (0.0.0.0/0 아님). design-step5.md §15 참조.

---

### 5. K8S 노드 (EC2)

**신규 모듈** `k8s-nodes/`. V2 compute 모듈 참고하되 K8S 전용으로 설계.

#### CP 노드

| 항목 | 값 |
|------|-----|
| 인스턴스 타입 | t4g.medium (2vCPU, 4GB) |
| 수량 | 1 |
| AZ | 2a |
| 서브넷 | k8s-2a (10.10.4.0/22) |
| SG | k8s-cp |
| 디스크 | 30GB gp3 |
| source_dest_check | **false** (VXLAN) |
| AMI | Ubuntu 24.04 ARM64 (Canonical) |

#### Worker 노드

| 항목 | 값 |
|------|-----|
| 인스턴스 타입 | t4g.large (2vCPU, 8GB) |
| 수량 | 6 |
| 배치 | 2-2-2 (2a: W1,W2 / 2b: W3,W4 / 2c: W5,W6) |
| SG | k8s-worker |
| 디스크 | 30GB gp3 |
| source_dest_check | **false** (VXLAN) |
| AMI | Ubuntu 24.04 ARM64 (Canonical) |
| T4g Credit | Unlimited 모드 |

#### 모듈 설계

```hcl
# k8s-nodes 모듈 입력
variable "nodes" {
  type = map(object({
    instance_type = string
    subnet_id     = string
    sg_ids        = list(string)
    disk_size_gb  = number
    role          = string   # "cp" | "worker"
    tags          = map(string)
  }))
}
```

사용 예:

```hcl
module "k8s_nodes" {
  source = "../modules/k8s-nodes"

  nodes = {
    "cp" = {
      instance_type = "t4g.medium"
      subnet_id     = module.networking.private_subnet_ids["k8s-2a"]
      sg_ids        = [module.security_groups.sg_ids["k8s-cp"]]
      disk_size_gb  = 30
      role          = "cp"
      tags = merge(local.common_tags, {
        "k8s:cluster-name" = "dojangkok-v3"
        "k8s:role"         = "control-plane"
        "k8s:nodepool"     = "system"
      })
    }
    "w1" = {
      instance_type = "t4g.large"
      subnet_id     = module.networking.private_subnet_ids["k8s-2a"]
      sg_ids        = [module.security_groups.sg_ids["k8s-worker"]]
      disk_size_gb  = 30
      role          = "worker"
      tags = merge(local.common_tags, {
        "k8s:cluster-name" = "dojangkok-v3"
        "k8s:role"         = "worker"
        "k8s:nodepool"     = "default"
      })
    }
    # ... w2~w6 동일 구조, AZ별 서브넷 변경
  }
}
```

#### 핵심 설정

- **source_dest_check = false**: 모든 K8S 노드 필수. Calico VXLAN이 Pod IP를 캡슐화하여 전송하므로 AWS 기본 패킷 검증 비활성화 필요.
- **AMI**: Ubuntu 24.04 LTS ARM64 (Canonical owner: 099720109477). V2 NAT Instance와 동일 AMI 소스.
- **lifecycle.ignore_changes = [ami]**: 생성 후 AMI 변경으로 인한 재생성 방지.
- **user_data**: 기본 패키지 설치까지만. kubeadm 설정은 Ansible이 담당.

---

### 6. ALB

design-step5.md §14, §15 기반. V2 ALB 모듈 수정.

#### V2와 차이점

| 항목 | V2 | V3 |
|------|-----|-----|
| 타겟 타입 | Instance (ASG 등록) | Instance (Worker `workers_per_az × 3`) |
| 타겟 포트 | 3000/8080 (앱 포트 직접) | 30xxx (NodePort) |
| 경로 라우팅 | ALB Listener Rule | NGINX Gateway Fabric (HTTPRoute) |
| Health Check | `/health-check`, `/actuator/health` | Gateway Fabric 헬스 엔드포인트 |

#### 타겟그룹

| 타겟그룹 | 포트 | 대상 | Health Check |
|---------|------|------|-------------|
| k8s-gateway | NodePort (30xxx) | Worker 전체 (`workers_per_az × 3`) | `/healthz` |

> V2에서는 FE/BE 별도 TG + path rule이었으나, V3에서는 **단일 TG**로 단순화. 경로 분기는 K8S 내부 Gateway Fabric이 처리.

#### 리스너

| 리스너 | 포트 | 액션 |
|--------|------|------|
| HTTP | 80 | → HTTPS 301 리다이렉트 |
| HTTPS | 443 | → k8s-gateway TG (ACM 인증서) |

#### Worker 등록

V2는 ASG가 자동 등록했으나, V3은 고정 EC2이므로 `aws_lb_target_group_attachment`로 Worker 전체 수동 등록. `workers_per_az` 변경 시 자동 반영.

```hcl
resource "aws_lb_target_group_attachment" "workers" {
  for_each = { for k, v in module.k8s_nodes.instances : k => v if v.role == "worker" }

  target_group_arn = module.alb.target_group_arns["k8s-gateway"]
  target_id        = each.value.id
  port             = var.gateway_nodeport  # 30xxx
}
```

---

### 7. NAT Instance

design-step5.md §8 기반. V2 모듈 재활용, 3-AZ 확장.

#### V2와 차이점

| 항목 | V2 | V3 |
|------|-----|-----|
| 수량 | 2대 (2a, 2c) | **3대** (2a, 2b, 2c) |
| ASG | 없음 | **ASG 래핑** (Min=Max=1) |

#### 인스턴스 배치

| AZ | 서브넷 | 라우트 테이블 |
|----|--------|-------------|
| 2a | public-2a (10.10.0.0/24) | k8s-2a private RT |
| 2b | public-2b (10.10.2.0/24) | k8s-2b private RT |
| 2c | public-2c (10.10.1.0/24) | k8s-2c private RT |

#### ASG 래핑 추가

V2 모듈에 ASG 기능이 없으므로 **V3에서 추가 구현** 또는 별도 처리.

방법 A: NAT Instance 모듈에 ASG 옵션 추가
방법 B: 기존 ASG 모듈을 NAT용으로 활용 (launch template + ASG min=max=1)

> 권장: 방법 B. ASG 모듈의 launch template 생성 → health check → 자동 복구 패턴 재활용.

#### EIP

NAT Instance당 EIP 1개 (총 3개). V2 모듈이 이미 per-instance EIP 생성 지원.

> **주의**: ASG 래핑 시 EIP를 Launch Template이 아닌 ASG lifecycle hook 또는 user_data에서 연결해야 함 (ASG 교체 시 EIP 재연결).

---

### 8. IAM

#### K8S 노드 IAM 역할

```hcl
# K8S Node 공통 정책
{
  "Effect": "Allow",
  "Action": [
    "ecr:GetDownloadUrlForLayer",
    "ecr:BatchGetImage",
    "ecr:BatchCheckLayerAvailability",
    "ecr:GetAuthorizationToken"
  ],
  "Resource": "*"
}
```

#### EBS CSI Driver IAM 정책

```hcl
# EBS CSI Driver가 볼륨 생성/삭제를 위해 필요
{
  "Effect": "Allow",
  "Action": [
    "ec2:CreateVolume",
    "ec2:DeleteVolume",
    "ec2:AttachVolume",
    "ec2:DetachVolume",
    "ec2:DescribeVolumes",
    "ec2:DescribeInstances",
    "ec2:CreateTags"
  ],
  "Resource": "*"
}
```

> kubeadm 기반이므로 IRSA(IAM Roles for Service Accounts) 대신 **EC2 Instance Profile**을 통해 권한 부여. 모든 Worker 노드가 동일 IAM 역할을 가진다.

#### IAM 역할 목록

| 역할 | 대상 | 정책 |
|------|------|------|
| k8s-node-role | CP + Worker | ECR pull, EBS CSI, CloudWatch Logs (선택) |
| nat-instance-role | NAT | 없음 (순수 네트워크 포워딩) |

---

### 9. 기타 리소스

#### ECR (data source)

```hcl
# 기존 V2 ECR 리포지토리 참조 (신규 생성 아님)
data "aws_ecr_repository" "be" {
  name = "dojangkok-be"
}

data "aws_ecr_repository" "fe" {
  name = "dojangkok-fe"
}

data "aws_ecr_repository" "ai" {
  name = "dojangkok-ai"
}
```

#### ACM (data source)

```hcl
# 기존 인증서 참조
data "aws_acm_certificate" "main" {
  domain   = "dojangkok.cloud"
  statuses = ["ISSUED"]
}
```

#### S3 (랜딩페이지, data source)

기존 V2 S3/CloudFront/Route53은 K8S와 독립. 변경 없음.

---

### 10. State 관리

| 항목 | 값 |
|------|-----|
| Backend | S3 |
| Bucket | `dojangkok-v3-tfstate` (신규 생성) |
| Key | `v3/prod/terraform.tfstate` |
| Lock | DynamoDB `dojangkok-v3-tflock` |
| Region | ap-northeast-2 |

> V2 state(`dojangkok-ai-iac-backend`)와 완전 분리. V2 리소스와 V3 리소스가 서로 영향 없음.

---

## 태그 & 라벨 전략 — Terraform → Ansible → K8S

IaC 전체 파이프라인(Terraform → Ansible → K8S)을 관통하는 메타데이터 규약.
AWS 리소스 태그가 Ansible 동적 인벤토리 필터 → K8S 노드 라벨로 이어지는 자동화 흐름.

### 기본 태그 정책

모든 AWS 리소스에 적용하는 필수 태그:

| 태그 키 | 값 | 용도 |
|---------|-----|------|
| `Environment` | `dev` / `prod` | 환경 구분 |
| `Project` | `dojangkok` | 프로젝트 식별 |
| `ManagedBy` | `terraform` | IaC 관리 여부 |

```hcl
# environments/prod/locals.tf
locals {
  common_tags = {
    Environment = "prod"
    Project     = "dojangkok"
    ManagedBy   = "terraform"
  }
}
```

> 모든 모듈에서 `merge(local.common_tags, { ... })`로 사용. §5 K8S 노드 예시 참조.

### K8S 클러스터 전용 태그

K8S 노드 EC2에 추가 적용하는 태그:

| 태그 키 | 값 예시 | 용도 |
|---------|---------|------|
| `k8s:cluster-name` | `dojangkok-v3` | 클러스터 식별 — Ansible 동적 인벤토리 필터 |
| `k8s:role` | `control-plane` / `worker` | 노드 역할 — Ansible 그룹 자동 생성 |
| `k8s:nodepool` | `default` / `system` | 노드풀 구분 — K8S 라벨 매핑 |

> `k8s:` 접두사로 K8S 전용 태그를 네임스페이스화. AWS 태그 키에 콜론(`:`) 사용 가능.

### 노드 토폴로지 매핑

CP 1대 + Worker `workers_per_az × 3 AZ`대 태그 할당.
`workers_per_az` 변수로 AZ당 워커 수 조절 (초기 1, prod 목표 2).

| 노드 | `k8s:role` | `k8s:nodepool` | AZ | 서브넷 | 비고 |
|------|------------|----------------|-----|--------|------|
| cp | `control-plane` | `system` | 2a | k8s-2a | 고정 |
| w1 | `worker` | `default` | 2a | k8s-2a | workers_per_az ≥ 1 |
| w2 | `worker` | `default` | 2a | k8s-2a | workers_per_az ≥ 2 |
| w3 | `worker` | `default` | 2b | k8s-2b | workers_per_az ≥ 1 |
| w4 | `worker` | `default` | 2b | k8s-2b | workers_per_az ≥ 2 |
| w5 | `worker` | `default` | 2c | k8s-2c | workers_per_az ≥ 1 |
| w6 | `worker` | `default` | 2c | k8s-2c | workers_per_az ≥ 2 |

> 초기 배포: `workers_per_az = 1` (3대). 안정화 후 tfvars에서 2로 변경, `terraform apply`로 스케일업.
> CP는 `system` 노드풀. 향후 모니터링/인프라 전용 노드 추가 시에도 `system` 노드풀 사용.

### 자동화 파이프라인 연결

```
Terraform tags          Ansible aws_ec2 plugin       kubelet --node-labels
──────────────          ──────────────────────       ─────────────────────
k8s:cluster-name   →    필터: 클러스터별 인벤토리     —
k8s:role           →    keyed_groups 그룹 생성       node-role.kubernetes.io/{role}
k8s:nodepool       →    호스트 변수 전달             dojangkok.cloud/nodepool={pool}
(EC2 AZ metadata)  →    —                           topology.kubernetes.io/zone={az}
```

**흐름**:

1. **Terraform** — EC2 생성 시 `common_tags` + `k8s:*` 태그 부여 (§5 참조)
2. **Ansible** — `aws_ec2` 플러그인이 `k8s:cluster-name` 태그로 필터, `k8s:role`로 그룹 자동 생성 (§11 참조)
3. **kubelet** — `--node-labels` 플래그로 태그를 K8S 노드 라벨로 변환 (§14 참조)

> 태그 추가/변경 시 Terraform apply → Ansible 인벤토리 자동 반영 → kubelet 라벨 업데이트까지 일관성 유지.

---

## Part 2. Ansible — kubeadm 클러스터 부트스트랩

### 11. 디렉터리 구조

```
IaC/3-v3/ansible/
├── ansible.cfg
├── inventory/
│   └── aws_ec2.yml           ← aws_ec2 동적 인벤토리 (태그 기반 자동 구성)
├── group_vars/
│   └── all.yml               ← 클러스터 공통 변수
├── roles/
│   ├── common/               ← 기본 패키지, sysctl, swap off
│   ├── containerd/           ← containerd 설치/설정
│   ├── kubeadm-prereqs/      ← kubeadm/kubelet/kubectl 설치
│   ├── kubeadm-init/         ← CP: kubeadm init
│   ├── kubeadm-join/         ← Worker: kubeadm join
│   ├── calico/               ← Calico CNI 설치
│   ├── ebs-csi/              ← EBS CSI Driver 설치
│   └── gateway-fabric/       ← NGINX Gateway Fabric 설치
└── playbooks/
    ├── site.yml              ← 전체 실행 (1회)
    ├── add-worker.yml        ← Worker 추가 시
    └── upgrade-cluster.yml   ← K8S 버전 업그레이드 시
```

#### 동적 인벤토리 (aws_ec2 plugin)

`k8s:cluster-name` 태그로 필터, `k8s:role` 태그로 그룹 자동 생성. 태그 전략 섹션 참조.

```yaml
# inventory/aws_ec2.yml
plugin: amazon.aws.aws_ec2
regions:
  - ap-northeast-2

filters:
  "tag:k8s:cluster-name": "dojangkok-v3"
  instance-state-name: running

keyed_groups:
  # k8s:role 태그 → role_control_plane, role_worker 그룹 자동 생성
  - key: tags['k8s:role'] | regex_replace('[^a-zA-Z0-9_]', '_')
    prefix: role

hostvar_expressions:
  ansible_host: private_ip_address
  k8s_role: "tags['k8s:role']"
  k8s_nodepool: "tags['k8s:nodepool']"
  node_az: placement.availability_zone

compose:
  ansible_user: "'ubuntu'"
  ansible_ssh_private_key_file: "'~/.ssh/k8s-v3.pem'"
```

> **주의**: `amazon.aws` 컬렉션 필요 (`ansible-galaxy collection install amazon.aws`).
> 기존 정적 인벤토리(`hosts.yml`) 대비 장점: 노드 추가/교체 시 인벤토리 수동 수정 불필요.

#### 공통 변수

```yaml
# group_vars/all.yml
k8s_version: "1.31"              # kubeadm/kubelet/kubectl 버전
pod_cidr: "192.168.0.0/16"       # Calico default
service_cidr: "10.96.0.0/12"     # kubeadm default
calico_vxlan_mtu: 8951           # AWS Jumbo Frame 9001 - VXLAN 50
containerd_version: "1.7"
```

---

### 12. 공통 설정 (common)

모든 노드(CP + Worker)에 적용.

#### 태스크

1. **swap 비활성화** — kubeadm 필수 조건
   ```
   swapoff -a
   /etc/fstab에서 swap 항목 주석 처리
   ```

2. **커널 모듈 로드**
   ```
   overlay
   br_netfilter
   ```

3. **sysctl 설정**
   ```
   net.bridge.bridge-nf-call-iptables  = 1
   net.bridge.bridge-nf-call-ip6tables = 1
   net.ipv4.ip_forward                 = 1
   ```

4. **기본 패키지**
   ```
   apt-transport-https, ca-certificates, curl, gnupg
   ```

---

### 13. Control Plane 초기화

CP 노드에서만 실행.

#### containerd 설치

```yaml
# roles/containerd/tasks/main.yml
- containerd 패키지 설치 (apt)
- /etc/containerd/config.toml 설정
  - SystemdCgroup = true  # systemd cgroup driver 사용
- systemctl enable --now containerd
```

#### kubeadm 설치

```yaml
# roles/kubeadm-prereqs/tasks/main.yml
- Kubernetes apt 저장소 추가 (pkgs.k8s.io)
- kubeadm, kubelet, kubectl 설치 (버전 고정)
- apt-mark hold kubeadm kubelet kubectl
```

#### kubeadm init

```yaml
# roles/kubeadm-init/tasks/main.yml
- kubeadm init 실행
  --pod-network-cidr={{ pod_cidr }}
  --service-cidr={{ service_cidr }}
  --apiserver-advertise-address={{ ansible_host }}
  --kubernetes-version={{ k8s_version }}

- kubeconfig 설정 (~/.kube/config)
- join 토큰 추출 → 팩트로 저장 (Worker join에 전달)
```

#### etcd 백업 (선택)

```yaml
# CP SPOF 대응 — etcd snapshot을 S3에 주기적 백업
- etcdctl snapshot save → S3 업로드 cron 등록
```

> CP 장애 시 etcd snapshot에서 복구. design-step5.md §4 참조.

---

### 14. Worker Join

Worker 6대에 적용. CP init 완료 후 실행.

```yaml
# roles/kubeadm-join/tasks/main.yml
- containerd 설치 (공통)
- kubeadm/kubelet 설치 (공통)

# kubelet extra args — 태그→라벨 자동 매핑
- name: Set kubelet node-labels from AWS tags
  copy:
    dest: /etc/default/kubelet
    content: |
      KUBELET_EXTRA_ARGS=--node-labels=dojangkok.cloud/nodepool={{ k8s_nodepool }},topology.kubernetes.io/zone={{ node_az }}

- kubeadm join 실행
  --token {{ hostvars[groups['role_control_plane'][0]].join_token }}
  --discovery-token-ca-cert-hash {{ hostvars[groups['role_control_plane'][0]].ca_cert_hash }}
  --apiserver {{ hostvars[groups['role_control_plane'][0]].ansible_host }}:6443
```

> `k8s_nodepool`, `node_az`는 동적 인벤토리의 `hostvar_expressions`에서 자동 주입 (§11 참조).
> kubelet 시작 시 `--node-labels`로 K8S 노드 라벨이 자동 설정되므로 별도 `kubectl label` 불필요.

#### 태그→라벨 매핑 표

| AWS 태그 | K8S 노드 라벨 | 설정 방식 |
|---------|-------------|----------|
| `k8s:role` | `node-role.kubernetes.io/{role}` | CP에서 `kubectl label` (join 후) |
| `k8s:nodepool` | `dojangkok.cloud/nodepool` | `--node-labels` (kubelet 자동) |
| EC2 AZ | `topology.kubernetes.io/zone` | `--node-labels` (kubelet 자동) |

#### 노드 역할 라벨링

join 완료 후 CP에서 실행 (`node-role` 라벨은 kubelet이 아닌 kubectl로 설정):

```yaml
- name: Label node roles from AWS tags
  delegate_to: "{{ groups['role_control_plane'][0] }}"
  command: >
    kubectl label node {{ inventory_hostname }}
    node-role.kubernetes.io/{{ k8s_role }}=""
    --overwrite
```

> AZ 라벨(`topology.kubernetes.io/zone`)은 kubelet `--node-labels`로 자동 설정되어 Pod anti-affinity와 topology spread constraint에 사용.

---

### 15. CNI — Calico VXLAN

CP에서 실행. Worker join 후.

design-step5.md §6 기반.

#### 설치

```yaml
# roles/calico/tasks/main.yml
- Calico operator 설치 (Tigera operator)
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28/manifests/tigera-operator.yaml

- Installation CR 적용
  apiVersion: operator.tigera.io/v1
  kind: Installation
  spec:
    calicoNetwork:
      ipPools:
      - cidr: "192.168.0.0/16"
        encapsulation: VXLAN
      mtu: 8951                    # AWS Jumbo Frame 9001 - VXLAN 50
```

#### 검증

```bash
kubectl get pods -n calico-system  # 모든 Pod Running 확인
kubectl get nodes                   # 모든 노드 Ready 확인
calicoctl node status               # VXLAN peering 확인
```

---

### 16. EBS CSI Driver + StorageClass

CP에서 실행. design-step5.md §10 기반.

#### EBS CSI Driver 설치

```yaml
# roles/ebs-csi/tasks/main.yml
- Helm으로 EBS CSI Driver 설치
  helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
  helm install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
    --namespace kube-system
```

> kubeadm 환경이므로 IRSA 대신 EC2 Instance Profile의 IAM 권한을 사용. §8 IAM 참조.

#### StorageClass 생성

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
```

> **WaitForFirstConsumer**: PVC가 Pod 스케줄링 후 같은 AZ에 EBS 생성. AZ 종속성 문제 방지.

---

### 17. NGINX Gateway Fabric

CP에서 실행. design-step5.md §14 기반.

#### 설치

```yaml
# roles/gateway-fabric/tasks/main.yml
- Gateway API CRD 설치
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

- NGINX Gateway Fabric Helm 설치 (NodePort 고정)
  helm install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
    --namespace nginx-gateway --create-namespace \
    --set service.type=NodePort \
    --set service.ports.http.nodePort=30080 \
    --set service.ports.https.nodePort=30443
```

#### DaemonSet 확인

```bash
kubectl get pods -n nginx-gateway  # 6개 Pod (Worker당 1개)
kubectl get svc -n nginx-gateway   # 포트가 30080/30443으로 고정되었는지 확인
```

> **해결됨:** NodePort를 `30080` (또는 `30xxx`)으로 하드코딩 지정하여 배포하므로, 처음부터 Terraform ALB 타겟그룹에 해당 번호 1개를 미리 뚫어둘 수 있습니다. 따라서 "일단 깔고 번호를 확인해서 테라폼을 다시 돌리는" 닭과 알의 문제가 완전히 해소되었습니다.

---

### 18. 실행 순서

```
┌─────────────────────────────────────────┐
│  Phase 0: Terraform apply               │
│  VPC, SG, EC2 10대, NAT 3대, ALB, IAM  │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│  Phase 1: Ansible site.yml              │
│  ① common (전체 노드)                    │
│  ② containerd + kubeadm-prereqs (전체)   │
│  ③ kubeadm-init (CP)                    │
│  ④ kubeadm-join (Worker 6대)            │
│  ⑤ calico (CP에서 적용)                  │
│  ⑥ ebs-csi (CP에서 적용)                 │
│  ⑦ gateway-fabric (CP에서 적용)          │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│  Phase 2: K8S 워크로드 배포 (별도 작업)   │
│  Namespace, NetworkPolicy, RBAC, Pod     │
└─────────────────────────────────────────┘
```

#### 접속 방법

Private 서브넷이므로 SSH 접속은:
- **방법 A**: Bastion Host (public 서브넷) → SSH 터널
- **방법 B**: AWS SSM Session Manager (IAM 기반, SSH 키 불필요)
- **방법 C**: VPN (기존 환경에 따라)

> 권장: SSM Session Manager. IAM 정책만 추가하면 되고, SG에 22번 포트 개방 불필요.

#### Terraform → Ansible 연동

동적 인벤토리(`aws_ec2` plugin)를 사용하므로 별도 변환 스크립트 불필요:

```bash
# 동적 인벤토리 확인 — Terraform apply 후 자동 반영
ansible-inventory -i inventory/aws_ec2.yml --graph
ansible-inventory -i inventory/aws_ec2.yml --list  # 호스트 변수 포함
```

> `k8s:cluster-name` 태그로 필터하므로 Terraform apply만으로 인벤토리가 자동 갱신된다. §11 참조.

---

### 19. Fault Injection (장애 주입) 대응 아키텍처

스프린트 백로그에 새롭게 추가된 "**Fault Injection 기반 장애 대응 검증(Phase 1 안정화)**"을 위해, 현재 v3 IaC 설계가 지원하는 장애 복구 및 대응 메커니즘은 다음과 같습니다. 해당 내용으로 화요일~목요일 장애 주입 시나리오(`Chaos Engineering`)를 테스트할 수 있습니다.

#### 인프라 레벨 (EC2, AZ 완전 장애)
- **Worker 노드 터미네이션 주입**: 6대가 3개 AZ(2-2-2)에 분산되어 있어 특정 노드 한두 대가 죽어도 `ALB → 활성 Worker(Gateway) → Pod`의 N-1 가용성이 유지되는지 검증 가능합니다. 복구의 경우 Terraform `apply`를 다시 수행하면 `Missing` 상태의 EC2를 정확하게 빈자리에 채워넣게 됩니다.
- **NAT Instance 강제 종료**: 3개의 NAT가 각각 ASG (`Min=1`, `Max=1`)로 래핑되어 있으므로, 1개 AZ의 인스턴스를 날려버렸을 때 EC2 Auto Scaling Launch Template 규칙에 의해 5~10분 내로 동일한 AZ에 **자동으로 새 NAT 인스턴스가 생성되는지 (Self-healing)** 모니터링할 수 있습니다.
- **CP 노드 재부팅**: 다중 마스터 구성이 아니므로(Single CP) API 타임아웃 장애가 발생합니다. 하지만 Worker 노드 상에 떠 있는 **기존 App Pod들의 트래픽은 그대로 유지**되는지 (Control Plane과 Data Plane의 독립성) 증명할 수 있습니다.

#### K8S 레벨 (Pod, Node NotReady 주입)
- **Gateway Fabric 장애 주입**: NGINX Gateway Pod를 DaemonSet 형태(또는 ReplicaSet)로 날렸을 때 ALB 타겟그룹 Health Check가 실패하면서, 살아있는 나머지 Gateway Pod로 순단 없이 트래픽 우회 라우팅이 걸리는지 확인할 수 있습니다.
- **Eviction / NodeNotReady 주입**: Kubelet 프로세스를 일시 정지(SIGSTOP) 시켰을 때 일정 시간 후 해당 노드가 NotReady로 빠지며 ReplicaSet 리소스가 자동으로 다른 워커 노드로 Pod 스케줄링(재배치) 시키는지 테스트할 수 있습니다.

---

## 변경 이력

| 버전 | 날짜 | 변경 내용 |
|------|------|----------|
| v1.2.0 | 2026-03-09 | NodePort 고정(Hardcoding) 반영, §19 Fault Injection 인프라/K8S 대응 아키텍처 추가 |
| v1.1.0 | 2026-03-09 | 태그 & 라벨 전략 섹션 추가, §5 태그 규약 반영, §11 동적 인벤토리, §14 kubelet 라벨 매핑 |
| v1.0.0 | 2026-03-09 | 초안: Terraform 모듈 구조 + Ansible 클러스터 부트스트랩 |
