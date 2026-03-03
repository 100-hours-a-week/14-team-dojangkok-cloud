# 노드 사양 산정 근거 (v3.1.1)

- 작성일: 2026-03-02
- 최종수정일: 2026-03-04
- 작성자: infra (claude-code)
- 상태: draft
- 관련문서: [design-step5.md](./design-step5.md) 섹션 4(노드 사이징), 섹션 3(워크로드 분석과 리소스 산정), 섹션 10(DB HA), [cost-comparison.md](./cost-comparison.md)

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

### 1.4 메모리 실측

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

### 1.5 디스크 사용량

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

> Worker **4대** 기준. 4대 합계: 2000m / 6.0GB.

### 2.3 공유 컴포넌트 (잠정)

| 컴포넌트 | CPU | RAM | 비고 | 상태 |
|---------|-----|-----|------|------|
| NGINX Gateway Fabric | 100m | 256MB | Gateway API 컨트롤러 | 확정 |
| ArgoCD | 300m | 512MB | server + repo-server + controller | 잠정 |
| Prometheus + Alertmanager | 200m | 512MB | kube-prometheus-stack | 잠정 |
| Grafana | 100m | 256MB | 대시보드 | 잠정 |
| Alloy (DaemonSet ×4) | 150m | 192MB | 노드당 ~40m/48MB | 잠정 |
| **합계** | **~850m** | **~1.7GB** | | |

> Gateway Fabric만 확정(섹션 12). CD·모니터링·로그 수집은 설계 전이며, 스택 확정 후 수치 재산정 예정.

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

> **잠정 산정**: 저트래픽 실측 기반 초기값. 도커 컨테이너 부하테스트 완료 후 조정 예정.

### 4.1 산정 원칙

```
Request = 실측 피크 × 2~5배 (서비스 특성별)
Limit   = Request × 2~3 (버스트 허용)
```

### 4.2 Prod Request/Limit (잠정)

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

> 부하테스트 후 Request/Limit 값 재산정 예정.

---

## 5. 워크로드 합산

### 5.1 시나리오 A — Prod 단일 (HA 미적용)

| 카테고리 | 구성 | CPU Request | RAM Request |
|----------|------|-------------|-------------|
| App | FE×2, BE×2, AI×1 | 1700m | 3.54GB |
| DB (단일) | MySQL, MongoDB, Redis | 450m | 1.77GB |
| Infra | RabbitMQ, ChromaDB | 300m | 1.02GB |
| **워크로드 소계** | | **2450m** | **6.33GB** |
| 공유 컴포넌트 | | ~850m | ~1.7GB |
| **Prod 합계** | | **~3300m** | **~8.0GB** |

### 5.2 시나리오 B — Prod HA (채택)

| 카테고리 | 구성 | CPU Request | RAM Request |
|----------|------|-------------|-------------|
| **App** | FE×2, BE×2, AI×1 | 1700m | 3.54GB |
| **DB Primary** | MySQL, MongoDB, Redis | 450m | 1.77GB |
| **DB Replica** | MySQL Replica, MongoDB Secondary, Redis Replica | 450m | 1.77GB |
| **Quorum** | MongoDB Arbiter, Redis Sentinel×3 | 200m | 0.26GB |
| **Infra** | RabbitMQ, ChromaDB | 300m | 1.02GB |
| **워크로드 소계** | | **3100m** | **8.35GB** |
| 공유 컴포넌트 | | ~850m | ~1.7GB |
| **Prod 합계** | | **~3950m** | **~10.0GB** |

> HA 추가분: DB Replica(450m/1.77GB) + Quorum(200m/0.26GB) = 650m / 2.0GB.

### 5.3 시스템 예약 요약

| 항목 | CPU | RAM |
|------|-----|-----|
| Worker 시스템 예약 (4대) | 2000m | 6.0GB |
| Prod 합계 (시나리오 B) | ~3950m | ~10.0GB |
| **총 필요량 (시스템 + Prod)** | **~5950m** | **~16.0GB** |

---

## 6. 노드 선정

### 6.1 워크로드 특성: CPU Bound

| 지표 | 값 | 판단 |
|------|-----|------|
| CPU Request 합계 (HA) | ~3950m | 높음 |
| RAM Request 합계 (HA) | ~10.0GB | 낮음 |
| CPU:RAM 비율 | 1vCPU : 2.5GB | CPU가 병목 |

→ 메모리 특화(r6g) 불필요. **범용(t4g)** 이 적합.

### 6.2 후보 비교

| 옵션 | Alloc CPU | Alloc RAM | 월비용 | HA 활용률 | HPA 풀(FE+BE +1) |
|------|-----------|-----------|--------|----------|---------|
| t4g.large × 3 | 4.5v | 19.5GB | $147 | 88% | ✗ (104%) |
| **t4g.large × 4** | **6.0v** | **26.0GB** | **$196** | **66%** | **78%** |
| t4g.xlarge × 2 | 7.0v | 29.0GB | $196 | 56% | 67% |
| t4g.xlarge × 3 | 10.5v | 43.5GB | $294 | 38% | 45% |

- **HA 활용률** = Prod 합계 ~3950m ÷ Alloc CPU
- **HPA 풀** = HPA 최대(~4700m) ÷ Alloc CPU

