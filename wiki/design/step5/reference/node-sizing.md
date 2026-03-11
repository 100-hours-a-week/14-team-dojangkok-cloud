# 노드 사양 산정 근거 (v4.2.0)

- 작성일: 2026-03-02
- 최종수정일: 2026-03-11
- 작성자: infra (claude-code)
- 상태: draft
- 관련문서: [design-step5.md](../design-step5.md) 섹션 4(노드 사이징), 섹션 3(워크로드 분석과 리소스 산정), 섹션 10(DB HA), [cost-comparison.md](./cost-comparison.md)

---

## 요약: 결정 사항

### 노드 구성

**t4g.large × 6 (2-2-2, 3-AZ 균등 배치)** — 월 $294

| 항목 | 노드당 | 6대 합계 |
|------|--------|---------|
| 총 vCPU / Allocatable | 2.0v / 1.5v | 12.0v / **9.0v** |
| 총 RAM / Allocatable | 8.0GB / 6.5GB | 48.0GB / **39.0GB** |

- **N-1 내결함**: 1대 장애 시 5대(7.5v) → 필요 2.89v의 39% → 매우 여유
- **AZ 장애**(2대 손실): 4대(6.0v) → 필요 2.89v의 48% → 여유롭게 수용
- **HPA 풀스케일**(~3840m): 6대(9.0v)의 43% → 충분한 여유
- **장애 blast radius**: 1/6 = 17% (xlarge×3의 33% 대비 절반)
- **초기 배포**: `workers_per_az = 1` (3대)로 시작 → 안정화 후 6대로 스케일업

### K8S 워크로드 (Stateless App 전용)

> DB(MySQL, MongoDB, Redis, RabbitMQ, ChromaDB)는 K8S 외부 EC2에서 영구 운영. [design-step5.md](../design-step5.md) §11 참조.

| 서비스 | CPU Req | CPU Lim | RAM Req | RAM Lim |
|--------|---------|---------|---------|---------|
| FE (×2) | 250m | 1500m | 512MB | 1GB |
| **BE (×2)** | **700m** | **2000m** | **1.5GB** | **2GB** |
| AI Server (×1) | 300m | 1000m | 768MB | 1.5GB |

> **굵은 글씨**: 부하테스트(k6 S02/S03/S05) 결과 반영하여 상향 조정된 항목

### 워크로드 합산

| 카테고리 | CPU Request | RAM Request |
|----------|-------------|-------------|
| App (FE×2, BE×2, AI×1) | 2200m | 4.75GB |
| 공유 컴포넌트 (ArgoCD, Alloy, kube-state-metrics, Gateway Fabric) | ~690m | ~1.1GB |
| **Prod 합계** | **~2890m** | **~5.85GB** |

→ Allocatable 9.0v 대비 활용률 32%. HPA 풀스케일(~3840m) 시에도 43%.

### 스케일업 트리거

| 조건 | 대응 |
|------|------|
| CPU 일상 85%+ | 워커 7대 추가 (3-3-1) |
| Baseline 30% 초과 빈번 | m7g.large로 교체 (비-burstable) |
| 전체 과부하 | t4g.xlarge × 3 전환 (동일 비용, 3대 단순화) |

### 핵심 리스크

| 리스크 | 완화 |
|--------|------|
| BE CPU Limit(2000m) > 노드 alloc(1500m) → throttle 가능 | 실측 피크 908m은 k6 편중. 대부분 Request(700m) 이하 |
| t4g Baseline 30% 초과 → 크레딧 소진 | Unlimited 모드 + CPUCreditBalance 알림 |
| 비용 $196→$294 (+50%) | 부하테스트 기반 불가피. 운영 안정 후 축소 검토 |

---

> 이하 섹션은 위 결정의 **산정 근거 데이터**. DB 워크로드(MySQL, MongoDB, Redis 등)의 실측·산정 데이터도 포함되어 있으나, 이는 EC2 사이징 참고용이며 K8S 워크로드 합산에는 포함되지 않는다.

---

## 1. 현행 애플리케이션 실측 데이터

### 1.1 측정 환경

| 항목 | 값 |
|------|-----|
| 환경 | V2 Dev (AWS + GCP) |
| 수집 출처 | Prometheus node-exporter + 애플리케이션 메트릭 (Grafana 경유) |
| 수집 기간 | 최근 3일 (현재 인스턴스) + 30일 (전체 ASG 인스턴스 이력) |
| 트래픽 수준 | **Dev 저트래픽** (실 사용자 없음, 내부 테스트) |
| 제한사항 | Prod 부하는 더 높을 것. 운영 후 조정 전제 |

