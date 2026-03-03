# 5단계: Kubeadm 오케스트레이션

- 작성일: 2026-03-02
- 최종수정일: 2026-03-04

## 개요

**도장콕**은 임차인의 부동산 임대 계약 과정(계약 전·계약 중)을 지원하는 서비스입니다.
핵심 기능: 쉬운 계약서(해설+리스크 검증) | 집노트(답사/비교/체크리스트) | 임대 매물 커뮤니티

**본 문서**: 4단계(Docker 컨테이너화)까지 구축된 멀티 클라우드(AWS+GCP) 인프라를 **AWS 단일 클라우드 + kubeadm 기반 Kubernetes 클러스터**로 전환하는 오케스트레이션 설계를 다룹니다. 컨테이너 단위로 격리된 서비스를 Kubernetes 워크로드로 전환하여, 선언적 배포 관리·자동 복구·수평 확장을 확보하고 운영 복잡도를 줄이는 것이 목표입니다.

## 목차

**Part 0. 서론**

1. [K8S 전환 필요성](#1-k8s-전환-필요성)
2. [대안 비교 및 kubeadm 선택 근거](#2-대안-비교-및-kubeadm-선택-근거)

**Part 1. 컴퓨팅 자원 및 노드 토폴로지**

3. [워크로드 분석과 리소스 산정](#3-워크로드-분석과-리소스-산정)
4. [노드 사이징 — CP와 Worker](#4-노드-사이징--cp와-worker)
5. [AZ 배치 — 노드별 워크로드 배분](#5-az-배치--노드별-워크로드-배분)

**Part 2. 클러스터 내부 네트워크망**

6. [CNI 선택](#6-cni-선택)
7. [네트워크 대역 — Pod CIDR, Service CIDR](#7-네트워크-대역--pod-cidr-service-cidr)
8. [외부 통신 — NAT, RunPod 호출 경로](#8-외부-통신--nat-runpod-호출-경로)

**Part 3. 데이터 및 특수 워크로드 전략**

9. [DB 배치 — K8S 내부 vs 외부](#9-db-배치--k8s-내부-vs-외부) ⚠ 논의 필요
10. [DB HA 토폴로지](#10-db-ha-토폴로지) ⚠ 논의 필요
11. [GPU 워크로드 — K8S 내부 vs RunPod 외부](#11-gpu-워크로드--k8s-내부-vs-runpod-외부)

**Part 4. 트래픽 인입 및 보안 통제**

12. [Ingress — 외부 트래픽 진입](#12-ingress--외부-트래픽-진입)
13. [Service 노출 전략](#13-service-노출-전략)
14. [TLS 종료 지점](#14-tls-종료-지점)
15. [NetworkPolicy — Pod 간 통신 제어](#15-networkpolicy--pod-간-통신-제어)

---
16. [설계 결정 요약](#16-설계-결정-요약)
17. [비용 비교](#17-비용-비교)
18. [장애 대응 & Failover](#18-장애-대응--failover)
19. [부록](#19-부록)

---

## Part 0. 서론

## 1. K8S 전환 필요성

### 현재 인프라의 한계 (서비스 관점)

4단계 Docker 컨테이너화를 통해 배포 표준화와 환경 일관성은 확보했지만, 서비스가 성장하면서 **운영 복잡도가 한계에 도달**하고 있습니다.

#### 1. VM 기반 장애 복구 지연이 야기하는 비즈니스 리스크 및 신뢰성 개선
- 현재 컨테이너가 비정상 종료되면 docker-compose의 `restart: unless-stopped` 정책에 의존하지만, EC2/VM 인스턴스 자체 장애 시 ASG/MIG가 이를 감지하고 새 인스턴스를 프로비저닝하여 서비스에 투입하기까지 **수 분의 공백**이 발생합니다.
- 도장콕의 핵심 가치는 부동산 계약 현장에서 **사용자의 안전한 의사결정을 실시간으로 지원**하는 것입니다. 특히 부동산 거래가 활발한 **주간(09~21시)에 수 분간의 서비스 장애가 발생할 경우**, 사용자가 AI의 검토 없이 치명적인 계약 리스크를 떠안게 되는 **금전적·정신적 피해로 직결**될 수 있습니다.
- K8S의 자동 복구(Self-Healing) 체계는 인스턴스 장애 시 이미 확보된 유휴 노드 자원에 즉각적으로 Pod를 재스케줄링하여 **복구 시간을 초 단위로 단축**함으로써 이 비즈니스 리스크를 근본적으로 해소합니다.

#### 2. 멀티 클라우드 아키텍처로 인한 인적 리소스 한계
- 초기 인프라 비용 최적화를 위해 서비스 영역(AWS)과 AI 워크로드 영역(GCP)을 이원화했으나, 스프린트를 거듭하며 각 클라우드의 운영이 고도화되면서 **팀원 간 상대 클라우드에 대한 이해도 격차**가 벌어졌습니다.
- 실제로 상대편이 구성한 Terraform 모듈이나 배포 설정의 의도를 충분히 이해하지 못한 상태에서 IaC 작업을 진행하다 **설정 오류가 발생**하거나, GCP 담당자 부재 시 **Spot 인스턴스 선점에 즉각 대응하지 못하는** 상황이 반복되었습니다.
- AWS CodeDeploy와 GCP MIG라는 **두 개의 배포 파이프라인**, IAM/WIF 권한 체계, Terraform State가 모두 이원화되어 있어, 한쪽 담당자가 빠지면 **장애 복구나 인프라 변경이 지연**되는 구조적 문제가 고착되었습니다.
- 이를 AWS 기반의 단일 K8S 클러스터로 통합하면 모든 워크로드의 배포 명세가 **K8S 매니페스트라는 단일 배포 형식으로 통일**됩니다. 파편화된 CI/CD 파이프라인이 하나로 합쳐지고, 모든 팀원이 동일한 도구와 방식으로 배포·운영할 수 있어 **누구든 전체 인프라를 동일하게 다룰 수 있는 체계**를 확보할 수 있습니다.

#### 3. 1서비스 1인스턴스 구조로 인한 리소스 비효율
- 현재 FE, BE, AI-Server가 각각 별도의 VM에 1대씩 할당되어 있습니다. 이로 인해 각 서비스마다 개별 OS와 백그라운드 에이전트(모니터링, 로그 수집 등)가 중복으로 구동되어야 하는 **구조적 리소스 오버헤드** 가 발생하고 있습니다.
- K8S를 도입하면 다수의 서비스를 소수의 워커 노드에 고집적하여 배치함으로써 **OS 단위의 중복 오버헤드를 제거** 하고, 노드 자원을 서비스 간 효율적으로 공유할 수 있습니다.

---

## 2. 대안 비교 및 kubeadm 선택 근거

### EKS vs kubeadm

AWS가 컨트롤 플레인을 관리해주는 **EKS**와, EC2 위에 직접 클러스터를 구성하는 **kubeadm** 중 어떤 방식이 도장콕 팀의 현재 상황에 적합한지 비교합니다.

| 항목 | EKS (관리형) | kubeadm (자체 구축) |
|------|------------|-------------------|
| **컨트롤 플레인 비용** | **월 $73** (관리형 서비스 요금, CP EC2 불필요) | **월 ~$30** (서비스 요금 $0, CP용 EC2 직접 운영) |
| **컨트롤 플레인 관리** | AWS가 관리 (etcd, apiserver 등) | 직접 관리 |
| **클러스터 업그레이드** | 콘솔/CLI 원클릭 | `kubeadm upgrade` 수동 |
| **AWS 서비스 통합** | 네이티브 (IAM, ALB Controller 등) | 직접 구성 |
| **운영 자립도** | AWS 지원 의존 (내부 추상화) | **K8S 내부 아키텍처 직접 이해** |
| **CNI 선택** | VPC CNI 권장 (다른 CNI 설정 복잡) | **자유 선택** (본 설계에서는 Calico 채택) |
| **인증서 관리** | AWS 관리 | 직접 관리 (kubeadm 자동 생성) |

#### kubeadm을 선택한 이유

**1. 비용**
- EKS는 컨트롤 플레인 관리형 서비스 요금으로 **월 ~$73**이 고정 발생합니다(CP용 EC2를 별도로 띄울 필요는 없음). kubeadm은 이 서비스 요금 대신 CP용 EC2(t4g.medium, **월 ~$30**)를 직접 운영하므로, **월 ~$43 절감**됩니다.

**2. 내부 트러블슈팅 역량 확보**
- EKS는 컨트롤 플레인을 추상화하여 장애 발생 시 내부 동작을 이해하지 못한 채 AWS 지원에 의존해야 합니다.
- kubeadm으로 직접 구축하면 etcd, kube-apiserver, kube-scheduler, controller-manager의 **동작 원리와 인증서 체계를 체득**할 수 있어, 장애 시 **팀 자체적으로 진단·복구가 가능**하며, 향후 EKS/GKE 전환 시에도 트러블슈팅 역량의 기반이 됩니다.

**3. 커스터마이징**
- CNI, Gateway API 컨트롤러, 스토리지 프로비저너를 팀의 요구에 맞춰 **자유롭게 선택**할 수 있습니다.
- kubeadm은 **K8S 공식 부트스트랩 도구**로, 공식 문서와 커뮤니티 리소스가 가장 풍부합니다.


#### kubeadm의 명확한 단점과 감수/대응 근거

kubeadm을 통한 직접 구축(Self-hosted)은 EKS(관리형) 대비 비용과 운영 자립도 측면에서 명확한 장점이 있지만, 다음과 같은 운영상의 리스크가 존재하며 이를 단계적이고 현실적인 방법으로 통제할 계획입니다.

**단점 1: 컨트롤 플레인(Control Plane) 직접 운영 부담**
- **위험성**: EKS를 사용하면 AWS가 무중단으로 관리해 주는 마스터 노드(API 서버, etcd 등)를 직접 유지보수해야 하므로, 장애 시 클러스터 제어권을 잃을 수 있습니다.
- **대응 방안**: 초기에는 아키텍처 단순화를 위해 마스터 노드를 1대(단일 구성)로 운영합니다. 단일 CP 장애 시 클러스터 제어권(스케줄링, 배포)은 일시 상실되지만, 워커 노드에 이미 배포된 서비스(Data Plane)는 정상 작동하여 사용자 트래픽에 즉각적인 중단은 발생하지 않습니다. 또한 클러스터 상태 데이터가 저장되는 etcd의 스냅샷 백업을 자동화하여, 최악의 노드 장애 시에도 수 분 내에 제어권을 원상 복구할 수 있는 최소한의 안전장치를 마련합니다.

**단점 2: 수동 버전 업그레이드의 번거로움**
- **위험성**: 클라우드 콘솔에서 클릭으로 끝나는 관리형 서비스와 달리, 새로운 버전이 나올 때마다 관리자가 직접 노드별로 접속해 명령어(`kubeadm upgrade`)를 치며 수동으로 업데이트해야 합니다.
- **대응 방안**: 수백 대의 노드를 굴리는 엔터프라이즈 환경에서는 부담스럽지만, 도장콕의 초기 인프라 규모(노드 5대(CP 1 + Worker 4))에서는 롤링 업데이트 방식으로 다운타임 없이 30분 내외로 작업이 가능하므로 팀의 현재 운영 리소스로 충분히 감당할 수 있습니다.

**단점 3: AWS 네이티브 서비스 연동(Cloud Provider)의 수동 구성**
- **위험성**: EKS에서는 자동으로 지원되는 AWS 자원 연동(ALB 동적 생성, Pod별 IAM 권한 부여 등)을 kubeadm 환경에서는 엔지니어가 직접 복잡한 설정(AWS Cloud Provider, IRSA 구축 등)을 통해 구현해야 합니다.
- **대응 방안**: 초기에는 K8S가 AWS 자원을 직접 제어하게 만드는 복잡한 연동을 배제하고, 역할을 명확히 분리하는 직관적인 방식으로 우회합니다.
  - **트래픽 인입 (ALB 정적 매핑 + 차세대 Gateway API)**: K8S 내부에서 ALB를 동적 생성하는 AWS Load Balancer Controller 대신, 인프라(ALB/NLB)는 기존처럼 Terraform으로 고정 생성합니다. K8S 내부에는 지원 종료가 예정된 구형 Nginx Ingress 대신 NGINX Gateway Fabric(Gateway API 컨트롤러)을 띄우고 이를 NodePort로 노출시킨 뒤, 외부의 AWS 타겟 그룹(Target Group)이 이 EC2 노드포트를 바라보게 하는 정적 매핑 방식을 채택합니다.
  - **IAM 권한 할당 (스토리지 연동)**: K8S 내부의 DB 파드가 AWS EBS 볼륨을 동적으로 생성(EBS CSI Driver)하거나 ECR에서 이미지를 풀(Pull)할 때 권한이 필요합니다. OIDC를 직접 구축하여 파드 단위로 세밀하게 권한을 부여(IRSA)하는 대신, 워커 노드(EC2) 자체에 IAM Instance Profile로 통권(AmazonEBSCSIDriverPolicy 등)을 부여하여 권한 관리 및 스토리지 연동의 복잡도를 대폭 낮춥니다. (향후 보안 요건 강화 시 세분화 검토)


---


## Part 1. 컴퓨팅 자원 및 노드 토폴로지

## 3. 워크로드 분석과 리소스 산정

K8S 전환 시 다수의 서비스를 소수의 Worker 노드에 고집적 배치하므로, 각 서비스의 실제 리소스 사용량을 파악하는 것이 노드 사이징의 출발점입니다.

### V2 인프라 현황

현재 V2에서는 FE, BE, MySQL, Redis, RabbitMQ가 각각 별도 AWS EC2 인스턴스에서, AI Server가 GCP VM에서 운영되고 있습니다. 1서비스 1VM 구조로 각 인스턴스에 OS·Docker·모니터링 에이전트 오버헤드가 중복되며, 워크로드 대비 리소스가 과잉 할당된 상태입니다.

| 서비스 | 인스턴스 | vCPU | RAM | 클라우드 |
|--------|---------|------|-----|---------|
| FE (Next.js) | t4g.small | 2 | 1.8GB | AWS |
| BE (Spring Boot) | t4g.small | 2 | 1.8GB | AWS |
| MySQL | t4g.medium | 2 | 3.7GB | AWS |
| Redis | t4g.small | 2 | 1.8GB | AWS |
| RabbitMQ | t4g.small | 2 | 1.8GB | AWS |
| AI Server (FastAPI) | n2d-standard-2 | 2 | 7.8GB | GCP |

> 상세 사양 및 디스크: [node-sizing.md](./node-sizing.md) 참조

### 실측 데이터와 핵심 관찰

Prometheus + Grafana를 통해 현재 활성 인스턴스(3일)와 ASG 전체 인스턴스 이력(30일)의 CPU·메모리를 수집했습니다.

- **BE/FE**: 평균 CPU 2~4%로 매우 낮지만, ASG 역대 피크가 **BE 90.3%, FE 92.8%**에 달합니다. T시리즈 CPU 크레딧이 거의 0까지 소진된 이력이 확인되어, 간헐적이지만 극심한 버스트가 존재합니다.
- **DB/Redis/RabbitMQ**: 평균 1~2%, 피크 3% 이내로 안정적인 워크로드 패턴입니다.
- **AI Server**: 평균 ~2%, 피크 11%. vLLM 추론은 RunPod에서 처리하고 오케스트레이션만 담당하므로 CPU 부담이 낮습니다.

> 상세 수치(CPU·메모리·디스크): [node-sizing.md](./node-sizing.md) 참조

### 데이터의 한계와 보완 계획

위 실측은 **Dev 저트래픽 환경**(실 사용자 없음, 내부 테스트)에서 수집된 것으로, Prod 부하와는 차이가 있을 수 있습니다. MongoDB와 ChromaDB는 V3에서 신규 추가되어 실측 데이터 자체가 없습니다.

이 한계를 인지한 상태에서, 다음 2단계로 보완합니다.

1. **사전 검증**: K8S 전환 전 도커 컨테이너 기반 부하테스트를 통해 Prod 수준의 트래픽을 인가하고 Request/Limit을 1차 보정합니다.
2. **운영 최적화**: Prod 전환 후 Prometheus/Grafana로 수집된 프로덕션 메트릭과 HPA 스케일링 트렌드를 분석하여 점진적으로 최적화합니다.

### 초기 리소스 산정 (잠정)

위 한계를 전제로, 초기 서비스 오픈 시 트래픽 변동성을 안전하게 흡수하기 위해 **보수적으로** 산정합니다. 실측 데이터와 서비스 특성(데이터 정합성, API 지연 허용치 등)을 종합적으로 고려했으며, 부하테스트 완료 후 전면 재조정할 예정입니다.

| 서비스 | 실측 근거 | CPU Req | CPU Lim | RAM Req | RAM Lim |
|--------|----------|---------|---------|---------|---------|
| FE | avg 0.037v, peak 1.86v, RSS ~400MB | 250m | 1500m | 512MB | 1GB |
| BE | avg 0.072v, peak 1.81v, JVM RSS ~900MB | 500m | 2000m | 1GB | 2GB |
| AI Server | avg ~0.04v, peak 0.23v, RSS 221MB | 200m | 500m | 512MB | 1GB |
| MySQL | avg 0.024v, peak 0.063v, BP 128→512MB | 200m | 500m | 1GB | 2GB |
| MongoDB (신규) | 실측 없음, 보수적 추정 | 150m | 500m | 512MB | 1GB |
| Redis | avg 0.014v, data 1.4MB | 100m | 250m | 256MB | 512MB |
| RabbitMQ | avg 0.024v, Erlang 135MB | 100m | 250m | 256MB | 512MB |
| ChromaDB | 실측 없음, 벡터 인덱스 | 200m | 500m | 768MB | 1.5GB |

> 잠정 산정. 부하테스트 후 Request/Limit 재조정 예정. 상세 산정 근거: [node-sizing.md](./node-sizing.md)

### 워크로드 합산

위 Request에 복제본 수를 곱한 Prod 워크로드 합산입니다.

| 서비스 | Prod 인스턴스 | 배포 방식 |
|--------|-------------|----------|
| FE | 2 | Deployment (anti-affinity) |
| BE | 2 | Deployment (anti-affinity) |
| AI Server | 1 | Deployment |
| MySQL | 1 Primary + 1 Replica | StatefulSet |
| MongoDB | 1 Primary + 1 Secondary + 1 Arbiter | StatefulSet + Deployment |
| Redis | 1 Master + 1 Replica + 3 Sentinel | StatefulSet + Deployment |
| RabbitMQ | 1 | Deployment |
| ChromaDB | 1 | Deployment |

**시나리오 A — Prod 단일 (HA 미적용)**

| 카테고리 | 구성 | CPU Request | RAM Request |
|----------|------|-------------|-------------|
| App | FE×2, BE×2, AI×1 | 1700m | 3.54GB |
| DB (단일) | MySQL, MongoDB, Redis | 450m | 1.77GB |
| Infra | RabbitMQ, ChromaDB | 300m | 1.02GB |
| **워크로드 소계** | | **2450m** | **6.33GB** |
| 공유 컴포넌트 (잠정) | Gateway Fabric, ArgoCD, Prometheus, Grafana, Alloy 등 | ~850m | ~1.7GB |
| **Prod 합계** | | **~3300m** | **~8.0GB** |

**시나리오 B — Prod HA (채택)**

| 카테고리 | 구성 | CPU Request | RAM Request |
|----------|------|-------------|-------------|
| **App** | FE×2, BE×2, AI×1 | 1700m | 3.54GB |
| **DB Primary** | MySQL, MongoDB, Redis | 450m | 1.77GB |
| **DB Replica** | MySQL Replica, MongoDB Secondary, Redis Replica | 450m | 1.77GB |
| **Quorum** | MongoDB Arbiter, Redis Sentinel×3 | 200m | 0.26GB |
| **Infra** | RabbitMQ, ChromaDB | 300m | 1.02GB |
| **워크로드 소계** | | **3100m** | **8.35GB** |
| 공유 컴포넌트 (잠정) | Gateway Fabric, ArgoCD, Prometheus, Grafana, Alloy 등 | ~850m | ~1.7GB |
| **Prod 합계** | | **~3950m** | **~10.0GB** |

**HPA 스케일아웃 시나리오**

FE/BE에 HPA를 적용하여 트래픽 급증 시 자동 확장할 경우의 리소스 증가입니다.

| 시나리오 | 추가 CPU | 추가 RAM | Prod 합계 |
|----------|---------|---------|----------|
| 기본 HA (FE×2, BE×2) | — | — | ~3950m |
| FE +1 (→3대) | +250m | +512MB | ~4200m |
| BE +1 (→3대) | +500m | +1GB | ~4450m |
| FE+BE 각 +1 | +750m | +1.5GB | ~4700m |

> HPA maxReplicas는 Worker allocatable 여유에 따라 결정하며, 섹션 4에서 노드 구성별 HPA 수용 범위를 비교합니다.

---

## 4. 노드 사이징 — CP와 Worker

섹션 3에서 산출한 Prod HA 워크로드(~3950m)와 HPA 스케일아웃 시(최대 ~4700m)를 수용할 클러스터 노드를 선정합니다. T시리즈 CPU 크레딧 고갈이 실측으로 확인되었고(BE 90.3%, FE 92.8%), 실측 데이터가 Dev 저트래픽 기준이라 Prod 부하는 더 높을 수 있으므로, **비용 대비 충분한 HPA 확장 여유**를 확보하는 것이 핵심입니다.

### Control Plane — t4g.medium

kubeadm Control Plane 구성요소의 리소스 합산입니다.

| 컴포넌트 | CPU | RAM |
|---------|-----|-----|
| etcd | ~0.5v | ~500MB |
| kube-apiserver | ~0.5v | ~500MB |
| kube-scheduler | ~0.1v | ~100MB |
| kube-controller-manager | ~0.1v | ~200MB |
| kubelet + OS | ~0.3v | ~500MB |
| **합계** | **~1.5v** | **~1.8GB** |

**t4g.medium (2vCPU, 4GB)** 을 선택합니다. kubeadm 최소 요구(2vCPU, 2GB)를 충족하며, 여유 2.2GB로 etcd 스냅샷 작업 등에 활용 가능합니다. 단일 CP 운영의 장애 대응은 섹션 2(kubeadm 선택 근거, 단점 1)에서 논의하였습니다.

### Worker — t4g.large × 4

Prod HA(~3950m) 기준과 HPA 풀스케일(~4700m) 시를 고려하여 네 가지 구성을 비교했습니다.

| 옵션 | Alloc CPU | Alloc RAM | 월비용 | HA 활용률 | HPA 풀(FE+BE +1) |
|------|----------|----------|--------|----------|---------|
| t4g.large × 3 | 4.5v | 19.5GB | $147 | 88% | ✗ (104%) |
| **t4g.large × 4** | **6.0v** | **26.0GB** | **$196** | **66%** | **78%** |
| t4g.xlarge × 2 | 7.0v | 29.0GB | $196 | 56% | 67% |
| t4g.xlarge × 3 | 10.5v | 43.5GB | $294 | 38% | 45% |

**t4g.large × 4** 가 xlarge × 2와 **동일 비용($196)** 이면서, 평시 HA 활용률 66%로 HPA 스케일아웃(FE+BE 각 1대 추가) 시에도 78%로 수용 가능합니다. 노드 4대이면 **AZ 2:2 균등 배치** 가 가능하고, RAM 활용률 38%로 InnoDB Buffer Pool 증설이나 MongoDB 데이터 증가에도 충분합니다.

> **결정: CP t4g.medium × 1 + Worker t4g.large × 4 (2vCPU, 8GB) — Prod 전용. xlarge×2와 동일 비용이면서 HPA 확장 여유(78%) + AZ 균등 배치 가능**

이 구성에서 감수하는 리스크는 다음과 같습니다.

| 리스크 | 영향 | 대응 |
|--------|------|------|
| **노드당 alloc 1.5v** — BE Pod의 CPU Limit(2000m)이 노드 allocatable(1500m) 초과 | 버스트 시 CPU throttle 발생 가능 | 실측 피크(1.8v)는 순간적. 대부분의 시간은 Request(500m) 이하. Limit을 1500m으로 조정하거나 throttle 감수 |
| **실측이 Dev 저트래픽 기준** — Prod 부하가 예상보다 높을 수 있음 | Request 합산이 allocatable 초과 시 Pod Pending | 운영 안정화 후 실측 기반 Request 재조정. 부족 시 xlarge로 스케일업 |
| **T시리즈 CPU 크레딧 고갈** — 버스트 워크로드(BE/FE)가 지속되면 크레딧 소진 | 크레딧 소진 후 기본 성능(40%)으로 제한 | Prometheus로 Credit Balance 모니터링 + 알람. 고갈 시 Unlimited Mode 활성화 또는 m6g.large 교체(+$18/대) |
| **HPA 풀스케일 시 78%** — FE+BE 동시 +1 시 여유 22% | 추가 확장 여지 제한 | HPA maxReplicas 제한(FE 3, BE 3). 상시 80%+ 시 W5 추가 |

스케일업 경로도 열어두었습니다.

| 조건 | 대응 |
|------|------|
| CPU 일상 80%+ | t4g.xlarge로 교체 (4vCPU, 16GB, ~$98/대) |
| 크레딧 반복 고갈 | m6g.large로 교체 (고정 성능, ~$67/대) |
| Worker 수 부족 | W5 추가 ($49/대) |

---

## 5. AZ 배치 — 노드별 워크로드 배분

노드 사이징(섹션 4)에서 결정한 **CP 1대 + Worker 4대** 를 ap-northeast-2의 2개 AZ(2a, 2c)에 어떻게 배분할지가 핵심입니다. 고려해야 할 제약은 세 가지입니다.
- 첫째, StatefulSet의 EBS는 AZ에 종속되므로 **같은 AZ에 Worker 2대 이상** 이 있어야 노드 장애 시 재스케줄링이 가능합니다.
- 둘째, DB HA 채택 시 Primary/Replica는 서로 다른 AZ에 배치해야 AZ 장애에 대비할 수 있습니다(섹션 10에서 논의 중).
- 셋째, DB HA 채택 시 Quorum 과반이 Primary 반대 AZ에 있어야 자동 선출이 보장됩니다(섹션 10에서 논의 중).

1:3이나 3:1 배치는 한쪽 AZ에 Worker가 1대뿐이라 재스케줄링이 불가능합니다. **2:2 균등 배치** (AZ 2a에 CP+W1+W2, AZ 2c에 W3+W4)만이 양쪽 AZ 모두에서 Worker 2대씩을 확보하여, 어느 AZ에서든 노드 1대 장애 시 같은 AZ의 나머지 노드로 재스케줄링할 수 있습니다. DB Primary/Replica를 AZ 분리 배치하여 AZ 장애 시 데이터를 보존하고, FE/BE는 Anti-Affinity로 AZ에 분산하여 어느 AZ가 다운되어도 서비스를 유지합니다.

단일 Control Plane(2a) 장애 시, 클러스터 제어권(스케줄링, 배포)은 일시 상실되나 기존 Worker 노드(2a, 2c)에 배포된 Data Plane(FE, BE 파드 및 라우팅 룰)은 정상 작동하여 **사용자 서비스 중단은 발생하지 않습니다** . CP 복구는 S3에 자동화된 etcd 스냅샷을 통해 수행합니다(섹션 2 "kubeadm 선택 근거" 단점 1 참조).

> **결정: 2:2 균등 배치 — AZ 2a(CP+W1+W2), AZ 2c(W3+W4). 양쪽 AZ 모두 재스케줄링 가능**

---


## Part 2. 클러스터 내부 네트워크망

## 6. CNI 선택

kubeadm은 EKS처럼 CNI가 기본 내장되어 있지 않아 별도 설치가 필요합니다. CNI는 Pod 네트워크의 기반으로, 이후 모든 네트워크 설계에 영향을 미칩니다. 특히 V2에서 프라이빗 서브넷 분리 + 보안그룹으로 확보했던 네트워크 격리를 K8S에서도 유지해야 하는데, K8S는 기본적으로 모든 Pod이 같은 클러스터 네트워크에 존재하므로 **격리 수단이 필수**입니다.

후보는 세 가지였습니다. **Flannel**은 설치가 가장 간단하고 가볍지만 NetworkPolicy를 지원하지 않아 별도 솔루션을 추가해야 합니다. **Cilium**은 eBPF 기반 고성능에 L7 정책과 Observability가 내장되어 있지만, 커널 5.10+ 요구와 에이전트당 ~300MB 오버헤드(4대 × 300MB = 1.2GB), 러닝커브가 소규모 팀에 부담입니다. **Calico**는 CNI + NetworkPolicy를 **하나의 컴포넌트**로 제공하며, kubeadm + Calico 조합의 레퍼런스가 압도적으로 많아 트러블슈팅이 용이합니다.

V2의 보안그룹 격리를 K8S의 NetworkPolicy로 계승하는 것이 핵심 요구이므로, 이를 단일 컴포넌트로 충족하는 Calico를 선택했습니다.

> **결정: Calico — CNI + NetworkPolicy 단일 컴포넌트, kubeadm 레퍼런스 최다**

---

## 7. 네트워크 대역 — Pod CIDR, Service CIDR

kubeadm init 시 Pod CIDR과 Service CIDR을 지정해야 하며, VPC 대역과 겹치면 라우팅 충돌이 발생합니다. 신규 VPC 대역은 다음과 같습니다.

| 구분 | 대역 | 범위 |
|------|------|------|
| VPC | 10.10.0.0/18 | 10.10.0.0 ~ 10.10.63.255 |
| 2a public | 10.10.0.0/24 | 10.10.0.0 ~ 10.10.0.255 |
| 2a private | 10.10.4.0/22 | 10.10.4.0 ~ 10.10.7.255 |
| 2c public | 10.10.1.0/24 | 10.10.1.0 ~ 10.10.1.255 |
| 2c private | 10.10.8.0/22 | 10.10.8.0 ~ 10.10.11.255 |

K8S 내부 대역은 kubeadm과 Calico의 기본값을 그대로 사용합니다.

| 대역 | CIDR | 범위 | 출처 |
|------|------|------|------|
| Pod CIDR | 192.168.0.0/16 | 192.168.0.0 ~ 192.168.255.255 | Calico 기본값 |
| Service CIDR | 10.96.0.0/12 | 10.96.0.0 ~ 10.111.255.255 | kubeadm 기본값 |

VPC(10.10.0.0/18), Pod(192.168.0.0/16), Service(10.96.0.0/12) 세 대역이 완전히 분리되어 충돌이 없고, Pod/Service CIDR은 K8S 내부 가상 네트워크로 AWS 인프라에 노출되지 않습니다. 기본값은 kubeadm + Calico 레퍼런스에서 가장 검증된 조합이므로 별도 커스터마이징 없이 채택합니다.

> **결정: kubeadm/Calico 기본값 사용 — VPC 대역과 충돌 없음**

---

## 8. 외부 통신 — NAT, RunPod 호출 경로

Worker 노드가 private 서브넷에 있으므로 외부 통신에 NAT가 필요합니다. 외부 호출 대상은 RunPod API(vLLM), ECR 이미지 풀, 외부 API(OCR 등)입니다.

**NAT Gateway**(월 ~$32 + 데이터)는 AWS 관리형으로 자동 고가용성을 제공하지만 비용이 높습니다. **NAT Instance × 1**(월 ~$3.8)은 저비용이며 V2에서 운영 경험이 있지만, AZ 배치(섹션 5)에서 결정한 2:2 배치와 **논리적으로 상충**합니다. NAT Instance가 2a에만 있을 때 2a AZ 장애가 발생하면, 2c에 살아남은 Worker(W3, W4)가 인터넷 출구를 잃어 RunPod API 호출·ECR 이미지 풀·HPA 스케일아웃이 모두 불가능해지므로, 2:2 배치로 확보한 고가용성이 무의미해집니다.

이를 해결하기 위해 **NAT Instance × 2를 AZ별로 배치**하고, **라우팅 테이블을 AZ별로 분리**합니다. 각 AZ의 private 서브넷이 자기 AZ의 NAT Instance만 바라보도록 구성하면, 한쪽 AZ가 다운되어도 반대쪽 AZ는 독립적인 인터넷 출구를 유지합니다. 추가 비용은 월 ~$3.8(t4g.nano 1대)에 불과합니다.

| 구성 | AZ 2a | AZ 2c | 월비용 | AZ 장애 시 |
|------|-------|-------|--------|-----------|
| NAT Instance × 1 | NAT-a | - | ~$3.8 | 2a 장애 → 전체 외부 통신 불가 |
| **NAT Instance × 2** | **NAT-a** | **NAT-c** | **~$7.6** | **각 AZ 독립 — 반대쪽 정상** |
| NAT Gateway | 관리형 | 관리형 | ~$64+ | 자동 HA |

> **결정: NAT Instance × 2 (t4g.nano, AZ별 배치) — 라우팅 테이블 분리로 AZ 독립 인터넷 출구 확보. 2:2 배치 철학과 일치. 월 +$3.8 추가**

---


## Part 3. 데이터 및 특수 워크로드 전략

## 9. DB 배치 — K8S 내부 vs 외부

V2에서 MySQL은 EC2 단독 인스턴스(t4g.medium)로, Redis와 RabbitMQ도 각각 별도 EC2에서 운영 중입니다. 전부 단일 인스턴스에 HA가 없어 장애 시 수동 복구가 필요한 상황입니다. K8S 전환 시 무중단 마이그레이션 과정에서 Standby/Replica가 추가되어 자연스럽게 HA 구성이 이루어지며, V3 스프린트 기간 동안 채팅 데이터 저장을 위해 MongoDB가 신규 추가됩니다. 대상 DB는 MySQL, MongoDB, Redis, RabbitMQ, ChromaDB 입니다.

관리형 DB(RDS 등)는 4종 전부 적용 시 비용 과다이므로 제외하고, **K8S StatefulSet(옵션 A)** 과 **EC2 외부 유지(옵션 B)** 두 가지를 비교합니다.

**옵션 A(K8S StatefulSet)** 는 kubectl 하나로 App+DB를 통합 관리할 수 있고, YAML로 HA 토폴로지를 코드화(Git 버전 관리)하며, DB 전용 EC2를 제거하여 비용을 절감할 수 있습니다. 반면 K8S CP 장애 시 DB Failover 스케줄링이 불가하고, EBS가 AZ에 종속되어 해당 AZ Worker 전멸 시 Pod Pending이 발생하며, App과 DB 간 CPU/메모리 경합(Limit으로 방어하나 완벽하지 않음), StatefulSet 운영 난이도(삭제/스케일링 순서 중요), 백업 파이프라인 직접 구축(CronJob → dump → S3), DB 메이저 업그레이드 직접 관리 등의 리스크가 있습니다.

**옵션 B(EC2 외부 유지)** 는 K8S 장애와 DB가 완전히 분리되어 DB 전용 리소스가 보장(경합 없음)되고, 기존 운영 방식을 유지(변경 최소)할 수 있으며, apt upgrade로 간단한 DB 업그레이드가 가능합니다. 반면 VM을 별도로 관리(SSH, 패치, 모니터링 이원화)해야 하고, DB 전용 EC2 추가 비용(Replica 포함 시 인스턴스 수 증가), K8S 매니페스트 + EC2 관리 이원화로 인한 운영 복잡도 증가, HA 구성을 EC2 레벨에서 직접 해야 하는(Keepalived 등) 부담이 있습니다.

핵심 쟁점은 **"K8S에 DB까지 통합하여 운영 단일화를 추구할 것인가, DB는 분리하여 장애 격리를 확보할 것인가"** 입니다.

> **결정: *(논의 필요)* — 옵션 A(통합 관리)와 옵션 B(장애 격리) 간 팀 논의 후 결정**

---

## 10. DB HA 토폴로지

V2에서는 모든 DB가 단일 인스턴스로 운영되어, 장애 시 서비스 전체가 중단됩니다. K8S 전환 시 무중단 마이그레이션 과정에서 Replica가 추가되어 자연스럽게 2 AZ 배치가 이루어지는데, 이때 **MySQL, MongoDB, Redis 각각의 HA 메커니즘이 다르다**는 점이 핵심 고민입니다.

HA 구성 시 Replica와 Quorum 노드로 인해 리소스가 증가하므로, 노드 사이징(섹션 4)에서 결정한 t4g.large × 4의 여유분으로 수용 가능한지가 중요합니다. 또한 팀의 K8S StatefulSet 운영 경험이 부족하고, RabbitMQ와 ChromaDB는 자체 HA 구성이 복잡하거나 미지원이라는 제약이 있습니다.

아래에 DB별 선택지를 정리합니다.

#### MySQL

| 옵션 | 구성 | Failover | 추가 리소스 | 장점 | 단점 |
|------|------|----------|-----------|------|------|
| A. 단일 | Primary 1 | - | 없음 | 단순, 리소스 절약 | 장애 시 서비스 중단, 데이터 유실 위험 |
| B. 수동 Failover | Primary + Replica | 수동 promote | +200m, +1GB | Replica에서 읽기 분산 가능, 데이터 안전 | 장애 시 운영자가 직접 promote 필요 (새벽 장애 시 대응 지연) |
| C. 자동 Failover | Primary + Replica + Orchestrator/ProxySQL | 자동 | +200m, +1GB + Orchestrator ~100m/256MB | 무인 자동 복구 | 추가 컴포넌트(Orchestrator) 학습/운영 비용, 복잡도 증가 |

> **MySQL은 자체 자동 Failover 메커니즘이 없음** — 자동화하려면 MySQL Orchestrator, ProxySQL, 또는 MySQL Group Replication 등 별도 구성 필요.
> Group Replication은 최소 3노드 권장이라 리소스 부담 큼. Orchestrator는 가볍지만 추가 학습 필요.

#### MongoDB

| 옵션 | 구성 | Failover | 추가 리소스 | 장점 | 단점 |
|------|------|----------|-----------|------|------|
| A. 단일 | Standalone 1 | - | 없음 | 단순 | 장애 시 채팅 데이터 유실 위험 |
| B. ReplicaSet (3멤버) | Primary + Secondary + Arbiter | **자동** (내장) | +150m/512MB + Arbiter 50m/64MB | 자동 선출, 읽기 분산, oplog 기반 복구 | Arbiter 포함 최소 3멤버 필요 |
| C. ReplicaSet (2멤버) | Primary + Secondary | **자동 불가** (과반 미달) | +150m/512MB | Arbiter 없이 간단 | 2멤버로는 과반 확보 불가 → Primary 다운 시 자동 선출 안 됨 |

> **MongoDB ReplicaSet은 과반(majority) 투표로 Primary를 선출**. 2멤버로는 과반 확보 불가능하므로, 자동 Failover를 원하면 **최소 3멤버**(Arbiter 포함)가 필요.
> Arbiter는 데이터를 저장하지 않으므로 리소스 부담 최소 (50m CPU, 64MB RAM).

#### Redis

| 옵션 | 구성 | Failover | 추가 리소스 | 장점 | 단점 |
|------|------|----------|-----------|------|------|
| A. 단일 | Master 1 | - | 없음 | 단순 | 장애 시 세션/캐시 유실 |
| B. Sentinel | Master + Replica + Sentinel×3 | **자동** (Sentinel 선출) | +100m/256MB + Sentinel 150m/192MB | 자동 Failover, 검증된 구성 | Sentinel 3대 필요 (과반 투표), 총 5 Pod |
| C. Redis Cluster | 최소 6노드 (3 Master + 3 Replica) | **자동** (내장) | 큼 | 수평 확장, 샤딩 | 현재 규모에 과잉, 복잡도 높음 |

> **Sentinel도 과반 투표** — 최소 3대 필요. Sentinel Pod는 매우 가벼움 (50m/64MB 각).
> Redis Cluster는 데이터 샤딩이 필요한 규모가 아니면 과잉.
> Redis 데이터가 유실되어도 **세션/캐시 재생성 가능**하다면 단일로 시작하는 것도 선택지.

#### RabbitMQ

| 옵션 | 구성 | Failover | 추가 리소스 | 장점 | 단점 |
|------|------|----------|-----------|------|------|
| A. 단일 | Standalone 1 | - | 없음 | 단순, 현행과 동일 | 장애 시 미처리 메시지 유실 |
| B. Quorum Queue | 3노드 클러스터 | **자동** (Raft) | +200m/512MB × 2 | 메시지 유실 방지, 자동 복구 | 리소스 3배, Erlang 클러스터 운영 복잡 |

> **RabbitMQ HA 비용이 높음** — Quorum Queue는 최소 3노드. 현재 AI 요청/응답 메시지 처리 용도에서 메시지 유실 시 **재요청으로 복구 가능**한지가 판단 기준.
> 유실 감수 가능하면 단일로 충분. 유실 불가면 Quorum Queue 필요.

#### ChromaDB

| 옵션 | 구성 | Failover | 추가 리소스 | 장점 | 단점 |
|------|------|----------|-----------|------|------|
| A. 단일 | Standalone 1 | - | 없음 | 단순 | 장애 시 벡터 검색 불가 |
| B. PVC 백업 + 재구축 | 단일 + CronJob 스냅샷 | 수동 (PVC 복원) | 스냅샷 스토리지 | 데이터 보존 | 복구 시간 발생 (분 단위) |

> **ChromaDB는 자체 HA 미지원**. 벡터 인덱스는 원본 문서에서 재구축 가능하므로, PVC Retain + 정기 백업이 현실적 대안.

조합별 리소스 영향을 비교하면 다음과 같습니다.

| 조합 | 추가 CPU | 추가 RAM | 비고 |
|------|---------|---------|------|
| 전부 단일 (A) | 0 | 0 | 장애 시 서비스 중단 감수 |
| MySQL 수동 + Mongo RS + Redis Sentinel + RMQ/Chroma 단일 | 800m | 2.3GB | Failover: Mongo/Redis 자동, MySQL 수동 |
| MySQL 자동 + Mongo RS + Redis Sentinel + RMQ/Chroma 단일 | 900m | 2.6GB | 전부 자동 Failover (MySQL에 Orchestrator 추가) |
| 전부 HA (Quorum Queue 포함) | 1300m | 3.6GB | 최대 안전, 최대 복잡도 |

현재 Prod alloc 여유는 CPU 6000m - 3300m(워크로드+공유) = **2700m**으로, 어떤 조합이든 리소스는 수용 가능합니다. 핵심 쟁점은 **서비스별 HA 수준을 어디까지 가져갈 것인가**(자동 Failover vs 수동 Failover vs 단일)와 **Quorum 구성의 복잡도를 팀이 감당할 수 있는가**입니다.

> **결정: *(논의 필요)* — DB별 HA 수준과 Quorum 구성 팀 논의 후 결정**

---

## 11. GPU 워크로드 — K8S 내부 vs RunPod 외부

vLLM(EXAONE-3.5-7.8B) 추론에는 최소 L4 24GB 이상의 GPU가 필수입니다. 이상적으로는 K8S 클러스터 내에 GPU 노드풀을 두어 통합 관리하는 것이 좋겠지만, **AWS GPU 인스턴스 할당 요청이 지속적으로 반려** 되고 있어 현실적으로 선택지가 없습니다.

섹션 1에서 기술한 단일 클라우드(AWS) 통합에 따라, **GPU만 RunPod으로 외부 위임** 합니다. AI Server(FastAPI)는 K8S 내부에서 오케스트레이터로 동작하며, vLLM에 HTTPS API 요청을 보내는 구조입니다. 

향후 AWS GPU 할당이 승인되면 K8S GPU 노드풀을 추가하여 클러스터 내부로 전환하는 경로를 열어둡니다.

> **결정: RunPod 외부 + API 요청 방식 — AWS GPU 할당 반려로 외부 위임, 추후 전환 검토**

---


## Part 4. 트래픽 인입 및 보안 통제

## 12. Ingress — 외부 트래픽 진입

V2에서는 AWS ALB가 FE/BE로 직접 라우팅했지만, K8S에서는 Ingress Controller(또는 Gateway API 구현체)가 필요합니다. 기존에 널리 쓰이던 NGINX Ingress Controller가 **2026년 3월 지원 종료**되므로 신규 도입이 불가합니다.

후보는 네 가지였습니다. **AWS ALB Controller**는 ALB 네이티브 연동이 가능하지만, kubeadm 환경에서는 IRSA가 없어 credential을 별도로 주입해야 하고 Gateway API를 미지원하여 클라우드 락인됩니다. **Cilium Gateway** 는 CNI 선택에서 Calico를 채택했으므로 제외됩니다. **Envoy Gateway** 는 Rate Limiting 네이티브 지원과 CNCF 프로젝트라는 장점이 있지만, Envoy 러닝커브와 레퍼런스 부족이 우려됩니다. **NGINX Gateway Fabric** 은 30년간 검증된 NGINX 엔진 위에 Gateway API 공식 구현체로 구축되어 있으며, 상대적으로 신규이고 고급 기능(Rate Limiting 등)이 미지원이지만 현재 요구사항에는 충분합니다.

NGINX Ingress Controller 지원 종료에 대응하여 차세대 **Gateway API 표준** 으로 전환하되, Envoy 대비 NGINX 엔진의 레퍼런스와 안정성 우위를 고려하여 NGINX Gateway Fabric을 선택했습니다. 트래픽은 앞단 AWS ALB(인프라 LB) → NodePort → NGINX Gateway Fabric 구조로 연결됩니다.

> **결정: NGINX Gateway Fabric — Gateway API 표준 + 검증된 NGINX 엔진**

---

## 13. Service 노출 전략

kubeadm에는 LoadBalancer 타입 자동 프로비저닝이 없으므로(EKS와 다름), 외부 트래픽을 클러스터 내부로 어떻게 전달할지 직접 설계해야 합니다. 내부 전용 서비스(AI Server, DB, Redis, RabbitMQ, ChromaDB)는 ClusterIP로 확정이고, 외부 접근이 필요한 FE/BE의 노출 방식이 쟁점이었습니다.

| 서비스 | 외부 접근 | 타입 |
|--------|----------|------|
| NGINX Gateway Fabric | O | NodePort |
| FE, BE | X (Gateway 경유) | ClusterIP |
| AI Server, DB, Redis, RabbitMQ, ChromaDB | X | ClusterIP |

Ingress(섹션 12)에서 NGINX Gateway Fabric을 확정한 이상, **모든 외부 트래픽은 Gateway Fabric을 통해서만 진입**하는 구조가 자연스럽습니다. FE/BE를 별도 NodePort로 직접 노출하면 라우팅 룰이 ALB와 Gateway에 이원화되고, Gateway Fabric의 관측성(access log, 메트릭) 이점이 사라집니다.

**옵션 A(Gateway Fabric NodePort 전용 노출)**를 확정합니다.
- **트래픽 경로**: ALB → Gateway Fabric(NodePort) → FE/BE(ClusterIP)
- **보안 은폐**: FE/BE가 ClusterIP로만 노출되어 외부에서 직접 접근 불가
- **라우팅 중앙화**: HTTPRoute 룰을 Gateway Fabric YAML에서 GitOps로 일원 관리
- **관측성**: Gateway Fabric에서 전체 트래픽의 access log, latency 메트릭 수집 가능
- **병목 대응**: Gateway Fabric을 DaemonSet으로 모든 Worker에 배치하여 단일 장애점 제거

> **결정: 옵션 A 확정 — Gateway Fabric NodePort 전용 노출. 보안 은폐(ClusterIP) 및 라우팅 룰 GitOps 관리를 위해 모든 외부 트래픽은 Gateway Fabric을 통해서만 진입**

---

## 14. TLS 종료 지점

외부 → ALB → Gateway Fabric → Pod 경로에서 어디서 HTTPS를 끊을지가 쟁점입니다. **ALB에서 종료**하면 클라이언트→ALB 구간만 HTTPS이고 내부는 HTTP로, ACM 무료 인증서를 활용할 수 있어 설정이 단순합니다. **끝단 암호화**는 ALB→Gateway Fabric 구간까지 HTTPS로 보호하지만, cert-manager를 추가로 관리해야 하여 복잡도가 증가합니다.

V2에서도 ALB TLS 종료로 운영한 전례가 있고, 내부 트래픽은 private 서브넷 안이라 평문이어도 실질적 위험이 낮습니다. ACM 인증서가 무료이므로 cert-manager 없이 운영 가능하며, kubeadm 내부 인증서(API Server, etcd 등)는 kubeadm이 자동 생성/갱신합니다.

> **결정: ALB에서 TLS 종료 — V2와 동일, 내부 HTTP. ACM 무료 인증서 활용**

---

## 15. NetworkPolicy — Pod 간 통신 제어

K8S 기본 상태에서는 모든 Pod이 모든 Pod과 통신할 수 있는 flat network입니다. V2에서는 보안그룹(기본 Deny + 허용 룰)으로 트래픽 방향을 제어했으므로, K8S에서도 동일한 보안 수준을 유지해야 합니다.

접근 방식은 세 가지를 검토했습니다. "DB만 보호"는 App 간 통신을 제어하지 못하고, "추후 적용"은 보안 공백이 생깁니다. V2 보안그룹이 기본 Deny였으므로, K8S에서도 **Default Deny + Whitelist**(전체 차단 후 필요한 통신만 허용)를 적용하여 동일한 보안 수준을 유지합니다. 정책 수가 많아지고 새 서비스 추가 시 정책도 추가해야 하지만, CNI 선택(섹션 6)에서 채택한 Calico가 NetworkPolicy를 기본 지원하므로 추가 컴포넌트 없이 구현 가능합니다.

공통 필수 정책(우선순위순)은 다음과 같습니다.

| # | 룰 | 방향 | 대상 | 빠뜨리면 |
|---|-----|------|------|---------|
| 1 | 모든 Pod → kube-dns (UDP 53) | Egress | 전체 | 서비스 이름 해석 불가, 전체 장애 |
| 2 | Gateway Fabric → FE/BE | Ingress | FE, BE | 외부 접속 502/504 |
| 3 | 외부 인터넷 (0.0.0.0/0) | Egress | AI Server 등 | RunPod API, ECR 풀 불가 |

이 공통 필수 정책 3개를 먼저 적용한 뒤, 아래 서비스 간 통신 맵에 따라 개별 허용합니다.

```
FE        → BE
BE        → MySQL, MongoDB, Redis, RabbitMQ, AI Server
AI Server → ChromaDB, 외부(RunPod)
RabbitMQ  ↔ BE, AI Server (양방향)
DB 간      → Primary ↔ Replica (HA 복제)
```

> **결정: Default Deny + Whitelist — V2 보안그룹과 동일한 기본 차단 + 허용 방식**

---

## 16. 설계 결정 요약

### 확정 사항

| Q | 주제 | 결정 | 한줄 근거 |
|---|------|------|----------|
| Q3 | GPU | RunPod 외부 (API 방식) | AWS GPU 할당 반려, 비용 절감 |
| Q4 | 노드 사이징 | t4g.large × 4 + CP t4g.medium × 1 | 실측 기반, HPA 확장 여유(78%), 2:2 AZ 균등 |
| Q6 | AZ 배치 | 2a(CP+W1+W2) / 2c(W3+W4) | Anti-Affinity로 서비스 분산 |
| Q7 | 리소스 산정 | 실측 기반 Request/Limit, 부하테스트 후 재조정 | 저트래픽 실측의 한계 인지, 운영 중 조정 전제 |
| Q8 | CNI | Calico | V2 보안그룹 → NetworkPolicy 계승, 단일 컴포넌트 |
| Q9 | 네트워크 대역 | Pod 192.168.0.0/16, Service 10.96.0.0/12 (기본값) | VPC(10.10.0.0/18)와 충돌 없음 |
| Q10 | Ingress | NGINX Gateway Fabric (Gateway API) | NGINX Ingress Controller 지원 종료, 차세대 표준 |
| Q11 | Service 노출 | Gateway Fabric NodePort 전용 노출 | Q10과 일관 — 라우팅 중앙화, 보안 은폐 |
| Q12 | 외부 통신 | NAT Instance × 2 (t4g.nano, AZ별) | 2:2 AZ 배치와 일치, 월 +$3.8 |
| Q13 | NetworkPolicy | Default Deny + Whitelist | V2 보안그룹과 동일한 기본 차단 방식 |
| Q14 | TLS | ALB에서 종료, 내부 HTTP | V2와 동일, private 서브넷 내부 평문 허용 |

### 논의 필요

| Q | 주제 | 선택지 | 쟁점 |
|---|------|--------|------|
| Q2 | DB 위치 | StatefulSet vs EC2 | HA 필요성 vs 운영 복잡도 |
| Q5 | DB HA 토폴로지 | DB별 Primary-Replica 구성 | 서비스별 HA 수준, Quorum 구성 |

### 인프라 구성 요약

**VPC**: 10.10.0.0/18 (ap-northeast-2)

| AZ | public | private | 노드 |
|----|--------|---------|------|
| 2a | 10.10.0.0/24 | 10.10.4.0/22 | CP, W1, W2 |
| 2c | 10.10.1.0/24 | 10.10.8.0/22 | W3, W4 |

**트래픽 흐름**: 클라이언트 → ALB (TLS 종료) → NGINX Gateway Fabric (NodePort) → Pod (ClusterIP)

**외부 통신**: Pod → NAT Instance (t4g.nano × 2, AZ별) → RunPod API / ECR / 외부 API

**네트워크 보안**: Calico NetworkPolicy (Default Deny) + 공통 필수 정책 (kube-dns, Gateway→App, 외부 Egress)

### 비용

V2 Prod과 비슷한 비용(~$296~311/월)에 서비스 이중화 + 단일 클라우드 통합. 상세: [cost-comparison.md](./cost-comparison.md)

---

## 17. 비용 비교

*(전체 Q 결정 후 작성. 상세: [cost-comparison.md](./cost-comparison.md))*

---

## 18. 장애 대응 & Failover

*(전체 Q 결정 후 작성)*

---

## 19. 부록

*(Q1~Q7 결정 후 작성 — YAML 예시 등)*

---

## 변경 이력

| 버전 | 날짜 | 변경 내용 |
|------|------|----------|
| v1.0.0 | 2026-03-02 | 초안: kubeadm 오케스트레이션 설계 전문 |
| v1.1.0 | 2026-03-03 | 구조 변경: 섹션 3~14를 Q&A 기반으로 재구성, Q1 결정 완료 |
| v1.2.0 | 2026-03-04 | Q1~Q14 섹션 서술형 재작성, 섹션 1·2 확정 내용 반영, Q1 "Prod 전용" 수정 |
| v1.3.0 | 2026-03-04 | 구조 개편: 설계 질문 목록·Q1 클러스터 전략 삭제, Part 1~4 그룹핑, 섹션 재배치, QX: 접두사 제거 |
| v1.4.0 | 2026-03-04 | NAT Instance AZ별 이중화(C안), Service 노출 옵션 A 확정, CP SPOF 방어 논리 추가 |
| v1.5.0 | 2026-03-03 | Part 1 재구성: §3 워크로드 분석(V2 현황+실측+산정)→§4 노드 사이징(CP 추가)→§5 AZ 배치. N-1 제거, HPA 스케일아웃 시나리오 추가 |
| **v1.5.1** | **2026-03-04** | §3: Tier 가중치 표/Peak 공식 제거(부하테스트 후 재산정), 공유 컴포넌트 구성 일치(잠정 표기). §5: DB HA 미확정 반영(둘째·셋째 조건부 표현). |