> Allocatable 산정: vCPU에서 시스템 예약 0.5v 차감, RAM에서 1.5GB 차감 (노드당)

### 6.3 결론: t4g.large × 4

| 항목 | 노드당 | 4대 합계 |
|------|--------|---------|
| 총 vCPU | 2.0 | 8.0 |
| 시스템 예약 (CPU) | 500m | 2000m |
| **Allocatable CPU** | **1.5v** | **6.0v** |
| 총 RAM | 8.0GB | 32.0GB |
| 시스템 예약 (RAM) | 1.5GB | 6.0GB |
| **Allocatable RAM** | **6.5GB** | **26.0GB** |

**선정 근거:**

- 비용 $196/월 — xlarge×2와 동일 비용
- HA 활용률 66% — 목표 범위(60~80%) 내
- HPA 풀스케일 78% — FE+BE 각 +1 시에도 수용 가능
- 4대 분산 — AZ 2:2 균등 배치 가능

### 6.4 EBS gp3 IOPS

| 서비스 | PVC 크기 | 기본 IOPS | 비고 |
|--------|---------|----------|------|
| MySQL | 100GB | 3000 | InnoDB의 random I/O 처리에 충분 (현재 Dev 3.1% CPU → I/O 병목 아님) |
| MongoDB | 50GB | 3000 | WiredTiger journal 쓰기 |
| 노드 루트 | 80GB | 3000 | 컨테이너 이미지 레이어 + containerd |

> gp3 기본 3000 IOPS는 현재 워크로드에 충분. 향후 MySQL 쿼리 증가 시 IOPS 프로비저닝(최대 16000) 조정.

### 6.5 T시리즈 CPU 크레딧 리스크

**실측 확인 사항**: 현행 V2에서 FE/BE의 CPU 크레딧이 거의 0까지 소진된 이력이 Prometheus에서 확인됨 (30일간 BE 최대 90.3%, FE 최대 92.8%).

**K8S 전환 후 대응**:
1. Worker **4대**에 워크로드가 분산되어 **단일 노드 부하가 분산**됨
2. t4g.large의 기본 성능: **30% (0.6vCPU 상시 사용 가능)** — 4대 분산으로 노드당 평균 부하는 baseline 이내
3. CPU Credit Balance를 Prometheus로 모니터링, 알람 설정
4. 고갈 시 **Unlimited Mode 활성화** 또는 m6g.large로 교체

### 6.6 감수 리스크

| 리스크 | 영향 | 완화 방안 |
|--------|------|----------|
| 노드당 alloc 1.5v — BE Limit(2000m) 초과 | 버스트 시 CPU throttle | 실측 피크(1.8v)는 순간적. Limit 1500m 조정 또는 throttle 감수 |
| 실측이 저트래픽 기준 | Prod 부하 예상보다 높을 수 있음 | 부하테스트 후 Request 재조정, 부족 시 xlarge 스케일업 |
| T시리즈 CPU 크레딧 고갈 | 기본 성능(30%)으로 제한 | Unlimited Mode + CloudWatch CPUCreditBalance 알림 |
| HPA 풀스케일 시 78% | FE+BE 동시 +1 시 여유 22% | HPA maxReplicas 제한(FE 3, BE 3). 상시 80%+ 시 W5 추가 |
| 2 AZ 한정 | 단일 AZ 장애 시 50% 노드 손실 | AZ 2:2 배치로 1대 손실 수용, 2대 동시 손실은 감수 |

---

## 7. 스케일업 경로

| 조건 | 대응 | 결과 |
|------|------|------|
| CPU 일상 80%+ | t4g.xlarge로 교체 (4vCPU, 16GB, ~$98/대) | 노드당 alloc 3.5v |
| 특정 노드만 압박 | 해당 노드만 xlarge로 교체 | 혼합 구성 허용 |
| 크레딧 반복 고갈 | m6g.large로 교체 (고정 성능, ~$67/대) | 동일 사양, 크레딧 제한 없음 |
| Worker 수 부족 | **W5 추가** ($49/대, AZ 밸런싱) | 7.5v alloc, 월 $245 |

---

## 변경 이력

| 버전 | 날짜 | 변경 내용 |
|------|------|----------|
| v1.0.0 | 2026-03-02 | 초안: V2 실측 기반 requests 산정, t4g.xlarge 3대 |
| v2.0.0 | 2026-03-03 | 전면 재작성: Prometheus 실측 데이터(3d+30d) 기반, 4섹션 구조, 컨테이너 레벨 분석, Dev/Prod 분리 산정, HA 시나리오 추가 |
| **v3.0.0** | **2026-03-03** | **전면 재작성**: Dev 제거(Prod 전용), Worker 3대→4대, t4g.xlarge×3→t4g.large×4, 리소스 산정 간소화(부하테스트 후 조정 예정), 감수 리스크 추가. design-step5.md v1.4.0과 수치 일치. |
| v3.1.0 | 2026-03-04 | N-1 제거, HPA 스케일아웃 시나리오 추가(FE/BE +1), 비교표·리스크 HPA 기준으로 갱신. design-step5.md v1.5.0 섹션 참조 업데이트. |
| **v3.1.1** | **2026-03-04** | 공유 컴포넌트: Promtail→Alloy, 잠정 표기 추가(Gateway Fabric만 확정, CD·모니터링·로그 수집은 설계 전). |