### 1.2 현행 인스턴스 사양

| 서비스 | 인스턴스 | vCPU | RAM | 디스크 | 클라우드 |
|--------|---------|------|-----|--------|---------|
| FE (Next.js) | t4g.small | 2 | 1.8GB | 29GB gp3 | AWS |
| BE (Spring Boot) | t4g.small | 2 | 1.8GB | 29GB gp3 | AWS |
| MySQL | t4g.medium | 2 | 3.7GB | 96GB gp3 | AWS |
| Redis | t4g.small | 2 | 1.8GB | 28GB gp3 | AWS |
| RabbitMQ | t4g.small | 2 | 1.8GB | 28GB gp3 | AWS |
| AI Server (FastAPI) | n2d-standard-2 | 2 | 7.8GB | - | GCP |

### 1.3 CPU 실측

#### 현재 활성 인스턴스 (3일)

| 서비스 | CPU 평균 | CPU 최대 | 절대값 평균 | 절대값 피크 |
|--------|---------|---------|-----------|-----------|
| BE | 3.61% | 71.00% | 0.072v | **1.420v** |
| FE | 1.87% | 38.20% | 0.037v | **0.764v** |
| MySQL | 1.18% | 3.13% | 0.024v | 0.063v |
| Redis | 0.72% | 2.58% | 0.014v | 0.052v |
| RabbitMQ | 1.20% | 3.17% | 0.024v | 0.063v |
| AI Server | ~2% | 11.26% | ~0.04v | 0.225v |

#### ASG 전체 인스턴스 역대 최대 (30일, 교체된 인스턴스 포함)

| 서비스 | 최악 피크 인스턴스 | CPU 최대 | 절대값 |
|--------|------------------|---------|--------|
| BE | 10.0.27.79 | **90.3%** | **1.806v** |
| FE | 10.0.7.191 | **92.8%** | **1.856v** |

> **핵심 관찰**: BE/FE의 평균 CPU는 2~4%로 매우 낮지만, 역대 피크는 **90%+** 까지 치솟는다.
> 이는 T시리즈 CPU 크레딧 고갈 이력과 일치하며, **간헐적이지만 극심한 버스트**가 존재함을 의미한다.
> 반면 MySQL/Redis/RabbitMQ/AI Server는 평시와 피크 차이가 크지 않아 **안정적인 워크로드** 패턴을 보인다.

### 1.4 부하테스트 실측 (2026-03-07)

| 항목 | 값 |
|------|-----|
| 환경 | V2 Dev (AWS ALB + ASG BE 4대) |
| 도구 | k6 v1.5.0 |
| 시나리오 | S02(800VU 읽기), S03(400VU CRUD), S05(300VU 체크리스트) |

#### 시나리오별 서버 피크 (Prometheus)

| Service | S02 avg/max | S03 avg/max | S05 avg/max |
|---------|-------------|-------------|-------------|
| BE CPU | 30.6%/90.8% | 21.4%/30.8% | 13.7%/18.9% |
| BE RAM | 1014/1053MB | 1031/1076MB | 1027/1067MB |
| MySQL CPU | 23.5%/32.2% | **68.8%/83.3%** | **61.1%/74.1%** |
| MySQL RAM | 958/959MB | 1012/1053MB | 1071/1074MB |
| Redis CPU | 2.0%/14.4% | 0.8%/0.8% | 0.7%/0.8% |
| RMQ CPU | 1.3%/1.3% | 1.2%/1.7% | 1.3%/1.3% |

#### BE 인스턴스별 CPU (S02 800VU, 4대)

| Instance | avg CPU | max CPU |
|----------|---------|---------|
| 10.0.9.133 | 42.4% | **90.8%** |
| 10.0.24.203 | 36.9% | 66.7% |
| 10.0.11.188 | 25.2% | 34.0% |
| 10.0.25.221 | 22.2% | 32.1% |

> **핵심 발견**: MySQL이 CRUD 시나리오(S03)에서 CPU 83.3% 피크로 **주요 병목**. JVM Heap 26%, GC 0.88%로 애플리케이션 레벨 병목 없음.

### 1.5 메모리 실측

#### VM 레벨 (OS + Docker + 모니터링 에이전트 포함)

