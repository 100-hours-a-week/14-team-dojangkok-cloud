# 5단계: Kubeadm 오케스트레이션 (v3.0.0)

- 작성일: 2026-03-02
- 최종수정일: 2026-03-08

## 개요

**도장콕**은 임차인의 부동산 임대 계약 과정(계약 전·계약 중)을 지원하는 서비스다.
핵심 기능: 쉬운 계약서(해설+리스크 검증) | 집노트(답사/비교/체크리스트) | 임대 매물 커뮤니티

**본 문서**: 4단계(Docker 컨테이너화)까지 구축된 멀티 클라우드(AWS+GCP) 인프라를 **AWS 단일 클라우드 + kubeadm 기반 Kubernetes 클러스터**로 전환하는 오케스트레이션 설계를 다룬다. 컨테이너 단위로 격리된 서비스를 Kubernetes 워크로드로 전환하여, 선언적 배포 관리·자동 복구·수평 확장을 확보하고 운영 복잡도를 줄이는 것이 목표다.

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

**Part 3. 배포 및 데이터 전략**

9. [애플리케이션(Stateless) 배포 및 스케줄링](#9-애플리케이션stateless-배포-및-스케줄링)
10. [영구 스토리지 전략 — PV/PVC, CSI Driver, StorageClass](#10-영구-스토리지-전략--pvpvc-csi-driver-storageclass)
11. [Stateful 배치 전략 — 단계적 전환](#11-stateful-배치-전략--단계적-전환)
12. [DB HA 토폴로지](#12-db-ha-토폴로지)
13. [GPU 워크로드 — K8S 내부 vs RunPod 외부](#13-gpu-워크로드--k8s-내부-vs-runpod-외부)

**Part 4. 트래픽 인입 및 보안 통제**

14. [Ingress — 외부 트래픽 진입](#14-ingress--외부-트래픽-진입)
15. [Service 노출 전략](#15-service-노출-전략)
16. [TLS 종료 지점](#16-tls-종료-지점)
17. [Namespace 설계](#17-namespace-설계)
18. [NetworkPolicy — Pod 간 통신 제어](#18-networkpolicy--pod-간-통신-제어)
19. [RBAC/SA — K8S API 접근 제어](#19-rbacsa--k8s-api-접근-제어)

---
20. [설계 결정 요약](#20-설계-결정-요약)
21. [비용 비교](#21-비용-비교)
22. [장애 대응 & Failover](#22-장애-대응--failover)
23. [부록](#23-부록)

---

## Part 0. 서론

## 1. K8S 전환 필요성

### 현재 인프라의 한계 (서비스 관점)

4단계 Docker 컨테이너화를 통해 배포 표준화와 환경 일관성은 확보했지만, 서비스가 성장하면서 **운영 복잡도가 한계에 도달**하고 있다.

#### 1. VM 기반 장애 복구 지연이 야기하는 비즈니스 리스크 및 신뢰성 개선
- 현재 FE/BE 등 일부 서비스는 ASG/MIG를 통해 인스턴스 단위 복구를 지원하지만, 인스턴스 장애 감지 후 새 VM을 프로비저닝하여 서비스에 투입하기까지 **수 분의 공백**이 발생한다. 더 심각한 것은 **MySQL, Redis, RabbitMQ 등 ASG가 적용되지 않은 단일 EC2 기반의 코어 인프라**로, 이들 노드에 장애가 발생할 경우 관리자의 수동 개입 전까지 서비스 전체가 마비되는 치명적인 취약점을 안고 있다.
- 도장콕의 핵심 가치는 부동산 계약 현장에서 **사용자의 안전한 의사결정을 실시간으로 지원**하는 것이다. 특히 부동산 거래가 활발한 **주간(09~21시)에 수 분간의 서비스 장애가 발생할 경우**, 사용자가 AI의 검토 없이 치명적인 계약 리스크를 떠안게 되는 **금전적·정신적 피해로 직결**될 수 있다.
- K8S의 자동 복구(Self-Healing) 체계는 ASG/MIG 적용 여부와 무관하게 클러스터 내 모든 워크로드(App, DB 등)의 상태를 중앙에서 주기적으로 감시한다. 노드나 파드 장애 시 이미 확보된 워커 노드 자원에 즉각적으로 파드를 재스케줄링하여 **복구 시간을 수초 내외로 단축** 하고, 기존의 수동 복구에 의존하던 단일 서비스들까지 자동 복구 대상에 포함시킴으로써 우리 서비스의 신뢰도 향상을 기대할 수 있다.

#### 2. 멀티 클라우드 아키텍처로 인한 인적 리소스 한계
- 초기 인프라 비용 최적화를 위해 서비스 영역(AWS)과 AI 워크로드 영역(GCP)을 이원화했으나, 스프린트를 거듭하며 각 클라우드의 운영이 고도화되면서 **팀원 간 상대 클라우드에 대한 이해도 격차**가 벌어졌다.
- 실제로 상대편이 구성한 Terraform 모듈이나 배포 설정의 의도를 충분히 이해하지 못한 상태에서 IaC 작업을 진행하다 **설정 오류가 발생**하거나, GCP 담당자 부재 시 **Spot 인스턴스 선점에 즉각 대응하지 못하는** 상황이 반복되었다.
- AWS CodeDeploy와 GCP MIG라는 **두 개의 배포 파이프라인**, IAM/WIF 권한 체계, Terraform State가 모두 이원화되어 있어, 한쪽 담당자가 빠지면 **장애 복구나 인프라 변경이 지연**되는 구조적 문제가 고착되었다.
- 이를 AWS 기반의 단일 K8S 클러스터로 통합하면 모든 워크로드의 배포 명세가 **K8S 매니페스트라는 단일 배포 형식으로 통일**된다. 파편화된 CI/CD 파이프라인이 하나로 합쳐지고, 모든 팀원이 동일한 도구와 방식으로 배포·운영할 수 있어 **누구든 전체 인프라를 동일하게 다룰 수 있는 체계**를 확보할 수 있다.

#### 3. 1서비스 1인스턴스 구조로 인한 리소스 비효율
- 현재 FE, BE, AI-Server가 각각 별도의 VM에 1대씩 할당되어 있다. 이로 인해 각 서비스마다 개별 OS와 백그라운드 에이전트(모니터링, 로그 수집 등)가 중복으로 구동되어야 하는 **구조적 리소스 오버헤드** 가 발생하고 있다.
- K8S를 도입하면 다수의 서비스를 소수의 워커 노드에 고집적하여 배치함으로써 **OS 단위의 중복 오버헤드를 제거** 하고, 노드 자원을 서비스 간 효율적으로 공유할 수 있다.

---

## 2. 대안 비교 및 kubeadm 선택 근거

### EKS vs kubeadm

AWS가 컨트롤 플레인을 관리해주는 **EKS**와, EC2 위에 직접 클러스터를 구성하는 **kubeadm** 중 어떤 방식이 도장콕 팀의 현재 상황에 적합한지 비교한다.

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
- EKS는 컨트롤 플레인 관리형 서비스 요금으로 **월 ~$73**이 고정 발생한다(CP용 EC2를 별도로 띄울 필요는 없음). kubeadm은 이 서비스 요금 대신 CP용 EC2(t4g.medium, **월 ~$30**)를 직접 운영하므로, **월 ~$43 절감**된다.

**2. 내부 트러블슈팅 역량 확보**
- EKS는 컨트롤 플레인을 추상화하여 장애 발생 시 내부 동작을 이해하지 못한 채 AWS 지원에 의존해야 한다.
- kubeadm으로 직접 구축하면 etcd, kube-apiserver, kube-scheduler, controller-manager의 **동작 원리와 인증서 체계를 체득**할 수 있어, 장애 시 **팀 자체적으로 진단·복구가 가능**하며, 향후 EKS/GKE 전환 시에도 트러블슈팅 역량의 기반이 된다.

**3. 커스터마이징**
- CNI, Gateway API 컨트롤러, 스토리지 프로비저너를 팀의 요구에 맞춰 **자유롭게 선택**할 수 있다.
- kubeadm은 **K8S 공식 부트스트랩 도구**로, 공식 문서와 커뮤니티 리소스가 가장 풍부하다.


#### kubeadm의 명확한 단점과 감수/대응 근거

kubeadm을 통한 직접 구축(Self-hosted)은 EKS(관리형) 대비 비용과 운영 자립도 측면에서 명확한 장점이 있지만, 다음과 같은 운영상의 리스크가 존재하며 이를 단계적이고 현실적인 방법으로 통제할 계획이다.

**단점 1: 컨트롤 플레인(Control Plane) 직접 운영 부담**
- **위험성**: EKS를 사용하면 AWS가 무중단으로 관리해 주는 마스터 노드(API 서버, etcd 등)를 직접 유지보수해야 하므로, 장애 시 클러스터 제어권을 잃을 수 있다.
- **대응 방안**: 초기에는 아키텍처 단순화를 위해 마스터 노드를 1대(단일 구성)로 운영한다. 단일 CP 장애 시 클러스터 제어권(스케줄링, 배포)은 일시 상실되지만, 워커 노드에 이미 배포된 서비스(Data Plane)는 정상 작동하여 사용자 트래픽에 즉각적인 중단은 발생하지 않는다. 또한 클러스터 상태 데이터가 저장되는 etcd의 스냅샷 백업을 자동화하여, 최악의 노드 장애 시에도 수 분 내에 제어권을 원상 복구할 수 있는 최소한의 안전장치를 마련한다.

**단점 2: 수동 버전 업그레이드의 번거로움**
- **위험성**: 클라우드 콘솔에서 클릭으로 끝나는 관리형 서비스와 달리, 새로운 버전이 나올 때마다 관리자가 직접 노드별로 접속해 명령어(`kubeadm upgrade`)를 치며 수동으로 업데이트해야 한다.
- **대응 방안**: 수백 대의 노드를 굴리는 엔터프라이즈 환경에서는 부담스럽지만, 도장콕의 초기 인프라 규모(노드 7대(CP 1 + Worker 6), 섹션 4에서 상세 산정)에서는 롤링 업데이트 방식으로 다운타임 없이 30분 내외로 작업이 가능하므로 팀의 현재 운영 리소스로 충분히 감당할 수 있다.

**단점 3: AWS 네이티브 서비스 연동(Cloud Provider)의 수동 구성**
- **위험성**: EKS에서는 자동으로 지원되는 AWS 자원 연동(ALB 동적 생성, Pod별 IAM 권한 부여 등)을 kubeadm 환경에서는 엔지니어가 직접 복잡한 설정(AWS Cloud Provider, IRSA 구축 등)을 통해 구현해야 한다.
- **대응 방안**: 초기에는 K8S가 AWS 자원을 직접 제어하게 만드는 복잡한 연동을 배제하고, 역할을 명확히 분리하는 직관적인 방식으로 우회한다.
  - **트래픽 인입 (ALB 정적 매핑 + 차세대 Gateway API)**: K8S 내부에서 ALB를 동적 생성하는 AWS Load Balancer Controller 대신, 인프라(ALB/NLB)는 기존처럼 Terraform으로 고정 생성한다. K8S 내부에는 지원 종료가 예정된 구형 Nginx Ingress 대신 NGINX Gateway Fabric(Gateway API 컨트롤러)을 띄우고 이를 NodePort로 노출시킨 뒤, 외부의 AWS 타겟 그룹(Target Group)이 이 EC2 노드포트를 바라보게 하는 정적 매핑 방식을 채택한다(Part 4에서 상세 서술).
  - **IAM 권한 할당 (스토리지 연동)**: K8S 내부의 DB 파드가 AWS EBS 볼륨을 동적으로 생성(EBS CSI Driver)하거나 ECR에서 이미지를 풀(Pull)할 때 권한이 필요하다. OIDC를 직접 구축하여 파드 단위로 세밀하게 권한을 부여(IRSA)하는 대신, 워커 노드(EC2) 자체에 IAM Instance Profile로 통권(AmazonEBSCSIDriverPolicy 등)을 부여하여 권한 관리 및 스토리지 연동의 복잡도를 대폭 낮춘다. (향후 보안 요건 강화 시 세분화 검토)


---


## Part 1. 컴퓨팅 자원 및 노드 토폴로지

## 3. 워크로드 분석과 리소스 산정

### V2 인프라 현황

현재 V2에서는 FE, BE, MySQL, Redis, RabbitMQ가 각각 별도 AWS EC2 인스턴스에서, AI Server가 GCP VM에서 운영되고 있다. 1서비스 1VM 구조로 각 인스턴스에 OS·Docker·모니터링 에이전트 오버헤드가 중복되며, 워크로드 대비 리소스가 과잉 할당된 상태다.

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

Prometheus + Grafana를 통해 현재 활성 인스턴스(3일)와 ASG 전체 인스턴스 이력(30일)의 CPU·메모리를 수집했다.

- **BE/FE**: 평균 CPU 2~4%로 매우 낮지만, ASG 역대 피크가 **BE 90.3%, FE 92.8%** 에 달한다. T시리즈 CPU 크레딧이 거의 0까지 소진된 이력이 확인되어, 간헐적이지만 극심한 버스트가 존재한다.
- **DB/Redis/RabbitMQ**: 평균 1~2%, 피크 3% 이내로 안정적인 워크로드 패턴이다.
- **AI Server**: 평균 ~2%, 피크 11%. vLLM 추론은 RunPod에서 처리하고 오케스트레이션만 담당하므로 CPU 부담이 낮다.

**부하테스트 결과 (2026-03-07)**: k6 v1.5.0으로 BE ASG 4대 환경에서 S02(800VU 읽기), S03(400VU CRUD), S05(300VU 체크리스트) 시나리오를 실행했다. **MySQL이 CRUD 시나리오(S03)에서 CPU 83.3% 피크로 주요 병목**으로 식별되었고, BE는 4대 평균 피크 306m(최악 단일 인스턴스 908m). JVM Heap 26%, GC 0.88%로 애플리케이션 레벨 병목 없음이 확인되었다.

> 상세 수치(CPU·메모리·디스크·부하테스트): [node-sizing.md](./node-sizing.md) 참조

### 데이터의 한계와 보완 계획

위 실측은 **Dev 저트래픽 환경**(실 사용자 없음, 내부 테스트)에서 수집된 것이며, 부하테스트(2026-03-07)를 통해 Prod 수준의 트래픽을 인가하여 BE·MySQL의 Request/Limit을 1차 보정하였다. MongoDB와 ChromaDB는 V3에서 신규 추가되어 실측 데이터 자체가 없다.

남은 한계를 인지한 상태에서, **운영 최적화** 단계로 보완한다: Prod 전환 후 Prometheus/Grafana로 수집된 프로덕션 메트릭과 HPA 스케일링 트렌드를 분석하여 점진적으로 최적화한다.

### 리소스 산정 (부하테스트 반영)

저트래픽 실측 + k6 부하테스트(S02/S03/S05) 피크를 기반으로 산정한다. BE, MySQL은 부하테스트 결과로 상향 조정하였다.

| 서비스 | 실측 근거 | CPU Req | CPU Lim | RAM Req | RAM Lim | 변경 |
|--------|----------|---------|---------|---------|---------|------|
| FE | avg 0.037v, peak 1.86v, RSS ~400MB | 250m | 1500m | 512MB | 1GB | — |
| BE | **부하테스트 4대 평균 피크 306m, 최악 908m** | **700m** | **2000m** | 1.5GB | 2GB | **상향** |
| AI Server | avg ~0.04v, peak 0.23v, RSS 221MB | 300m | 1000m | 768MB | 1.5GB | — |
| MySQL | **부하테스트 S03 피크 833m, RAM 1074MB** | **500m** | **1500m** | **1.5GB** | **2.5GB** | **상향** |
| MongoDB (신규) | 실측 없음, 보수적 추정 | 150m | 500m | 512MB | 1GB | — |
| Redis | 부하테스트 spike 14.4%, data 1.4MB | 100m | 256m | 256MB | 512MB | — |
| RabbitMQ | avg 0.024v, Erlang 135MB | 100m | 256m | 256MB | 512MB | — |
| ChromaDB | 실측 없음, 벡터 인덱스 | 200m | 500m | 1GB | 2GB | — |

> BE Request 700m: 4대 평균 피크 306m × 2.3x headroom. MySQL Request 500m: 저트래픽 62m → 부하테스트 833m 급등(CRUD 시나리오). 상세: [node-sizing.md](./node-sizing.md)

### 워크로드 합산

위 Request에 복제본 수를 곱한 Prod 워크로드 합산이다.

| 서비스 | Prod 인스턴스 | 배포 방식 |
|--------|-------------|----------|
| FE | 2 | Deployment (anti-affinity) |
| BE | 2 | Deployment (anti-affinity) |
| AI Server | 1 | Deployment |
| MySQL | 1 Primary + 1 Replica | StatefulSet |
| MongoDB | 1 Primary + 1 Secondary + 1 Arbiter | StatefulSet + Deployment |
| Redis | 1 Master + 1 Replica + 3 Sentinel | StatefulSet + Deployment |
| RabbitMQ | 1 | Deployment (단일) |
| ChromaDB | 1 | Deployment (단일) |

트래픽 인입·배포·관측성을 위해 클러스터 전역에 배포되는 공유 컴포넌트(Gateway Fabric, CD, 모니터링 등)를 포함한 합산이다.

**시나리오 A — Prod 단일 (HA 미적용)**

| 카테고리 | 구성 | CPU Request | RAM Request |
|----------|------|-------------|-------------|
| App | FE×2, BE×2, AI×1 | 2100m | 4.77GB |
| DB (단일) | MySQL, MongoDB, Redis | 750m | 2.25GB |
| Infra | RabbitMQ, ChromaDB | 300m | 1.26GB |
| **워크로드 소계** | | **3150m** | **8.28GB** |
| 공유 컴포넌트 (6노드) | Gateway Fabric, ArgoCD, Prometheus, Grafana, Alloy 등 | ~1050m | ~1.7GB |
| **Prod 합계** | | **~4200m** | **~10.0GB** |

**시나리오 B — Prod HA (채택)**

| 카테고리 | 구성 | CPU Request | RAM Request |
|----------|------|-------------|-------------|
| **App** | FE×2, BE×2, AI×1 | 2100m | 4.77GB |
| **DB Primary** | MySQL, MongoDB, Redis | 750m | 2.25GB |
| **DB Replica** | MySQL Replica, MongoDB Secondary, Redis Replica | 750m | 2.25GB |
| **Quorum** | MongoDB Arbiter, Redis Sentinel×3 | 200m | 0.26GB |
| **Infra** | RabbitMQ, ChromaDB | 300m | 1.26GB |
| **워크로드 소계** | | **4100m** | **10.79GB** |
| 공유 컴포넌트 (6노드) | Gateway Fabric, ArgoCD, Prometheus, Grafana, Alloy 등 | ~1050m | ~1.7GB |
| **Prod 합계** | | **~5150m** | **~12.5GB** |

> HA 추가분: DB Replica(750m/2.25GB) + Quorum(200m/0.26GB) = 950m / 2.51GB.

**HPA 스케일아웃 시나리오**

FE/BE에 HPA를 적용하여 트래픽 급증 시 자동 확장할 경우의 리소스 증가분이다.

| 시나리오 | 추가 CPU | 추가 RAM | Prod 합계 |
|----------|---------|---------|----------|
| 기본 HA (FE×2, BE×2) | — | — | ~5150m |
| FE +1 (→3대) | +250m | +512MB | ~5400m |
| BE +1 (→3대) | +700m | +1.5GB | ~5850m |
| FE+BE 각 +1 | +950m | +2.0GB | ~6100m |

> HPA maxReplicas는 Worker allocatable 여유에 따라 결정. 섹션 4에서 노드 구성별 HPA 수용 범위 비교.

---

## 4. 노드 사이징 — CP와 Worker

섹션 3에서 산출한 Prod HA 워크로드(~5150m)와 HPA 스케일아웃 시(최대 ~6100m)를 수용할 클러스터 노드를 선정한다. k6 부하테스트에서 BE 피크 908m(단일 인스턴스), MySQL 833m이 확인되었고, T시리즈 CPU 크레딧 고갈이 실측으로 확인되었으므로(BE 90.3%, FE 92.8%), **N-1 장애 내성 + HPA 확장 여유** 를 확보하는 것이 핵심이다.

### Control Plane — t4g.medium

kubeadm Control Plane 구성요소의 리소스 합산이다.

| 컴포넌트 | CPU | RAM |
|---------|-----|-----|
| etcd | ~0.5v | ~500MB |
| kube-apiserver | ~0.5v | ~500MB |
| kube-scheduler | ~0.1v | ~100MB |
| kube-controller-manager | ~0.1v | ~200MB |
| kubelet + OS | ~0.3v | ~500MB |
| **합계** | **~1.5v** | **~1.8GB** |

**t4g.medium (2vCPU, 4GB)** 을 선택한다. kubeadm 최소 요구(2vCPU, 2GB)를 충족하며, 여유 2.2GB로 etcd 스냅샷 작업 등에 활용 가능하다. 단일 CP 운영의 장애 대응은 섹션 2(kubeadm 선택 근거, 단점 1)에서 논의하였다.

### Worker — t4g.large × 6 (3-AZ, 2-2-2)

Prod HA(~5150m) 기준으로 3-AZ 균등 배치가 가능한 구성을 비교한다. 부하테스트 반영 후 기존 4대(2-AZ)에서 6대(3-AZ)로 전환하였다.

| 옵션 | AZ 배치 | Alloc CPU | Alloc RAM | 월비용 | HA 활용률 | N-1 (HA) |
|------|---------|-----------|-----------|--------|----------|----------|
| t4g.large × 3 | 1-1-1 | 4.5v | 19.5GB | $147 | ✗ (108%) | ✗ (146%) |
| t4g.large × 4 (구) | 2-2-0 | 6.0v | 26.0GB | $196 | 83% | ✗ (110%) |
| **t4g.large × 6** | **2-2-2** | **9.0v** | **39.0GB** | **$294** | **57%** | **69%** |
| t4g.xlarge × 3 | 1-1-1 | 10.5v | 43.5GB | $294 | 46% | 69% |

- **HA 활용률** = Prod 필요 CPU ÷ Alloc CPU
- **N-1 (HA)** = Prod 필요 CPU ÷ (Alloc CPU − 노드 1대분)
- t4g.large × 4 (구 결론)는 부하테스트 반영 후 N-1 110%로 불가 판정

**t4g.large × 6**과 t4g.xlarge × 3은 동일 비용($294), 동일 N-1(69%)이지만, 6대가 Pod 분산 유연성이 높고(anti-affinity 효과, DB/App 노드 분리 용이), 장애 blast radius가 작다(1/6=17% vs 1/3=33%). 3-AZ 2-2-2 구성으로 **단일 AZ 장애 시 4대(6.0v) 잔여, AZ 장애(2대 손실) 시 83%로 수용 가능**하다.

> **결정: CP t4g.medium × 1 + Worker t4g.large × 6 (2vCPU, 8GB) — 3-AZ 2-2-2. N-1 69%, AZ 장애 83%. 비용 $294/월**
>
> **운영 참고**: Terraform `workers_per_az` 변수로 AZ당 워커 수 조절 가능. 초기 배포는 `workers_per_az = 1` (1-1-1, 3대)로 시작, 안정화 후 2로 스케일업.

이 구성에서 감수하는 리스크는 다음과 같다.

| 리스크 | 영향 | 완화 방안 |
|--------|------|----------|
| **6대 운영 오버헤드** — 관리 복잡도 증가 | 노드 장애 대응 횟수 증가 가능 | EKS 관리형 노드그룹으로 자동화 |
| **노드당 alloc 1.5v** — BE Pod의 CPU Limit(2000m)이 노드 allocatable(1500m) 초과 | 버스트 시 CPU throttle 발생 가능 | 실측 피크(908m)는 k6 keep-alive 편중. 대부분의 시간은 Request(700m) 이하. throttle 감수 |
| **T시리즈 CPU 크레딧** — t4g.large baseline 30%(600m) | 크레딧 소진 시 throttling | Unlimited 모드 기본 활성 + CloudWatch CPUCreditBalance 알림. 6대 분산으로 노드당 부하 감소 |
| **비용 증가 ($196→$294)** — +50% | 예산 초과 가능 | 부하테스트 결과 불가피. 운영 안정 후 노드 축소 검토 |

---

## 5. AZ 배치 — 노드별 워크로드 배분

노드 사이징(섹션 4)에서 결정한 **CP 1대 + Worker 6대** 를 ap-northeast-2의 3개 AZ(2a, 2b, 2c)에 어떻게 배분할지가 핵심이다. 고려해야 할 제약은 세 가지다.
- 첫째, StatefulSet의 EBS는 AZ에 종속되므로 **같은 AZ에 Worker 2대 이상**이 있어야 노드 장애 시 재스케줄링이 가능하다.
- 둘째, DB HA(§12)에서 Stateful 워크로드를 **3-AZ(2a/2b/2c) 독립 EC2**로 분산 배치하여 AZ 장애 시에도 과반(Majority)을 유지한다. K8S Worker의 AZ 배치와는 독립적이다.

**2-2-2 균등 배치** (AZ 2a에 CP+W1+W2, AZ 2b에 W3+W4, AZ 2c에 W5+W6)가 3개 AZ 모두에서 Worker 2대씩을 확보하여, 어느 AZ에서든 노드 1대 장애 시 같은 AZ의 나머지 노드로 재스케줄링할 수 있다. 단일 AZ 장애(2대 손실) 시에도 나머지 4대(6.0v)로 Prod HA 워크로드(~5150m)의 83%를 수용 가능하다. FE/BE는 Anti-Affinity로 AZ에 분산하여 어느 AZ가 다운되어도 서비스를 유지한다.

단일 Control Plane(2a) 장애 시, 클러스터 제어권(스케줄링, 배포)은 일시 상실되나 기존 Worker 노드(2a, 2b, 2c)에 배포된 Data Plane(FE, BE 파드 및 라우팅 룰)은 정상 작동하여 **사용자 서비스 중단은 발생하지 않는다** . CP 복구는 S3에 자동화된 etcd 스냅샷을 통해 수행한다(섹션 2 "kubeadm 선택 근거" 단점 1 참조).

> **결정: 3-AZ 2-2-2 균등 배치 — AZ 2a(CP+W1+W2), AZ 2b(W3+W4), AZ 2c(W5+W6). N-1 69%, AZ 장애 83%**

---


## Part 2. 클러스터 내부 네트워크망

## 6. CNI 선택

kubeadm은 EKS와 달리 CNI가 기본 내장되어 있지 않아 별도 설치가 필요하다. CNI는 Pod 네트워크의 기반으로, 이후 모든 네트워크 설계(대역, 캡슐화, NetworkPolicy)에 영향을 미친다. K8S는 기본적으로 모든 Pod이 같은 flat network에 존재하므로, V2에서 프라이빗 서브넷 분리 + 보안그룹으로 확보했던 네트워크 격리를 K8S에서도 유지하려면 **NetworkPolicy를 지원하는 CNI가 필수**이다.

### CNI 후보 비교

| 후보 | 장점 | 단점 |
|------|------|------|
| **Flannel** | 설치 간단, 가벼움 | NetworkPolicy 미지원 → 별도 솔루션 필요 |
| **Cilium** | eBPF 기반 고성능, L7 정책, Observability 내장 | 커널 5.10+ 요구, 에이전트당 ~300MB(6대 1.8GB), 러닝커브 |
| **Calico** | CNI + NetworkPolicy 단일 컴포넌트, kubeadm 레퍼런스 최다 | Cilium 대비 L7 정책 미지원 |

V2의 보안그룹 격리를 K8S NetworkPolicy로 계승하는 것이 핵심 요구이므로, 이를 단일 컴포넌트로 충족하며 kubeadm과의 조합 레퍼런스가 가장 풍부한 **Calico**를 선택한다.

### Calico Encapsulation 모드

Calico 선택 후 다음 결정은 **Pod 간 트래픽을 어떻게 전달할 것인가**다. Calico는 세 가지 encapsulation 모드를 제공한다.

| 모드 | 동작 | 패킷 오버헤드 | AWS 적합성 |
|------|------|-------------|-----------|
| **None (Direct)** | BGP로 라우팅, 캡슐화 없음 | 0 | ✗ — AWS VPC는 외부 BGP 피어링 미지원 |
| **IPIP** | IP-in-IP 터널링 (L3) | ~20B/pkt | △ — 동작하나 eBPF 데이터플레인 호환 제한 |
| **VXLAN** | UDP 기반 L2 오버레이 | ~50B/pkt | ✓ — AWS 멀티 AZ 환경 권장, eBPF 최적화 |

AWS VPC 환경에서 BGP 피어링이 불가하므로 None(Direct)은 제외된다. IPIP와 VXLAN은 모두 동작하지만, VXLAN이 BGP 메시를 필요로 하지 않고 향후 eBPF 데이터플레인 전환 시 호환성이 우수하다. 따라서 **VXLAN**을 선택한다. 모든 Pod 트래픽이 UDP 기반 L2 오버레이로 캡슐화되며, 패킷당 ~50B(실질 ~2-3%) 수준의 오버헤드가 발생한다.

### AWS 인프라 요구사항

VXLAN 운용에 필요한 AWS 측 설정이다.

| 설정 | 이유 |
|------|------|
| EC2 Source/Dest Check 비활성화 | Pod IP가 노드 ENI IP와 불일치 → 비활성화해야 Pod 트래픽 통과 |
| Security Group: 노드 간 UDP 4789 허용 | VXLAN 캡슐화 포트 |
| VPC 라우팅 테이블 변경 | **불필요** — VXLAN 오버레이가 VPC 라우팅 위에서 동작 |

AWS VPC는 점보 프레임(MTU 9001)을 지원하지만, Calico VXLAN 기본 MTU는 1450으로 설정된다. VXLAN 헤더(50B)를 고려하여 `veth_mtu=8951`(9001−50)로 튜닝해야 VPC 대역폭을 최대한 활용할 수 있다. calico-config ConfigMap에서 설정한다.

> **결정: Calico + VXLAN — CNI+NetworkPolicy 단일 컴포넌트, 모든 Pod 트래픽 VXLAN 캡슐화. AWS source/dest check 비활성화, veth_mtu=8951 튜닝 필요**


---

## 7. 네트워크 대역 — Pod CIDR, Service CIDR

섹션 6에서 Calico(VXLAN)를 선택했다. kubeadm init 시 Calico가 사용할 Pod CIDR과 Service CIDR을 지정해야 하며, VPC 대역과 겹치면 라우팅 충돌이 발생한다. 신규 VPC 대역은 다음과 같다.

| 구분 | 대역 | 범위 |
|------|------|------|
| VPC | 10.10.0.0/18 | 10.10.0.0 ~ 10.10.63.255 |
| 2a public | 10.10.0.0/24 | 10.10.0.0 ~ 10.10.0.255 |
| 2a private (K8S) | 10.10.4.0/22 | 10.10.4.0 ~ 10.10.7.255 |
| 2b public | 10.10.2.0/24 | 10.10.2.0 ~ 10.10.2.255 |
| 2b private (K8S) | 10.10.12.0/22 | 10.10.12.0 ~ 10.10.15.255 |
| 2c public | 10.10.1.0/24 | 10.10.1.0 ~ 10.10.1.255 |
| 2c private (K8S) | 10.10.8.0/22 | 10.10.8.0 ~ 10.10.11.255 |
| 2a/2b/2c private (Data) | 별도 할당 예정 | §12 DB HA EC2 전용, 부하테스트 후 CIDR 확정 |

K8S 내부 대역은 kubeadm과 Calico의 기본값을 그대로 사용한다.

| 대역 | CIDR | 범위 | 출처 |
|------|------|------|------|
| Pod CIDR | 192.168.0.0/16 | 192.168.0.0 ~ 192.168.255.255 | Calico 기본값 |
| Service CIDR | 10.96.0.0/12 | 10.96.0.0 ~ 10.111.255.255 | kubeadm 기본값 |

VPC(10.10.0.0/18), Pod(192.168.0.0/16), Service(10.96.0.0/12) 세 대역이 완전히 분리되어 충돌이 없고, Pod/Service CIDR은 K8S 내부 가상 네트워크로 AWS 인프라에 노출되지 않는다. 기본값은 kubeadm + Calico 레퍼런스에서 가장 검증된 조합이므로 별도 커스터마이징 없이 채택한다.

> **결정: kubeadm/Calico 기본값 사용 — VPC 대역과 충돌 없음**

### kube-proxy 모드 (iptables vs IPVS)

Service의 트래픽 라우팅을 담당하는 kube-proxy는 Kubeadm의 기본값인 **iptables**를 사용한다. 노드 7개(Worker 6개)와 Service 수십 개 이내의 초기 클러스터 규모에서는 iptables 룰 순차 탐색으로 인한 성능 병목(O(N) 탐색)이 거의 발생하지 않는다. 도입 초기의 복잡도를 낮추기 위해 커널 모듈 추가 작업이 필요한 IPVS(O(1) 해시 테이블)는 추후 대규모 트래픽 발생이나 서비스 개수가 폭증할 때 전환을 검토한다.

> **결정: iptables (Kubeadm 기본값 유지) — 초기 클러스터 규모상 성능 오버헤드 미미, 운영 단순화**


---

## 8. 외부 통신 — NAT, RunPod 호출 경로

섹션 6~7에서 클러스터 내부 네트워크를 설계했다. Worker 노드는 private 서브넷에 있으므로, 외부(RunPod API, ECR, 외부 API)와 통신하려면 NAT가 필요하다. 외부로 나가는 트래픽은 두 가지 경로가 있다.

- **Pod → 외부** (RunPod API, 외부 API 호출 등): Pod(192.168.x.x)가 외부 요청 시 Calico가 IP Masquerade(SNAT)로 Pod IP를 Worker 노드 IP(10.10.x.x)로 변환한 뒤, NAT Instance를 거쳐 인터넷으로 나간다.
- **Worker 노드 → 외부** (ECR 이미지 풀, OS 업데이트, kubelet 등): 노드 프로세스가 Worker IP로 직접 NAT Instance를 거쳐 인터넷으로 나간다.

두 경로 모두 최종적으로 NAT Instance를 통과하므로, NAT의 가용성이 곧 외부 통신 전체의 가용성을 결정한다.

**NAT Gateway**(월 ~$32 + 데이터)는 AWS 관리형으로 자동 고가용성을 제공하지만 비용이 높다.
<br> **NAT Instance × 1**(월 ~$3.8)은 저비용이며 V2에서 운영 경험이 있지만, AZ 배치(섹션 5)에서 결정한 3-AZ 2-2-2 배치와 **논리적으로 상충** 한다. <br>NAT Instance가 2a에만 있을 때 2a AZ 장애가 발생하면, 2b·2c에 살아남은 Worker(W3~W6)가 인터넷 출구를 잃어 RunPod API 호출·ECR 이미지 풀·HPA 스케일아웃이 모두 불가능해지므로, 3-AZ 배치로 확보한 고가용성이 무의미해진다.

이를 해결하기 위해 **NAT Instance × 3을 AZ별로 배치**하고, **라우팅 테이블을 AZ별로 분리**한다. 각 AZ의 private 서브넷이 자기 AZ의 NAT Instance만 바라보도록 구성하면, 한쪽 AZ가 다운되어도 나머지 AZ는 독립적인 인터넷 출구를 유지한다. 추가 비용은 월 ~$7.6(t4g.nano 2대 추가)이다.

| 구성 | AZ 2a | AZ 2b | AZ 2c | 월비용 | AZ 장애 시 |
|------|-------|-------|-------|--------|-----------|
| NAT Instance × 1 | NAT-a | - | - | ~$3.8 | 2a 장애 → 전체 외부 통신 불가 |
| **NAT Instance × 3** | **NAT-a** | **NAT-b** | **NAT-c** | **~$11.4** | **각 AZ 독립 — 나머지 정상** |
| NAT Gateway | 관리형 | 관리형 | 관리형 | ~$96+ | 자동 HA |

NAT Instance는 AZ별로 배치하여 AZ 장애에 대비하지만, AZ는 정상인데 EC2 자체가 하드웨어 결함으로 중단될 수 있다. 이 경우 해당 AZ의 외부 통신이 수동 복구까지 마비된다. 이를 방지하기 위해 각 NAT Instance를 **ASG(Min=1, Max=1)**로 래핑한다. EC2 장애 시 ASG가 헬스체크 실패를 감지하여 자동으로 대체 인스턴스를 프로비저닝하므로, 추가 비용 없이 인스턴스 수준 HA를 확보한다.

> **결정: NAT Instance × 3 (t4g.nano, AZ별 ASG Min=1/Max=1) — 3-AZ 독립 + 인스턴스 자동 복구. 라우팅 테이블 AZ별 분리. 월 ~$11.4**

> **운영 노트 (k8s-dev 환경)**: dev에서는 비용 최적화를 위해 **NAT × 1 (ASG Min=1/Max=1, multi-AZ 서브넷)**로 운영한다. 모든 AZ의 private RT가 단일 NAT를 가리키며, cross-AZ 트래픽 비용(~$0.01/GB)은 dev 트래픽 수준에서 무시 가능하다. ASG가 multi-AZ 서브넷을 가지므로 NAT가 있는 AZ 장애 시 다른 AZ에 자동 재생성된다. prod 전환 시 원안(NAT × 3, AZ별 분리)을 적용한다.

---


## Part 3. 배포 및 데이터 전략

## 9. 애플리케이션(Stateless) 배포 및 스케줄링

데이터베이스나 GPU 같은 특수 워크로드 외에, 실제 비즈니스 로직을 처리하는 핵심 애플리케이션(FE, BE, AI Server)이 클러스터 내에서 어떻게 배포되고 고가용성을 유지할지 설계한다. 이들은 상태를 저장하지 않는(Stateless) 특성을 가지며, K8S의 표준 `Deployment` 컨트롤러를 통해 관리된다.

### 배포 컨트롤러와 HPA (Horizontal Pod Autoscaler)

BE와 FE는 트래픽 변동에 대비해 `Deployment` 리소스로 정의하며, CPU/Memory 메트릭 기반의 `HPA(Horizontal Pod Autoscaler)`를 연결한다. AI Server는 메시지 큐(RabbitMQ) 기반의 비동기 처리 구조이므로 우선 단일 리플리카로 시작하여 필요 시 외부 메트릭(큐 대기열 길이) 기반으로 한 수평 확장을 고려한다.

### 고가용성을 위한 Pod Anti-Affinity (AZ 분산)

섹션 5에서 Worker 노드를 2a(W1, W2), 2b(W3, W4), 2c(W5, W6)로 3-AZ 2-2-2 균등 배치했다. 파드가 우연히 단일 AZ 노드로만 몰려서 AZ 장애 시 서비스가 중단되는 것을 막기 위해 **Pod Anti-Affinity**를 설정한다.

*   `topologyKey: topology.kubernetes.io/zone` (AZ 기준)
*   **Preferred vs Required**: 엄격한 분산(`RequiredDuringScheduling...`)을 걸면, 한쪽 AZ의 가용 자원이 부족할 때 HPA로 인한 스케일아웃이 실패(Pending)할 수 있다. 이 때문에 **선호(`PreferredDuringScheduling...`) 조건**을 부여하여 가급적 서로 다른 AZ에 배치되도록 유도하되, 자원 부족 시 남은 AZ 노드라도 사용하여 배포되도록 유연성을 확보한다.

### 무중단 배포 전략 (Rolling Update)

V2에서는 서비스당 단일 인스턴스로 운영되어, 배포 시 해당 인스턴스를 중단하고 새 버전으로 교체하는 동안 다운타임이 불가피했다. K8S 전환 시 다음과 같이 Deployment의 롤링 업데이트 룰을 정의하여 재배포 시 1초의 다운타임도 없애 목표 서비스 신뢰도를 달성한다.

*   `maxUnavailable: 0` (또는 25% 이내) — 이전 버전의 파드를 함부로 죽이지 않고 최소 가용성을 보장.
*   `maxSurge: 1` (또는 25% 이상) — 새 버전 파드를 띄울 컴퓨팅 여유분을 확보(Worker 리소스 여유가 여기서 빛을 발함).
*   **Graceful Shutdown & Readiness Probe**: BE(Spring)와 FE(Next.js)가 완전히 부팅되고 트래픽을 받을 준비가 될 때까지 ALB(Gateway)에 붙이지 않도록 `Readiness Probe`를 깐깐하게 설정한다. 더불어 컨테이너 종료(SIGTERM) 시 처리 중이던 클라이언트 요청이나 DB 트랜잭션을 끝낼 수 있도록 `preStop` 훅이나 프레임워크 자체의 Graceful Shutdown 타임아웃을 K8S `terminationGracePeriodSeconds`와 맞춰준다.

> **결정: Stateless 애플리케이션은 Deployment + HPA, Preferred AZ Anti-Affinity, Readiness Probe 기반 롤링 업데이트를 적용해 무중단 고가용성을 확보한다.**

---

## 10. 영구 스토리지 전략 — PV/PVC, CSI Driver, StorageClass

Stateful 워크로드로 넘어가기 전에, K8S에서 영구 데이터를 어떻게 저장하는지 제약 조건을 먼저 정의한다. Phase 1에서 Stateful 워크로드를 EC2에 유지하더라도, K8S 내부에는 상태를 저장해야 하는 인프라 Pod(Prometheus, Grafana, ArgoCD 등)가 존재하므로, 영구 스토리지 전략은 반드시 필요하다.


### CSI Driver 선택

kubeadm은 EKS와 달리 스토리지 프로비저닝이 자동 설정되지 않으므로 CSI(Container Storage Interface) Driver를 직접 설치해야 한다. PVC를 선언하면 CSI Driver가 실제 볼륨을 생성·연결·해제하는 역할을 한다.

| 후보 | 장점 | 단점 |
|------|------|------|
| **AWS EBS CSI Driver** | AWS 네이티브, gp3/io2 지원, 스냅샷 API 연동 | EBS AZ 종속, IRSA 없이 Instance Profile 필요 |
| **OpenEBS (LocalPV/Replicated)** | 클라우드 비종속, 로컬 디스크 활용 | CPU/RAM 오버헤드, Split-Brain 복구 난이도, 추가 학습 비용 |
| **Longhorn** | 직관적 UI, 복제 내장 | 리소스 오버헤드, 소규모 클러스터에서 과잉 |

**AWS EBS CSI Driver를 채택한다.** AWS 단일 클라우드로 통합한 이상 EBS 네이티브 연동이 가장 자연스럽고, OpenEBS/Longhorn의 분산 스토리지 오버헤드는 Worker 6대 규모에서 리소스 낭비다. 권한은 §2(kubeadm 단점 3)에서 언급한 대로 워커 노드의 IAM Instance Profile(AmazonEBSCSIDriverPolicy)로 부여한다.

### StorageClass 설계

EBS CSI Driver 위에 StorageClass를 정의하여 PVC가 어떤 유형의 볼륨을 받을지 결정한다.

**기본(Default) StorageClass: gp3**

| 항목 | 설정 | 이유 |
|------|------|------|
| 볼륨 타입 | gp3 | 기본 3,000 IOPS / 125MB/s, 추가 비용 없이 IOPS/Throughput 독립 조절 가능 |
| Reclaim Policy | 워크로드별 분리 (아래 참조) | 데이터 중요도에 따라 차등 적용 |
| VolumeBindingMode | **WaitForFirstConsumer** | Pod가 스케줄링된 AZ에 볼륨 생성 (필수) |

**Reclaim Policy — 워크로드별 차등**

| 정책 | 대상 | 동작 | 이유 |
|------|------|------|------|
| **Delete** | 모니터링(Prometheus), 로깅, 임시 캐시 | PVC 삭제 시 EBS도 삭제 | 재생성 가능한 데이터, 비용 절약 |
| **Retain** | DB(MySQL, MongoDB), ChromaDB, RabbitMQ | PVC 삭제해도 EBS 보존 | 실수로 PVC를 삭제해도 데이터 복구 가능 |

**WaitForFirstConsumer가 필수인 이유**: 기본 모드(Immediate)는 PVC 생성 즉시 임의 AZ에 EBS를 만든다. Pod가 다른 AZ에 스케줄링되면 EBS에 접근할 수 없어 **Pod Pending** 상태에 빠진다. WaitForFirstConsumer는 Pod의 스케줄링 결과를 확인한 후 해당 AZ에 EBS를 생성하므로 이 문제를 원천 차단한다.

### AZ 종속성과 한계

AWS EBS는 **생성된 AZ를 벗어날 수 없다.** 이것이 K8S Stateful 워크로드 설계의 가장 큰 제약이다.

```
AZ 2a: W1, W2 + EBS-A (MySQL Primary)
AZ 2b: W3, W4
AZ 2c: W5, W6 + EBS-B (MySQL Replica)

W1 장애 → W2로 재스케줄링 → EBS-A 재연결 ✓ (같은 AZ)
AZ 2a 전체 장애 → W3~W6로 재스케줄링 → EBS-A 접근 불가 ✗ (다른 AZ)
```

§5의 3-AZ 2-2-2 배치에서 각 AZ에 Worker 2대씩 있으므로, **같은 AZ 내 노드 장애는 재스케줄링으로 복구 가능**하다. 그러나 AZ 전체 장애 시 해당 AZ의 EBS에 의존하는 단일 Pod는 복구할 수 없다.

따라서 영구 데이터 보존이 필요한 워크로드는 다음 중 하나를 반드시 동반해야 한다:
- **애플리케이션 레벨 복제(HA)**: Primary(AZ 2a) + Replica(AZ 2c) → AZ 장애 시 Replica가 승격
- **정기 스냅샷 백업**: EBS 스냅샷은 리전 레벨 저장 → AZ 장애와 무관하게 복원 가능

> **결정: AWS EBS CSI Driver + gp3 Default StorageClass (WaitForFirstConsumer). Reclaim Policy는 데이터 중요도별 Delete/Retain 분리. EBS AZ 종속성을 인지하고 Stateful 워크로드는 HA 또는 스냅샷으로 보완**

---

## 11. Stateful 배치 전략 — 단계적 전환

### V2 현황

V2에서 상태를 저장하거나 메시지를 처리하는 워크로드는 다음과 같다.

| 워크로드 | 분류 | 역할 | V2 운영 |
|----------|------|------|---------|
| MySQL | 데이터베이스 | 핵심 비즈니스 데이터 (계약, 사용자, 매물) | EC2 단일 |
| MongoDB | 데이터베이스 | 채팅 데이터 (V3 신규) | — |
| Redis | 캐시/세션 | 세션 저장, 응답 캐시 | EC2 단일 |
| RabbitMQ | 메시지 브로커 | AI 요청/응답 큐 | EC2 단일 |
| ChromaDB | 벡터 DB | 임베딩 검색 | EC2 단일 |

V2에서는 전부 단일 인스턴스, HA 없음. 장애 시 수동 복구가 필요했다. Phase 1에서는 이를 **3-AZ(2a/2b/2c) 분산 클러스터**로 격상하여 자동 Failover를 확보한다(§12 참조).

### 왜 단계적 전환인가

이들을 한꺼번에 K8S로 옮기면 위험이 크다.

- **StatefulSet 운영 경험 부족**: 팀에 K8S StatefulSet 운영 경험이 없다. Stateless(Deployment)와 Stateful(StatefulSet)을 동시에 학습하면 장애 원인 분리가 어렵다.
- **EBS AZ 종속(§10)**: K8S에서 영구 스토리지는 AZ에 묶인다. 이 제약을 충분히 이해하지 않은 상태에서 DB를 K8S에 올리면 AZ 장애 시 데이터 접근 불가 사태가 발생한다.
- **장애 격리**: Stateless와 Stateful을 동시에 K8S에 배치하면, K8S CP 장애 시 App과 DB 모두 영향을 받는다.

**Stateless(FE/BE/AI-Server)를 먼저 K8S에서 안정화한 뒤, Stateful은 검증된 운영 경험을 바탕으로 순차 이관한다.**

### Phase 1 — Stateless K8S + Stateful EC2

```
[K8S Cluster — 새 VPC Private 서브넷]
  FE, BE, AI-Server (Deployment)
  Prometheus, Grafana, Alloy, ArgoCD (PVC 사용)
  Gateway Fabric (DaemonSet)
       │
       │ Private IP (같은 VPC)
       ▼
[EC2 — 새 VPC Private 서브넷, 3-AZ 분산]
  MySQL, MongoDB, Redis, RabbitMQ, ChromaDB (§12 HA 클러스터)
```

K8S Worker 노드와 DB EC2는 **같은 VPC의 Private 서브넷**에 배치한다. K8S Pod가 EC2 DB에 접근하는 방법은 두 가지다.

| 방식 | 동작 | 장점 | 단점 |
|------|------|------|------|
| **ExternalName Service** | CNAME으로 EC2 Private DNS/IP를 가리킴 | 설정 단순 | ClusterIP 없음, NetworkPolicy 적용 제한 |
| **Endpoints + ClusterIP Service** | 수동 Endpoints에 EC2 IP 등록 | ClusterIP 부여 → NetworkPolicy 적용 가능 | IP 변경 시 Endpoints 수동 갱신 필요 |

어느 방식이든 Pod는 `mysql.external.svc.cluster.local` 같은 **K8S 서비스명**으로 접근한다. Phase 2에서 K8S StatefulSet으로 이관 시, Service 뒤의 Endpoint만 변경하면 **Pod 코드 수정 없이 전환**할 수 있다.

### Phase 1의 이점

- **장애 격리**: K8S 장애가 DB에 영향 없음. DB 장애가 K8S 컨트롤 플레인에 영향 없음.
- **자동 Failover**: §12의 3-AZ HA 클러스터로 DB 자체의 무중단 운영을 Phase 1부터 확보.
- **점진적 학습**: K8S 기본 운영(Deployment, HPA, Rolling Update, Gateway API)에 집중할 수 있음.
- **롤백 용이**: Stateless만 K8S에 있으므로, 문제 시 EC2로 롤백이 간단.
- **리소스 분리**: DB 전용 EC2 인스턴스로 App과 CPU/메모리 경합이 없음.

### Phase 2 — Stateful K8S 이관

Phase 1 안정화 후, Stateful 워크로드를 순차적으로 K8S StatefulSet으로 이관한다. §12의 DB HA 토폴로지는 이 Phase 2에서 적용한다.

- **전환 기준**: K8S 운영 안정화 확인 (Stateless 워크로드 무장애 운영 기간)
- **이관 순서**: 운영 경험 축적 후 결정 (위험도·복잡도·데이터 중요도 기준)
- **이관 방식**: Service Endpoint 전환 — EC2 IP → K8S Pod IP로 변경. 코드 수정 불필요.

> **결정: 단계적 전환 — Phase 1에서 Stateless만 K8S 배포, Stateful(MySQL/MongoDB/Redis/RabbitMQ/ChromaDB)은 같은 VPC EC2 유지. Phase 1 안정화 후 Phase 2에서 순차 K8S 이관.**

---

## 12. DB HA 토폴로지

> 이 섹션은 Phase 2(Stateful → K8S 이관) 시 적용할 HA 토폴로지를 다룬다. Phase 1에서는 §11의 결정에 따라 Stateful 워크로드가 EC2에서 운영되므로, 본 섹션의 K8S StatefulSet 구성은 Phase 2 이관 시 참조한다.

도장콕의 핵심 기능(쉬운 계약서, 집노트)은 부동산 현장이나 계약 과정에서 실시간으로 쓰이는 만큼 시스템 가용성이 매우 중요하다. 애플리케이션의 무중단 운영뿐만 아니라, 사용자 데이터를 다루는 데이터베이스와 메시지 큐 계층에서도 철저한 장애 대비(HA)가 뒷받침되어야 한다.

이를 위해 기존의 단일 인스턴스 수준을 넘어, 주요 인프라 구성요소 전반을 고가용성 클러스터로 개편하기로 결정했다. 단, Stateful한 특성을 가진 데이터베이스와 메시지 큐를 처음부터 K8S 클러스터에 포함시키기보다는 초기에는 외부에서 분리하여 안정적으로 관리한다. 이후 조직의 K8S 운영 노하우가 축적됨에 따라 이를 컨테이너화(Pod)하여, 최종적으로 모든 인프라 구성요소를 클러스터 내부에서 통합 관리하는 것을 목표로 한다.

### 확정 결정

| 워크로드 | 구성 | Failover | AZ 배치 |
|----------|------|----------|---------|
| MySQL | InnoDB Cluster | 자동 (Group Replication) | Master(2a) + Replica(2b) + Replica(2c) |
| MongoDB | ReplicaSet | 자동 (내장 election) | Primary(2a) + Secondary(2b) + Arbiter(2c) |
| Redis | Sentinel | 자동 (Sentinel 쿼럼) | Master(2a) + Replica(2b) + Replica(2c) |
| RabbitMQ | Quorum Queue | 자동 (Raft 합의) | Leader(2a) + Follower(2b) + Follower(2c) |
| ChromaDB | 단일 + PVC + 정기 백업 | 수동 (스냅샷/재구축) | 단일 (2a) |

> 이때 애플리케이션 개발자는 다중화, 클러스터 여부와 관계없이 해당 서비스들을 단일 엔드포인트로 접근할 수 있도록 구성하여 인프라 계층에서의 추상화 목표도 달성하고자 한다.

### MySQL — InnoDB Cluster (Master + 2 Replicas)

MySQL의 데이터 정합성과 고가용성을 위해 3-AZ에 분산된 InnoDB Cluster를 구성한다. 

**채택 구성: Master(2a) + Replica(2b) + Replica(2c)**

- **Master (AZ 2a)**: 읽기/쓰기 처리
- **Replica (AZ 2b, 2c)**: 데이터 동기화 및 부하(읽기) 분산
- **Failover**: AZ 장애 시 남은 노드 간 과반수(Majority) 투표를 통해 새로운 Master를 자동 선출한다. 과거처럼 Orchestrator 등 외부 도구에 의존할 필요 없이 자체 내장된 Group Replication을 기반으로 완벽한 자동 장애 조치가 동작한다.

| 컴포넌트 | AWS 인스턴스 타입 | vCPU | RAM |
|----------|-------------------|------|-----|
| Master | t4g.small | 2 | 2GB |
| Replica (×2) | t4g.small × 2 | 4 | 4GB |
| **합계** | **t4g.small × 3대** | **6** | **6GB** |

### MongoDB — ReplicaSet (Primary + Secondary + Arbiter)

MongoDB ReplicaSet은 수동 개입 없이 내장된 선출(election) 기능으로 Primary를 즉시 분별 및 자동 선출한다. 

**채택 구성: Primary(2a) + Secondary(2b) + Arbiter(2c)**

- **Primary (AZ 2a)**: 읽기/쓰기 처리
- **Secondary (AZ 2b)**: oplog 기반 실시간 복제
- **Arbiter (AZ 2c)**: 데이터는 미저장하지만, 파티션 장애 시 투표권만 행사하여 과반수를 달성하게 돕는 경량 노드 (50m/64MB 수준)

가장 비용 효율적인 3-AZ 구성으로써, 2c AZ에 무거운 데이터를 복제하지 않고 컴퓨팅 리소스를 아끼면서도 높은 수준의 완충 가용성을 확보한다.

| 컴포넌트 | AWS 인스턴스 타입 | vCPU | RAM |
|----------|-------------------|------|-----|
| Primary | t4g.micro | 2 | 1GB |
| Secondary | t4g.micro | 2 | 1GB |
| Arbiter | t4g.small | 2 | 2.0GB |
| **합계** | **micro 2대 + small 1대** | **6** | **4.0GB** |

### Redis — Sentinel (Master + 2 Replicas)

세션 저장과 캐시, 향후 채팅 관련 Pub/Sub 역할을 고려하여 Redis 역시 3개의 가용 영역에 분산 배치, 장애를 완전 자동으로 복구한다.

**채택 구성: Sentinel Master(2a) + Replica(2b) + Replica(2c)**

- 별도 분산된 3-AZ 노드에 띄워진 Sentinel 프로세스들이 쿼럼(과반수)을 보장하며, 마스터 노드 장애 감지 시 상태가 가장 온전한 Replica를 신규 마스터로 자동 승격시킨다.
- 초반 EC2 Phase에서는 HAProxy 등을 사용하고 이후 K8S 전환 시에는 Redis Operator를 활용하여 애플리케이션(BE)에 최적의 단일 Service 엔드포인트 DNS를 제공한다. 백엔드 시스템은 인프라의 장애 변경을 전혀 신경 쓰지 않게(Decoupling) 된다.

### RabbitMQ — Quorum Queue

AI 서버 등과의 메인 메시지 브로커인 RabbitMQ 또한 데이터 완전성과 HA에 최적화된 분산 아키텍처 Quorum Queue를 전면 채택한다.

**채택 구성: Leader(2a) + Follower(2b) + Follower(2c)**

- 강력한 내부 정합성 모델인 Raft 합의 알고리즘에 기초하여 3-AZ 전체에 데이터를 안전하게 동기 복제한다. 
- 하나의 AZ가 다운되어 Leader가 소실되어도 즉시 살아남은 두 Follower 사이에서 신규 Leader를 투표를 통해 자동 선출하고 큐 처리를 무중단 재개한다. 클라이언트는 다수의 주소를 연결 정보로 설정하여 재결합을 위임하거나, K8S 내에서 단일 진입점 Service를 통해 연결할 수 있다.

| 컴포넌트 | AWS 인스턴스 타입 | vCPU | RAM |
|----------|-------------------|------|-----|
| Leader / Follower | t4g.small × 3대 | 6 | 6.0GB |

### ChromaDB — 단일 + PVC + 정기 백업

오픈소스 ChromaDB는 DB 자체적으로 다중 AZ 분산 클러스터링 기반의 완전 자동 선출 시스템(Failover)을 제공하지 않는다. 이를 억지로 다중화하기보다 본연의 특징인 '단일 노드의 빠른 복원' 중심 아키텍처를 추구한다.

- 장애 발생 대응: 프로세스 다운 시 컨테이너 오케스트레이션(K8S/EC2 ASG) 레벨에서 즉각적인 재시작을 수행한다. 최악의 AZ 완전 장애나 데이터 결함 시 K8S에 연결된 정기 EBS 스냅샷으로 복원하거나, 시스템을 정비하고 MySQL에 보존된 원본 텍스트를 바탕으로 벡터 임베딩을 다시 추출(Re-indexing)하여 돌파한다.

### 3-AZ 분산 배치의 이점 (무중단 고가용성 보장)

과거 2개 AZ로만 배치했을 때는, 한쪽 AZ의 장애가 즉각 '과반수(Majority) 상실'을 야기해 데이터베이스가 읽기 전용으로 강등되거나 수동 조치에 의존해야 하는 인프라적 제약이 있었다.
**핵심 Stateful 워크로드를 모두 3개 AZ (2a, 2b, 2c)로 격상**함에 따라 만일의 특정 AZ 하나가 붕괴되더라도 다음과 같이 무중단 서비스를 이어간다.

| 장애 상황 시나리오 | 동작 결과 |
|--------------------|-----------|
| **AZ 2a (현 대장) 다운** | 남은 2b, 2c가 과반수를 달성. 2b의 Secondary/Replica/Follower가 새로운 대장으로 즉각 100% 자동 승격 (**서비스 생존 및 진화**) |
| **AZ 2b 다운** | 2a 대장과 2c가 굳건히 안전 투표수(과반수)를 유지하므로 쓰기/읽기 작업 영향 제로 (**서비스 온전 유지**) |
| **AZ 2c 다운** | 2a 대장과 2b가 살아있어 과반수 확보 유지. 동일하게 정상 동작 (**서비스 온전 유지**) |

### 리소스 영향

핵심 파이프라인 리소스를 3방향 고가용성(HA)으로 편제하기 위해 필요한 AWS EC2 인스턴스 추가 구성은 다음과 같다. K8S 클러스터 워커 노드와는 물리적으로 물리/분리된 독립 인프라로 구성된다.

| 항목 | 권장 인스턴스 사양 | 대수 | 총 vCPU | 총 RAM |
|------|------------------|------|---------|--------|
| MySQL (1M+2R) | t4g.small | 3 | 6 | 6.0GB |
| MongoDB (P+S+A) | t4g.micro (2), t4g.small (1) | 3 | 6 | 4.0GB |
| Redis (3-node) | t4g.small | 3 | 6 | 6.0GB |
| RabbitMQ (3-node) | t4g.small | 3 | 6 | 6.0GB |
| ChromaDB (단일) | t4g.micro | 1 | 2 | 1.0GB |

K8S 클러스터 안에서 자원(CPU/RAM)을 나누어 쓰는 것이 아니므로 K8S Node의 리소스와 경합하지 않는다. AWS EC2 인스턴스를 독립적으로 운영함으로써 앱(K8S) 장애와 데이터(DB) 장애를 더욱 완벽하게 물리적으로 격리하는 이점을 가진다. 

> **결정: MySQL(InnoDB Cluster), MongoDB(ReplicaSet), Redis(Sentinel), RabbitMQ(Quorum Queue) 모두 3-AZ(2a, 2b, 2c) 풀 클러스터 분산 배치로 변경하여 완전 자동 Failover 구성을 실현한다. 단, ChromaDB는 단일 노드 운영 및 스냅샷 복구 전략 채택. 이를 통해 장애 제약을 한 단계 초월한, 완벽한 인프라 무중단 서비스 생태계를 갖춘다.**

---

## 13. GPU 워크로드 — K8S 내부 vs RunPod 외부

vLLM(EXAONE-3.5-7.8B) 추론에는 최소 L4 24GB 이상의 GPU가 필수다. 이상적으로는 K8S 클러스터 내에 GPU 노드풀을 두어 통합 관리하는 것이 좋지만, **AWS GPU 인스턴스 할당 요청이 지속적으로 반려**되고 있어 현실적으로 선택지가 없다.

섹션 1에서 기술한 단일 클라우드(AWS) 통합에 따라, **GPU만 RunPod으로 외부 위임**한다. AI Server(FastAPI)는 K8S 내부에서 오케스트레이터로 동작하며, vLLM에 HTTPS API 요청을 보내는 구조다.

향후 AWS GPU 할당이 승인되면 K8S GPU 노드풀을 추가하여 클러스터 내부로 전환하는 경로를 열어둔다.

> **결정: RunPod 외부 + API 요청 방식 — AWS GPU 할당 반려로 외부 위임, 추후 전환 검토**

---


## Part 4. 트래픽 인입 및 보안 통제

## 14. Ingress — 외부 트래픽 진입

### 역할 정의와 요구사항

V2에서는 ALB가 FE/BE로 직접 라우팅했다. K8S에서는 클러스터 외부의 트래픽을 받아 내부 서비스로 전달하는 **L7 진입점** 이 필요하다. 이 진입점은 호스트명이나 URL 경로를 보고 적절한 Service로 분배하는 역할을 한다.

이 진입점을 외부에서 접근 가능하게 만드는 방법(NodePort, LoadBalancer 등)은 별도의 관심사로, 섹션 15(Service 노출 전략)에서 다룬다.

**현재 필요한 L7 라우팅 기능** :
- 호스트/경로 기반 라우팅 (`/ → FE`, `/api → BE`)
- TLS는 ALB에서 종료하므로 진입점 레벨 TLS 불필요
- kubeadm이라 `type: LoadBalancer` 자동 프로비저닝 없음

### Ingress API vs Gateway API

K8S에서 L7 라우팅을 제공하는 표준은 두 가지다. **Ingress API**(2015~, v1 GA 2020)는 단일 오브젝트에 라우팅 규칙을 선언하며 호스트/경로 라우팅과 TLS를 스펙으로 제공한다. 그 외 기능(가중치 라우팅, 헤더 매칭 등)은 컨트롤러별 annotation에 의존하고, 2020 GA 이후 스펙이 동결되었다.<br> **Gateway API**(2019~, v1.0 GA 2023)는 Ingress의 후속 표준으로, annotation 영역을 스펙으로 흡수하고 리소스를 역할별(GatewayClass/Gateway/HTTPRoute)로 분리했다.

우리 요구사항(호스트/경로 라우팅)에 한정하면 **양쪽 모두 동일하게 충족**한다. Gateway API가 가중치 라우팅·헤더 매칭·타입 검증 등을 스펙에 내장하고 있으나, 현재 우리가 사용하는 범위에서는 기능적 우위가 선택의 결정적 이유는 아니다.

### 기능 외 판단 기준

기능이 동일하다면 다른 축에서 판단해야 한다.

| 기준 | Ingress | Gateway API |
|------|---------|-------------|
| 스펙 상태 | 동결 (2020 GA 이후 변경 없음) | 활발한 개발 (2023 GA, 지속 확장) |
| NGINX 구현체 | Ingress Controller (2026-03 EOL) | Gateway Fabric (활발 개발) |
| 생태계 | 주력 개발이 Gateway API로 이동 중 | Envoy Gateway, Traefik v3 등 |

새로 K8S를 구축하는 입장에서, 동결된 스펙보다 활발한 후속 표준에 학습을 투자하는 것이 합리적이다. 같은 NGINX 엔진 기반의 후속 제품(Gateway Fabric)이 있으므로, 엔진 안정성을 유지하면서 표준만 전환할 수 있다.

> Gateway API는 가중치 라우팅(카나리), L4 프로토콜(TCPRoute/GRPCRoute), Cross-namespace 라우팅 등 Ingress에 없는 기능을 스펙으로 제공하나, 현재 우리 요구사항 범위 밖이므로 선택 근거에서 제외한다.

### Gateway API 구현체 선택

Gateway API를 택한 후, 구현체를 비교한다.

| 구현체 | 엔진 | 장점 | 단점 | 적합성 |
|--------|------|------|------|--------|
| AWS ALB Controller | ALB 네이티브 | AWS 통합 | kubeadm IRSA 없음, 클라우드 락인 | ✗ |
| Cilium Gateway | Cilium | eBPF 고성능 | CNI에서 Calico 채택 → 제외 | ✗ |
| Envoy Gateway | Envoy | Rate Limiting 내장, CNCF | 러닝커브, 레퍼런스 부족 | △ |
| NGINX Gateway Fabric | NGINX | 30년 검증 엔진, 레퍼런스 풍부 | 고급 기능 미지원 | ✓ |

> **결정: NGINX Gateway Fabric — 기능적으로 Ingress와 차이 없으나, 동결된 Ingress 스펙 대신 활발한 Gateway API 표준 + 검증된 NGINX 엔진**

---

## 15. Service 노출 전략

kubeadm에는 LoadBalancer 타입 자동 프로비저닝이 없으므로(EKS와 다름), 외부 트래픽을 클러스터 내부로 어떻게 전달할지 직접 설계해야 한다. 내부 전용 서비스(AI Server, DB, Redis, RabbitMQ, ChromaDB)는 ClusterIP로 확정이고, 외부 접근이 필요한 FE/BE의 노출 방식이 쟁점이었다.

| 서비스 | 외부 접근 | 타입 |
|--------|----------|------|
| NGINX Gateway Fabric | O | NodePort |
| FE, BE | X (Gateway 경유) | ClusterIP |
| AI Server, DB, Redis, RabbitMQ, ChromaDB | X | ClusterIP |

Ingress(섹션 14)에서 NGINX Gateway Fabric을 확정한 이상, **모든 외부 트래픽은 Gateway Fabric을 통해서만 진입**하는 구조가 자연스럽다. FE/BE를 별도 NodePort로 직접 노출하면 라우팅 룰이 ALB와 Gateway에 이원화되고, Gateway Fabric의 관측성(access log, 메트릭) 이점이 사라진다.

**옵션 A(Gateway Fabric NodePort 전용 노출)** 를 확정한다.
- **트래픽 경로**: ALB → Gateway Fabric(NodePort) → FE/BE(ClusterIP)
- **보안 은폐**: FE/BE가 ClusterIP로만 노출되어 외부에서 직접 접근 불가
- **라우팅 중앙화**: HTTPRoute 룰을 Gateway Fabric YAML에서 GitOps로 일원 관리
- **관측성**: Gateway Fabric에서 전체 트래픽의 access log, latency 메트릭 수집 가능
- **병목 대응**: 모든 외부 트래픽이 Gateway를 경유하므로, Gateway Pod가 단일 노드에만 있으면 SPOF가 된다. DaemonSet으로 모든 Worker(W1~W6)에 각 1개씩 배치하고, ALB Target Group이 6대의 동일 NodePort를 바라보게 한다. 노드 1대 다운 시 ALB health check가 감지하여 나머지 5대로 분산하며, 트래픽이 도착한 노드에서 로컬 Gateway Pod이 직접 처리하므로 노드 간 추가 hop이 없다. §5의 3-AZ 2-2-2 배치와 맞물려 AZ 장애 시에도 나머지 AZ의 Gateway Fabric이 트래픽을 계속 처리한다.

> **대안 — hostNetwork**: Gateway Fabric Pod에 `hostNetwork: true`를 설정하면 노드 IP의 80/443 포트에 직접 바인딩되어, NodePort(30000~32767) 대신 웹 표준 포트만 열면 되므로 SG 룰이 깔끔해지고 kube-proxy hop도 제거된다. 다만 Pod이 노드 네트워크를 공유하여 **네트워크 격리가 약화**되므로, 격리를 우선하여 NodePort 방식을 채택한다.

> **AWS SG 주의**: Worker 노드 SG의 NodePort 대역(30000-32767) Inbound Source를 **ALB SG ID로 한정**해야 한다. 0.0.0.0/0으로 열면 ALB를 우회하여 노드에 직접 접근하는 공격이 가능해진다.

> **결정: 옵션 A 확정 — Gateway Fabric NodePort 전용 노출. DaemonSet + ALB health check로 SPOF 제거. 보안 은폐(ClusterIP) 및 라우팅 룰 GitOps 관리를 위해 모든 외부 트래픽은 Gateway Fabric을 통해서만 진입**

---

## 16. TLS 종료 지점

외부 → ALB → Gateway Fabric → Pod 경로에서 어디서 HTTPS를 끊을지가 쟁점이다. **ALB에서 종료**하면 클라이언트→ALB 구간만 HTTPS이고 내부는 HTTP로, ACM 무료 인증서를 활용할 수 있어 설정이 단순하다. **끝단 암호화**는 ALB→Gateway Fabric 구간까지 HTTPS로 보호하지만, cert-manager를 추가로 관리해야 하여 복잡도가 증가한다.

V2에서도 ALB TLS 종료로 운영한 전례가 있고, 내부 트래픽은 private 서브넷 안이라 평문이어도 실질적 위험이 낮다. ACM 인증서가 무료이므로 cert-manager 없이 운영 가능하며, kubeadm 내부 인증서(API Server, etcd 등)는 kubeadm init 시 자동 생성되며, **기본 1년 만료**다. `kubeadm certs renew`로 수동 갱신하거나, `kubeadm upgrade` 실행 시 자동 갱신된다. 만료 전 Prometheus 알림 설정이 필수다.

> **결정: ALB에서 TLS 종료 — V2와 동일, 내부 HTTP. ACM 무료 인증서 활용**

---

## 17. Namespace 설계

Namespace는 K8S 보안 통제의 **적용 범위(scope)**를 결정하는 상위 설계다. NetworkPolicy(§18)와 RBAC(§19)가 모두 NS 단위로 적용되므로, NS가 먼저 정의되어야 보안 정책의 경계가 결정된다.

```
§17 Namespace     →  "경계를 어디에 긋는가"     (보안 범위 정의)
  ↓
§18 NetworkPolicy →  "Pod끼리 누가 통신하는가"   (네트워크 격리)
  ↓
§19 RBAC/SA       →  "Pod가 K8S API에서 뭘 하는가" (API 접근 제어)
```

이 3개가 합쳐져 V2의 보안 수준(프라이빗 서브넷 + 보안그룹 + IAM)을 K8S에서 동등하게 계승한다.

### NS가 결정하는 범위

| K8S 리소스 | NS 영향 |
|-----------|---------|
| NetworkPolicy | 같은 NS의 Pod에만 적용. `dojangkok` NS의 Default Deny는 `monitoring` NS에 영향 없음 |
| Role / RoleBinding | NS 단위 권한. `data` NS의 Role은 `dojangkok` NS 리소스에 접근 불가 |
| ServiceAccount | NS 소속. `dojangkok` NS의 `be-sa`와 `data` NS의 `mysql-sa`는 별개 |
| Secret / ConfigMap | NS 격리. `data` NS의 DB 패스워드 Secret을 `dojangkok` NS Pod에서 직접 참조 불가 |

NS를 어떻게 나누느냐에 따라 위 리소스들의 기본 격리 경계가 달라진다.

### 설계 원칙

- **역할별 분리**: 비즈니스 워크로드, 데이터, 운영 도구를 분리하여 장애 영향 범위와 권한 범위를 제한한다.
- **도구 기본값 존중**: Helm 차트가 기본 생성하는 NS를 그대로 사용하여 설정 복잡도를 낮춘다.
- **Phase 대응**: Phase 1에서는 data NS 없이 운영하고, Phase 2 이관 시 생성한다.

### Namespace 구성

| NS | 워크로드 | Phase | 비고 |
|----|---------|-------|------|
| `dojangkok` | FE, BE, AI Server | 1 | 비즈니스 워크로드 |
| `data` | MySQL, MongoDB, Redis, RabbitMQ, ChromaDB | 2 | Phase 1에서는 EC2, Phase 2 이관 시 생성 |
| `monitoring` | Prometheus, Grafana, Alloy | 1 | kube-prometheus-stack 관례 NS |
| `argocd` | ArgoCD | 1 | Helm 차트 기본 NS |
| `nginx-gateway` | NGINX Gateway Fabric | 1 | Helm 차트 기본 NS |
| `kube-system` | CoreDNS, kube-proxy, Calico, EBS CSI Driver | 1 | kubeadm 기본 |

### Cross-Namespace 통신

NS 분리 시 서비스 DNS가 `{svc}.{ns}.svc.cluster.local` 형태가 된다. 같은 NS 내에서는 `{svc}`만으로 접근 가능하다.

| 출발 | 목적 | 트래픽 | DNS 예시 |
|------|------|--------|---------|
| nginx-gateway | dojangkok | Gateway → FE/BE | HTTPRoute로 라우팅 |
| dojangkok | data | BE → MySQL, MongoDB, Redis, RMQ | `mysql.data.svc.cluster.local` |
| dojangkok | data | AI Server → ChromaDB | `chromadb.data.svc.cluster.local` |
| dojangkok | 외부(VPC) | BE → EC2 DB (Phase 1) | ExternalName → EC2 Private IP |
| dojangkok | 외부(인터넷) | AI Server → RunPod | NAT Instance 경유 |
| monitoring | 전체 NS | Prometheus 메트릭 스크래핑 | ServiceMonitor로 대상 지정 |
| argocd | 전체 NS | ArgoCD 배포 관리 | K8S API 경유 |

### Phase 전환 시 DNS 경로

Phase 1에서 BE는 `dojangkok` NS의 ExternalName Service(`mysql` → EC2 IP)로 DB에 접근한다. Phase 2에서 MySQL을 `data` NS로 이관하면, ExternalName의 대상을 `mysql.data.svc.cluster.local`로 변경하여 **BE 코드 수정 없이** 전환할 수 있다(§11 참조).

> **결정: 역할별 6개 NS — dojangkok(비즈니스) / data(DB, Phase 2) / monitoring / argocd / nginx-gateway / kube-system. Phase 1에서는 data NS 미사용.**

---

## 18. NetworkPolicy — Pod 간 통신 제어

K8S 기본 상태에서는 모든 Pod이 모든 Pod과 통신할 수 있는 flat network다. V2에서는 보안그룹(기본 Deny + 허용 룰)으로 트래픽 방향을 제어했으므로, K8S에서도 동일한 보안 수준을 유지해야 한다.

접근 방식은 세 가지를 검토했다. "DB만 보호"는 App 간 통신을 제어하지 못하고, "추후 적용"은 보안 공백이 생긴다. V2 보안그룹이 기본 Deny였으므로, K8S에서도 **Default Deny + Whitelist**(전체 차단 후 필요한 통신만 허용)를 적용하여 동일한 보안 수준을 유지한다. 정책 수가 많아지고 새 서비스 추가 시 정책도 추가해야 하지만, CNI 선택(섹션 6)에서 채택한 Calico가 NetworkPolicy를 기본 지원하므로 추가 컴포넌트 없이 구현 가능하다.

공통 필수 정책(우선순위순)은 다음과 같다.

| # | 룰 | 방향 | 대상 | 빠뜨리면 |
|---|-----|------|------|---------|
| 1 | 노드 CIDR(10.10.x.x) → 전체 Pod | Ingress | 전체 | kubelet Probe 실패, Pod 무한 재시작 |
| 2 | 모든 Pod → kube-dns (UDP 53) | Egress | 전체 | 서비스 이름 해석 불가, 전체 장애 |
| 3 | Gateway Fabric → FE/BE | Ingress | FE, BE | 외부 접속 502/504 |
| 4 | Prometheus → 전체 Pod (메트릭 포트) | Ingress | 전체 | 모니터링 블랙아웃 |
| 5 | 외부 인터넷 (0.0.0.0/0) | Egress | AI Server 등 | RunPod API, ECR 풀 불가 |

이 공통 필수 정책 5개를 먼저 적용한 뒤, 아래 서비스 간 통신 맵에 따라 개별 허용한다.

```
FE          → BE
BE          → MySQL, MongoDB, Redis, RabbitMQ, AI Server
AI Server   → ChromaDB, 외부(RunPod)
RabbitMQ    ↔ BE, AI Server (양방향)
DB 간        → Primary ↔ Replica (HA 복제)
Prometheus  → 전체 Pod (메트릭 스크래핑)
Alloy       → 전체 Pod (로그/트레이스 수집)
```

### NS별 정책 매핑

§17에서 정의한 Namespace 단위로 Default Deny를 각각 적용하고, 필요한 통신만 화이트리스트한다. Cross-NS 트래픽은 `namespaceSelector`로 명시해야 통과하고, 같은 NS 내부는 `podSelector`만으로 충분하다.

**`dojangkok` NS** (FE, BE, AI Server):

| 방향 | 룰 | 비고 |
|------|-----|------|
| Ingress | `nginx-gateway` NS → FE, BE | Gateway 라우팅 |
| Ingress | 공통 필수 #1, #4 (kubelet, Prometheus) | |
| Egress | BE → `data` NS의 MySQL, MongoDB, Redis, RMQ | `namespaceSelector` 필요 |
| Egress | AI Server → `data` NS의 ChromaDB | `namespaceSelector` 필요 |
| Egress | AI Server → 외부 인터넷 (RunPod) | 공통 필수 #5 |
| Egress | 전체 → kube-dns | 공통 필수 #2 |

**`data` NS** (Phase 2, MySQL, MongoDB, Redis, RMQ, ChromaDB):

| 방향 | 룰 | 비고 |
|------|-----|------|
| Ingress | `dojangkok` NS의 BE → MySQL, MongoDB, Redis, RMQ | `namespaceSelector` 필요 |
| Ingress | `dojangkok` NS의 AI Server → ChromaDB | `namespaceSelector` 필요 |
| Ingress | 공통 필수 #1, #4 (kubelet, Prometheus) | |
| Ingress/Egress | DB Primary ↔ Replica (같은 NS) | `podSelector`로 충분 |
| Egress | 전체 → kube-dns | 공통 필수 #2 |

**`monitoring` NS** (Prometheus, Grafana, Alloy):

| 방향 | 룰 | 비고 |
|------|-----|------|
| Egress | Prometheus/Alloy → **전체 NS** Pod | Cross-NS 스크래핑, `namespaceSelector: {}` (all) |
| Ingress | Grafana ← 내부 (Prometheus, Loki) | 같은 NS |
| Ingress | 공통 필수 #1 (kubelet) | |
| Egress | 전체 → kube-dns | 공통 필수 #2 |

**`argocd` / `nginx-gateway` / `kube-system`**: Helm 차트가 기본 생성하는 정책을 기반으로, 공통 필수 정책 + 역할에 필요한 Cross-NS 트래픽만 추가한다. 구체 YAML은 구현 단계에서 정의한다.

> **결정: Default Deny + Whitelist — NS별 개별 적용, Cross-NS는 namespaceSelector 명시 필수. V2 보안그룹과 동일한 기본 차단 + 허용 방식**

---

## 19. RBAC/SA — K8S API 접근 제어

§18에서 Pod 간 네트워크 통신을 제어했다. 하지만 보안에는 또 다른 축이 있다 — **누가 K8S 리소스를 조회·생성·삭제할 수 있는가**. V2에서는 IAM 정책과 SSH 키로 AWS 리소스 접근을 제한했다. K8S에서도 동일한 수준의 접근 제어가 필요하며, 이를 RBAC(Role-Based Access Control)와 ServiceAccount로 구현한다.

```
§18 NetworkPolicy: "Pod끼리 아무나 통신하면 안 된다" (네트워크 격리)
   ↓ "네트워크는 통제했다. 그런데 K8S API 접근은?"
§19 RBAC/SA: "아무나 K8S 리소스를 건드리면 안 된다" (API 접근 제어)
```

두 섹션이 합쳐져서 V2의 보안 수준(프라이빗 서브넷 + 보안그룹 + IAM)을 K8S에서 동등하게 계승하는 그림이 완성된다.

### RBAC 개념

RBAC는 **누가(Subject)** — **무엇을(Resource)** — **어떻게(Verb)** 할 수 있는지를 선언적으로 정의한다.

| 구성요소 | 역할 | 예시 |
|---------|------|------|
| **Subject** | 접근 주체 | User, Group, ServiceAccount |
| **Role / ClusterRole** | 허용할 리소스와 동작 정의 | `pods: [get, list]`, `secrets: [get]` |
| **RoleBinding / ClusterRoleBinding** | Subject와 Role을 연결 | SA `argocd` → ClusterRole `argocd-controller` |

- **Role/RoleBinding**: 특정 Namespace 내에서만 유효
- **ClusterRole/ClusterRoleBinding**: 클러스터 전체에서 유효 (Node, PersistentVolume 등 Namespace 밖 리소스 접근 시 필수)

### ServiceAccount — Pod의 K8S API 신원

Pod가 K8S API에 접근할 때 사용하는 신원(identity)이 ServiceAccount다. Namespace마다 `default` SA가 자동 생성되지만, 모든 Pod이 동일한 권한을 공유하게 되어 **최소 권한 원칙에 위배**된다.

**원칙: 워크로드별 전용 ServiceAccount를 생성하고, 필요한 권한만 부여한다.**

- `automountServiceAccountToken: false`를 기본으로 설정하여, K8S API 접근이 불필요한 Pod에는 토큰 자체를 마운트하지 않는다
- K8S API 접근이 필요한 워크로드(ArgoCD, EBS CSI Driver, Prometheus 등)에만 전용 SA + 최소 Role을 부여한다

### 최소 권한 원칙

V2 보안그룹의 Default Deny와 같은 맥락이다 — **"필요한 권한만 부여"**.

| V2 (AWS) | K8S (RBAC) |
|----------|------------|
| IAM Policy: 필요한 AWS API만 허용 | Role: 필요한 K8S API만 허용 |
| SSH 키: 접근 가능한 서버 제한 | RoleBinding: 접근 가능한 Namespace 제한 |
| Instance Profile: EC2 단위 권한 | ServiceAccount: Pod 단위 권한 |

### NS별 SA/권한 매핑

§17에서 정의한 Namespace에 따라, 각 NS의 워크로드가 필요로 하는 권한 수준이 다르다.

| NS | SA 예시 | 권한 유형 | K8S API 접근 | 이유 |
|----|---------|----------|-------------|------|
| `dojangkok` | `fe-sa`, `be-sa`, `ai-sa` | 토큰 미마운트 | 불필요 | 비즈니스 로직만 수행, K8S API 호출 없음 |
| `data` | `mysql-sa`, `mongodb-sa` | NS Role | 자기 PVC만 | DB Pod가 다른 NS Secret을 읽으면 안 됨 |
| `monitoring` | `prometheus-sa`, `alloy-sa` | **ClusterRole** | 전체 NS 읽기 | ServiceMonitor로 모든 NS의 Pod/Service 스크래핑 |
| `argocd` | `argocd-controller-sa` | **ClusterRole** | 전체 NS CRUD | 모든 NS에 Deployment/StatefulSet 배포 |
| `nginx-gateway` | `gateway-sa` | **ClusterRole** | Gateway CRD | HTTPRoute, Gateway 리소스가 클러스터 스코프 |
| `kube-system` | `ebs-csi-sa` | **ClusterRole** | PV/PVC 관리 | 전체 NS의 PV를 프로비저닝 + AWS API(IRSA) |

`dojangkok`, `data` NS는 자기 NS 안에서만 동작하므로 Role(NS 스코프)이면 충분하다.
`monitoring`, `argocd`, `nginx-gateway`, `kube-system`은 다른 NS 리소스에 접근해야 하므로 ClusterRole이 필수다.

### 설계 원칙

구체적인 SA 목록과 각각의 Role/ClusterRole 바인딩은 **구현 단계에서 정의**한다. 본 설계에서는 아래 원칙을 확정한다.

1. **default SA 사용 금지** — 모든 워크로드에 전용 SA 생성
2. **automountServiceAccountToken: false 기본** — API 접근 불필요 Pod(`dojangkok` NS)에 토큰 미마운트
3. **Namespace 단위 Role 우선** — ClusterRole은 Cross-NS 접근이 필요한 경우(`monitoring`, `argocd` 등)에만 사용
4. **Secret 접근 최소화** — Secret을 읽을 수 있는 SA를 제한하여 민감 데이터 노출 방지

> **결정: 워크로드별 전용 SA + 최소 권한 RBAC — NS별 Role/ClusterRole 분리 적용. V2 IAM/SSH 접근 제어를 K8S에서 동등하게 계승. 구체 SA/Role 목록은 구현 단계에서 정의**

---

## 20. 설계 결정 요약

### 확정 사항

| Q | 주제 | 결정 | 한줄 근거 |
|---|------|------|----------|
| Q3 | GPU | RunPod 외부 (API 방식) | AWS GPU 할당 반려, 비용 절감 |
| Q4 | 노드 사이징 | t4g.large × 6 + CP t4g.medium × 1 | 부하테스트 반영, N-1 69%, 3-AZ 2-2-2 |
| Q6 | AZ 배치 | 2a(CP+W1+W2) / 2b(W3+W4) / 2c(W5+W6) | 3-AZ 균등, AZ 장애 83% 수용 |
| Q7 | 리소스 산정 | 부하테스트 반영 Request/Limit (BE 700m, MySQL 500m 상향) | 부하테스트 피크 기반 산정, 운영 중 조정 전제 |
| Q8 | CNI | Calico + VXLAN | V2 보안그룹 → NetworkPolicy 계승, 모든 Pod 트래픽 VXLAN 캡슐화 |
| Q9 | 네트워크 대역 | Pod 192.168.0.0/16, Service 10.96.0.0/12 (기본값) | VPC(10.10.0.0/18)와 충돌 없음 |
| Q10 | 영구 스토리지 | EBS CSI Driver + gp3 StorageClass (WaitForFirstConsumer) | EBS AZ 종속 인지, Retain/Delete 차등, DB 배치 판단의 전제 |
| Q11 | Ingress | NGINX Gateway Fabric (Gateway API) | 기능 동등하나 동결 Ingress 대신 활발한 Gateway API 표준 + 검증 NGINX 엔진 |
| Q12 | Service 노출 | Gateway Fabric NodePort 전용 노출 | Q11과 일관 — 라우팅 중앙화, 보안 은폐 |
| Q13 | 외부 통신 | NAT Instance × 3 (t4g.nano, AZ별) | 3-AZ 배치와 일치, 월 ~$11.4 |
| Q14 | NetworkPolicy | Default Deny + Whitelist | V2 보안그룹과 동일한 기본 차단 방식 |
| Q15 | TLS | ALB에서 종료, 내부 HTTP | V2와 동일, private 서브넷 내부 평문 허용 |
| Q16 | RBAC/SA | 워크로드별 전용 SA + 최소 권한 RBAC | V2 IAM/SSH 접근 제어 계승, 구체 목록은 구현 시 정의 |
| Q17 | Namespace | 역할별 6개 NS (dojangkok/data/monitoring/argocd/nginx-gateway/kube-system) | 보안 정책 범위 분리, Phase 대응, Helm 기본값 존중 |
| Q2 | Stateful 배치 | 단계적 전환 (Phase 1 EC2, Phase 2 K8S) | 위험 분산, StatefulSet 경험 부족, Phase 1 안정화 후 순차 이관 |
| Q5 | DB HA 토폴로지 | MySQL P+R+Orch, MongoDB P+S+A, Redis 보류, RMQ/Chroma 단일+PVC | 자동 failover(MySQL/MongoDB), 과잉 HA 배제, Redis BE 설계 후 결정 |

### 논의 필요

현재 미결 사항 없음. Redis HA 수준은 BE 설계 확정 후 결정 예정.

### 인프라 구성 요약

**VPC**: 10.10.0.0/18 (ap-northeast-2)

| AZ | public | private | 노드 |
|----|--------|---------|------|
| 2a | 10.10.0.0/24 | 10.10.4.0/22 (K8S) | CP, W1, W2 |
| 2b | 10.10.2.0/24 | 10.10.12.0/22 (K8S) | W3, W4 |
| 2c | 10.10.1.0/24 | 10.10.8.0/22 (K8S) | W5, W6 |
| 2a/2b/2c | — | Data 서브넷 (별도) | DB HA EC2 — 부하테스트 후 확정 (§12) |

**트래픽 흐름**: 클라이언트 → ALB (TLS 종료) → NGINX Gateway Fabric (NodePort) → Pod (ClusterIP)

**외부 통신**: Pod → NAT Instance (t4g.nano × 3, AZ별) → RunPod API / ECR / 외부 API

**보안 통제**: NetworkPolicy (Default Deny + Whitelist) + RBAC/SA (워크로드별 전용 SA + 최소 권한)

### 비용

V2 Prod(~$298) 대비 +$118~133/월 증가(~$416~431/월). 부하테스트 기반 리소스 상향 + 3-AZ N-1 장애 내성 확보에 따른 비용. 서비스 이중화 + 3-AZ 분산 + 단일 클라우드 통합 포함. 상세: [cost-comparison.md](./cost-comparison.md)

---

## 21. 비용 비교

*(전체 Q 결정 후 작성. 상세: [cost-comparison.md](./cost-comparison.md))*

---

## 22. 장애 대응 & Failover

*(전체 Q 결정 후 작성)*

---

## 23. 부록

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
| v1.5.1 | 2026-03-04 | §3: Tier 가중치 표/Peak 공식 제거(부하테스트 후 재산정), 공유 컴포넌트 구성 일치(잠정 표기). §5: DB HA 미확정 반영(둘째·셋째 조건부 표현). |
| v1.6.0 | 2026-03-04 | Part 2 전면 재작성: §6 Calico encapsulation 모드(VXLAN CrossSubnet) + AWS 요구사항 추가, §6→§7→§8 섹션 간 연결 문장, Part 2 전체 평어체 통일. §16 encapsulation 모드 반영. |
| v1.7.0 | 2026-03-04 | §12 전면 재작성(요구사항→Ingress/Gateway API 비교→기능외판단→구현체 선택, 표준 설명 압축, Gateway API 차별점 각주 추가), §13 DaemonSet SPOF 대응 보충 + hostNetwork 대안 언급, §16 RBAC/SA 신규 추가(V2 IAM/SSH→K8S API 접근 제어), §16~§19→§17~§20 번호 이동, §17 설계 결정 요약에 RBAC 행 추가. |
| v1.8.0 | 2026-03-04 | §10 영구 스토리지 전략 신규 추가(EBS CSI Driver, gp3 StorageClass, AZ 종속성), Part 3 이름 변경(배포 및 데이터 전략), §10~§20→§11~§22 번호 이동 + 중복 §10 해소, 목차 전면 재작성(§9 App 배포 누락 수정 포함), 본문 cross-reference 7곳 수정, §19 설계 결정 요약에 스토리지 행 추가. |
| **v2.0.0** | **2026-03-04** | §11 전면 재작성(DB 배치 → Stateful 배치 전략: 단계적 전환 — Phase 1 Stateless K8S + Stateful EC2, Phase 2 순차 이관), §9 V2 배포 설명 수정(PM2/Docker Compose 제거), §10 Phase 1 scope 반영(인프라 Pod만 PVC 대상), §12 Phase 2 컨텍스트 추가, §19 Q2 확정(단계적 전환). |
| v2.1.0 | 2026-03-05 | §12 전면 재작성(DB HA 토폴로지 확정: MySQL P+R+Orchestrator, MongoDB P+S+A, Redis 보류, RabbitMQ/ChromaDB 단일+PVC, 2-AZ quorum 제약 정리), §3 워크로드 합산 업데이트(Redis HA 제거, Orchestrator 추가, ~3950m→~3800m), §4 참조 수치 반영(66%→63%, 78%→76%), §5 cross-reference 확정, §19 Q5 확정 이동. |
| v2.2.0 | 2026-03-05 | §3 RAM Request 증설(FE 512→768MB, BE 1→1.5GB, MySQL 1→1.5GB, MongoDB 512→768MB, ChromaDB 768MB→1GB — RAM 활용률 38%→50%), §6 CrossSubnet 제거(VXLAN Always로 단순화), §8 외부 통신 경로 구분(Pod→외부 Calico SNAT + Worker→외부 직접 NAT), §12·§4 연동 수치 반영. |
| v2.3.0 | 2026-03-05 | §17 Namespace 설계 신규 추가(역할별 6개 NS, Phase 대응, Cross-NS 통신 맵), §18 NetworkPolicy 필수 정책 보완(kubelet Probe + Prometheus 스크래핑 Ingress 허용 추가, 3→5개), §16 kubeadm 인증서 1년 만료 경고 수정, §17~§22→§18~§23 번호 재배치, §20 Q17 추가. |
| v2.4.0 | 2026-03-05 | §17-§18-§19 보안 스택 연결 설명 추가: §17에 계층 구조(NS→NetworkPolicy→RBAC) + NS별 범위 영향 테이블, §18에 NS별 Default Deny + Whitelist 정책 매핑(dojangkok/data/monitoring), §19에 NS별 SA/권한 매핑 테이블(Role vs ClusterRole 분리 근거). |
| v2.4.1 | 2026-03-05 | 문체 통일: §13, §15, §16, §18의 경어체(~합니다/~입니다)를 평어체(~한다/~이다)로 전면 수정. |
| v2.5.0 | 2026-03-05 | §12 DB HA 3-AZ 전환에 따른 연동 수정: §5 DB 배치 제약(2-AZ→3-AZ 독립 EC2 반영, K8S Worker와 분리 명시), §11 Phase 1 EC2 구성(단일→3-AZ HA 클러스터 격상, 자동 Failover 이점 추가). 구 design-step5.md git 추적 제거. |
| v2.6.0 | 2026-03-05 | PL 리뷰 반영: §6 Calico VXLAN MTU 튜닝(veth_mtu=8951), §15 ALB SG NodePort Source 제한 주의사항, §8 NAT Instance ASG(Min=1/Max=1) 래핑, §7 2b AZ 서브넷 + Data 서브넷(별도, 부하테스트 후 확정) 추가, §20 요약표 3-AZ 반영. 파일명 버저닝 제거(design-step5_v2_0_0.md → design-step5.md). |
| **v3.0.0** | **2026-03-08** | **부하테스트(2026-03-07) 반영 + node-sizing.md v4.0.0 동기화**: §3 리소스 산정 부하테스트 반영(BE 500→700m, MySQL 200→500m 상향, RAM 조정), §3 워크로드 합산 재계산(HA ~3800m→~5150m, 공유 컴포넌트 6노드 기준), §4 Worker t4g.large×4→×6(3-AZ 2-2-2, N-1 69%), §5 AZ 배치 2:2→2-2-2(3-AZ), §7 2b private 서브넷 추가(10.10.12.0/22), §8 NAT Instance ×2→×3(3-AZ), §9·§10·§15 cross-reference 6대 반영, §20 설계 결정 요약 갱신. |