| 서비스 | 평균 | 최대 | VM 총 RAM | 사용률 |
|--------|------|------|----------|--------|
| BE | 921~1011MB | **1144MB** | 1843MB | 53~62% |
| FE | 486~625MB | **844MB** | 1843MB | 26~46% |
| MySQL | 846~923MB | 959MB | 3826MB | 22~25% |
| Redis | 410~413MB | 432MB | 1837MB | 22~24% |
| RabbitMQ | 528~533MB | 582MB | 1837MB | 29~32% |
| AI Server | 758MB | 875MB | 7939MB | 10~11% |

#### 애플리케이션 프로세스 레벨 (컨테이너 실사용량 추정 근거)

| 서비스 | 프로세스 메모리 | 비고 |
|--------|---------------|------|
| BE (JVM) | Heap ~86MB (현시점) + Metaspace | JVM RSS 전체는 ~700~900MB. VM 메모리와의 차이 ~200~300MB는 OS/Docker/에이전트 |
| AI Server (Python) | **221MB** RSS | FastAPI 프로세스 단독. VM 875MB와의 차이 ~650MB는 OS/에이전트 (GCP 8GB 인스턴스라 여유) |
| Redis | **1.4MB** 실데이터 | 현재 데이터 극소량. Prod에서 세션/캐시 증가 예상 |
| RabbitMQ (Erlang) | **135MB** RSS | 큐 메시지가 적은 상태. Prod 부하 시 증가 예상 |
| MySQL | InnoDB Buffer Pool **128MB** (기본값) | 현재 기본 설정. Prod에서 512MB+ 증설 권장 |

> **VM 메모리 → 컨테이너 메모리 변환**: VM 측정값에서 OS+Docker+에이전트 오버헤드(~200~400MB)를 빼야 컨테이너 실사용량.
> 단, K8S에서는 컨테이너 Limit 초과 시 OOM Kill되므로 **프로세스 피크 + 여유분**으로 설정해야 안전.

### 1.6 디스크 사용량

| 서비스 | 디스크 크기 | 사용률 | 실사용량 |
|--------|-----------|--------|---------|
| MySQL | 96GB | 6.2% | ~6GB |
| BE | 29GB | 13.6% | ~4GB |
| FE | 29GB | 11.5% | ~3GB |
| Redis | 28GB | 11.8% | ~3GB |
| RabbitMQ | 28GB | 11.8% | ~3GB |

> 전체적으로 디스크는 여유. Dev 환경이라 데이터 축적이 적음.

---

## 2. K8S 자체 및 공통 인프라 오버헤드

### 2.1 Control Plane

| 컴포넌트 | CPU | RAM | 비고 |
|---------|-----|-----|------|
| etcd | ~0.5v | ~500MB | 워크로드 규모 소 |
| kube-apiserver | ~0.5v | ~500MB | |
| kube-scheduler | ~0.1v | ~100MB | |
| kube-controller-manager | ~0.1v | ~200MB | |
| kubelet + OS | ~0.3v | ~500MB | |
| **합계** | **~1.5v** | **~1.8GB** | |

→ **t4g.medium (2vCPU, 4GB)** 선택. kubeadm 최소 요구(2vCPU, 2GB) 충족, 여유 2.2GB.

### 2.2 Worker 노드당 시스템 예약

| 컴포넌트 | CPU | RAM | 비고 |
|---------|-----|-----|------|
| kubelet | 100m | 200MB | |
| kube-proxy | 100m | 128MB | |
| Calico (CNI) | 150m | 200MB | IP-in-IP 모드 |
| containerd | 100m | 200MB | |
| node-exporter (DaemonSet) | 50m | 64MB | 모니터링 |
| OS 커널/기타 | - | ~700MB | |
| **합계** | **~500m** | **~1.5GB** | 노드당 |

> Worker **6대** 기준 (3-AZ, 2-2-2). 6대 합계: 3000m / 9.0GB.

### 2.3 공유 컴포넌트

> 하이브리드 모니터링 결정에 따라 Prometheus/Grafana는 외부 EC2에서 운영. K8S에는 수집기(Alloy, kube-state-metrics)만 배치.

| 컴포넌트 | CPU | RAM | 비고 | 상태 |
|---------|-----|-----|------|------|
| NGINX Gateway Fabric | 100m | 256MB | Gateway API 컨트롤러 | 확정 |
| ArgoCD | 300m | 512MB | server + repo-server + controller | 잠정 |
| kube-state-metrics | 50m | 64MB | K8S 오브젝트 상태 메트릭 | 잠정 |
| Alloy (DaemonSet ×6) | 240m | 288MB | 노드당 ~40m/48MB | 잠정 |
| **합계** | **~690m** | **~1.1GB** | | |

> Gateway Fabric만 확정. CD·모니터링 수집기는 설계 확정 후 수치 재산정 예정. Prometheus/Grafana는 외부 EC2 유지([monitoring-plan.md](./monitoring-plan.md) §1 참조).

---

## 3. 운영 및 아키텍처 정책

### 3.1 복제본 정책

| 서비스 | Prod 인스턴스 | 배포 방식 |
|--------|-------------|----------|
| FE | 2 | Deployment (anti-affinity) |
| BE | 2 | Deployment (anti-affinity) |
| AI Server | 1 | Deployment (HPA로 확장) |
| MySQL | 1 Primary + 1 Replica | StatefulSet |
| MongoDB | 1 Primary + 1 Secondary + 1 Arbiter | StatefulSet + Deployment |
| Redis | 1 Master + 1 Replica + 3 Sentinel | StatefulSet + Deployment |
| RabbitMQ | 1 | Deployment (단일) |
| ChromaDB | 1 | Deployment (단일) |

### 3.2 HPA 스케일아웃 정책

FE/BE에 HPA를 적용하여 트래픽 급증 시 자동 확장. HPA 풀스케일 시 리소스 증가:

| 시나리오 | 추가 CPU | 추가 RAM | Prod 합계 |
|----------|---------|---------|----------|
| 기본 HA (FE×2, BE×2) | — | — | ~3950m |
| FE +1 (→3대) | +250m | +512MB | ~4200m |
| BE +1 (→3대) | +500m | +1GB | ~4450m |
| FE+BE 각 +1 | +750m | +1.5GB | ~4700m |

> HPA maxReplicas는 Worker allocatable 여유에 따라 결정. 노드 선정(섹션 6)에서 HPA 수용 범위를 비교.

---

## 4. Prod Request/Limit 산정

> **부하테스트 반영**: 저트래픽 실측 + k6 부하테스트(S02/S03/S05) 피크 기반 산정. BE, MySQL은 부하테스트 결과로 상향 조정.

### 4.1 산정 원칙

```
Request = 실측 피크(부하테스트 우선) × headroom (서비스 특성별)
Limit   = Request × 2~3 (burst 수용)
```

> 부하테스트 데이터가 있는 서비스(BE, MySQL, Redis)는 부하테스트 피크 기준.
> 부하테스트 미포함 서비스는 저트래픽 피크 × 2~5배 유지.

### 4.2 Prod Request/Limit

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

> BE Request 700m: 4대 평균 피크 306m × 2.3x headroom. Limit 2000m은 로드밸런싱 불균형 시 908m 버스트 수용.
> MySQL Request 500m: 저트래픽 62m → 부하테스트 833m 급등. CRUD 시나리오에서 단일 DB가 전체 부하 수용. RAM도 1074MB 피크 반영.

---

## 5. 워크로드 합산

### 5.1 시나리오 A — Prod 단일 (HA 미적용)

| 카테고리 | 구성 | CPU Request | RAM Request |
|----------|------|-------------|-------------|
| App | FE×2, BE×2, AI×1 | 2100m | 4.77GB |
| DB (단일) | MySQL, MongoDB, Redis | 750m | 2.25GB |
| Infra | RabbitMQ, ChromaDB | 300m | 1.26GB |
| **워크로드 소계** | | **3150m** | **8.28GB** |
| 공유 컴포넌트 (6노드) | | ~1050m | ~1.7GB |
| **Prod 합계** | | **~4200m** | **~10.0GB** |

### 5.2 시나리오 B — Prod HA (채택)

| 카테고리 | 구성 | CPU Request | RAM Request |
|----------|------|-------------|-------------|
| **App** | FE×2, BE×2, AI×1 | 2100m | 4.77GB |
| **DB Primary** | MySQL, MongoDB, Redis | 750m | 2.25GB |
| **DB Replica** | MySQL Replica, MongoDB Secondary, Redis Replica | 750m | 2.25GB |
| **Quorum** | MongoDB Arbiter, Redis Sentinel×3 | 200m | 0.26GB |
| **Infra** | RabbitMQ, ChromaDB | 300m | 1.26GB |
| **워크로드 소계** | | **4100m** | **10.79GB** |
| 공유 컴포넌트 (6노드) | | ~1050m | ~1.7GB |
| **Prod 합계** | | **~5150m** | **~12.5GB** |

> HA 추가분: DB Replica(750m/2.25GB) + Quorum(200m/0.26GB) = 950m / 2.51GB.

### 5.3 시스템 예약 요약

| 항목 | CPU | RAM |
|------|-----|-----|
| Worker 시스템 예약 (6대) | 3000m | 9.0GB |
| Prod 합계 (시나리오 B) | ~5150m | ~12.5GB |
| **총 필요량 (시스템 + Prod)** | **~8150m** | **~21.5GB** |

---

## 6. 노드 선정 (3-AZ)

> 3-AZ 배포 전제. 노드 수는 3의 배수(3, 6, 9)로 AZ 균등 배치.

### 6.1 워크로드 특성: CPU Bound

| 지표 | 값 | 판단 |
|------|-----|------|
| CPU Request 합계 (HA) | ~5150m | 높음 |
| RAM Request 합계 (HA) | ~12.5GB | 보통 |
| CPU:RAM 비율 | 1vCPU : 2.4GB | CPU가 병목 |

→ 메모리 특화(r6g) 불필요. **범용(t4g)** 이 적합.

### 6.2 후보 비교

| 옵션 | AZ 배치 | Alloc CPU | Alloc RAM | 월비용 | HA 활용률 | N-1 (HA) |
|------|---------|-----------|-----------|--------|----------|----------|
| t4g.large × 3 | 1-1-1 | 4.5v | 19.5GB | $147 | ✗ (108%) | ✗ (146%) |
| t4g.large × 4 (구) | 2-2-0 | 6.0v | 26.0GB | $196 | 83% | ✗ (110%) |
| **t4g.large × 6** | **2-2-2** | **9.0v** | **39.0GB** | **$294** | **57%** | **69%** |
| t4g.xlarge × 3 | 1-1-1 | 10.5v | 43.5GB | $294 | 46% | 69% |

- **HA 활용률** = Prod 필요 CPU ÷ Alloc CPU
- **N-1 (HA)** = Prod 필요 CPU ÷ (Alloc CPU − 노드 1대분)
- t4g.large × 4 (구 결론)는 부하테스트 반영 후 N-1 110%로 불가 판정

### 6.3 t4g.large × 6 vs t4g.xlarge × 3

동일 비용($294/월), 동일 N-1(69%)이므로 구조적 차이 비교:

| 비교 항목 | t4g.large × 6 | t4g.xlarge × 3 |
|-----------|---------------|----------------|
| 노드당 Alloc CPU | 1.5v | 3.5v |
| N-1 잔여 | 5대 = 7.5v | 2대 = 7.0v |
| Pod 분산 유연성 | 높음 (6대) | 낮음 (3대) |
| anti-affinity 효과 | DB/App 분리 용이 | 노드 수 적어 제약 |
| 장애 blast radius | 작음 (1/6 = 17%) | 큼 (1/3 = 33%) |

### 6.4 결론: t4g.large × 6 (2-2-2)

> **운영 참고**: Terraform `workers_per_az` 변수로 AZ당 워커 수 조절 가능. 초기 배포는 `workers_per_az = 1` (1-1-1, 3대)로 시작, 안정화 후 2로 스케일업.

| 항목 | 노드당 | 6대 합계 |
|------|--------|---------|
| 총 vCPU | 2.0 | 12.0 |
| 시스템 예약 (CPU) | 500m | 3000m |
| **Allocatable CPU** | **1.5v** | **9.0v** |
| 총 RAM | 8.0GB | 48.0GB |
| 시스템 예약 (RAM) | 1.5GB | 9.0GB |
| **Allocatable RAM** | **6.5GB** | **39.0GB** |

**선정 근거:**

- 3-AZ 균등 배치: 2-2-2 구성으로 단일 AZ 장애 시 4대(6.0v) 잔여
- N-1 69%: 1대 장애 시 5대(7.5v)로 여유롭게 수용
- AZ 장애(2대 손실) 시: 4대(6.0v) → 필요 4950m/6000m = 83% (수용 가능)
- Pod 분산: 6대로 anti-affinity, DB/App 노드 분리 유연
- 비용 $294/월: xlarge×3과 동일하나 장애 blast radius 작음

### 6.5 EBS gp3 IOPS

| 서비스 | PVC 크기 | 기본 IOPS | 비고 |
|--------|---------|----------|------|
| MySQL | 100GB | 3000 | InnoDB의 random I/O 처리에 충분 |
| MongoDB | 50GB | 3000 | WiredTiger journal 쓰기 |
| 노드 루트 | 80GB | 3000 | 컨테이너 이미지 레이어 + containerd |

> gp3 기본 3000 IOPS는 현재 워크로드에 충분. 향후 MySQL 쿼리 증가 시 IOPS 프로비저닝(최대 16000) 조정.

### 6.6 T시리즈 CPU 크레딧

| 항목 | 값 |
|------|-----|
| t4g.large 기준 CPU | 30% baseline (600m / 2vCPU) |
| Unlimited 모드 | 기본 활성 |
| 6대 분산 효과 | 개별 노드 burst 빈도 감소 |

> Worker 6대 분산으로 노드당 평균 부하 감소. Baseline 초과 빈도가 줄어 크레딧 소진 위험 완화.

### 6.7 감수 리스크

| 리스크 | 영향 | 완화 방안 |
|--------|------|----------|
| 6대 운영 오버헤드 | 관리 복잡도 증가 | EKS 관리형 노드그룹으로 자동화 |
| DB I/O 경합 (같은 노드) | StatefulSet 성능 저하 가능 | anti-affinity로 DB 노드 분산, gp3 IOPS 모니터링 |
| t4g Baseline 30% 초과 | 크레딧 소진 시 throttling | Unlimited 모드 + CloudWatch CPUCreditBalance 알림 |
| 비용 증가 ($196→$294) | +50% 비용 | 부하테스트 결과 불가피. 운영 안정 후 노드 축소 검토 |

---

## 7. 스케일업 경로

| 조건 | 대응 | 결과 |
|------|------|------|
| CPU 일상 85%+ | **W7 추가** (t4g.large, 3-3-1 AZ) | 10.5v alloc, 월 $343 |
| 특정 노드만 압박 | 해당 노드 **xlarge로 교체** | 혼합 구성 허용 |
| Baseline 초과 빈번 | **m7g.large로 교체** (비-burstable) | 동일 사양, 크레딧 제한 없음 |
| 전체적 과부하 | **t4g.xlarge × 3으로 전환** | 10.5v alloc, 동일 비용, 3대로 단순화 |

---

## 변경 이력

| 버전 | 날짜 | 변경 내용 |
|------|------|----------|
| v1.0.0 | 2026-03-02 | 초안: V2 실측 기반 requests 산정, t4g.xlarge 3대 |
| v2.0.0 | 2026-03-03 | 전면 재작성: Prometheus 실측 데이터(3d+30d) 기반, 4섹션 구조, 컨테이너 레벨 분석, Dev/Prod 분리 산정, HA 시나리오 추가 |
| v3.0.0 | 2026-03-03 | 전면 재작성: Dev 제거(Prod 전용), Worker 3대→4대, t4g.xlarge×3→t4g.large×4, 리소스 산정 간소화, 감수 리스크 추가. |
| v3.1.0 | 2026-03-04 | N-1 제거, HPA 스케일아웃 시나리오 추가(FE/BE +1), 비교표·리스크 HPA 기준으로 갱신. |
| v3.1.1 | 2026-03-04 | 공유 컴포넌트: Promtail→Alloy, 잠정 표기 추가. |
| **v4.0.0** | **2026-03-07** | **부하테스트 반영**: k6 부하테스트(S02/S03/S05) 피크 데이터 추가(§1.4), BE/MySQL Request/Limit 상향(BE 500→700m, MySQL 200→500m), 3-AZ 전환(t4g.large×4→×6, 2-2-2), 워크로드 합산 재계산. |
| v4.1.0 | 2026-03-11 | 문서 구조 개선: 결정 사항 요약 섹션을 문서 앞단에 배치. DB EC2 이관 결정 반영(K8S 워크로드에서 DB 제외). |
| **v4.2.0** | **2026-03-11** | 하이브리드 모니터링 반영: §2.3 공유 컴포넌트에서 Prometheus/Grafana 제거, kube-state-metrics 추가(~940m→~690m). 요약 수치 연동(Prod ~2890m, HA 32%, N-1 39%). |
