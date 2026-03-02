# 노드 사양 산정 근거 (v2.0.0)

- 작성일: 2026-03-02
- 최종수정일: 2026-03-03
- 작성자: infra (claude-code)
- 상태: draft
- 관련문서: [design-step5.md](./design-step5.md) Q4~Q7

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

### 2.3 공유 컴포넌트 (클러스터 전체 1세트)

| 컴포넌트 | CPU | RAM | 비고 |
|---------|-----|-----|------|
| NGINX Gateway Fabric | 100m | 256MB | Gateway API 컨트롤러 |
| ArgoCD | 300m | 512MB | server + repo-server + controller |
| Prometheus + Alertmanager | 200m | 512MB | kube-prometheus-stack |
| Grafana | 100m | 256MB | 대시보드 |
| Promtail (DaemonSet ×3) | 150m | 192MB | 노드당 50m/64MB |
| **합계** | **~850m** | **~1.7GB** | |

---

## 3. 운영 및 아키텍처 정책

### 3.1 환경 통합: Dev+Prod Namespace 분리

단일 클러스터에서 Dev/Prod를 Namespace로 분리 (Q1 결정).
→ **워크로드 요구량이 2배**. 단, Dev은 Request를 낮게 설정하여 실제 부담은 1.5배 수준.

### 3.2 복제본 정책

| 서비스 | Dev | Prod | 비고 |
|--------|-----|------|------|
| FE | 1 | 2 | AZ 분산 (Anti-Affinity) |
| BE | 1 | 2 | AZ 분산 |
| AI Server | 1 | 1 | RabbitMQ 비동기, HPA로 확장 |
| MySQL | 1 | 1 (+ Replica TBD) | Q5에서 결정 |
| MongoDB | 1 | 1 (+ Secondary TBD) | Q5에서 결정 |
| Redis | 1 | 1 (+ Replica TBD) | Q5에서 결정 |
| RabbitMQ | 1 | 1 | 단일 (미러링 후순위) |
| ChromaDB | 1 | 1 | 단일 |

### 3.3 N-1 생존 원칙

Worker 노드 1대가 다운되어도, **남은 노드들로 Prod 워크로드를 전부 수용 가능**해야 한다.
(Dev는 일시적 Pending 허용)

---

## 4. K8S Request/Limit 산정

### 4.1 산정 원칙

```
Request = 컨테이너가 안정 운영에 필요한 최소 보장 리소스 (스케줄러 배치 기준)
Limit   = 버스트 시 허용되는 최대치 (초과 시 CPU throttle / OOM Kill)
```

- **CPU Request**: 평균 사용량의 3~5배 (저트래픽 Dev 기준이므로 Prod 증가분 + 안전 마진)
- **CPU Limit**: 실측 피크 수준 또는 그 이상 (버스트 허용)
- **RAM Request**: 프로세스 피크 + 20~30% 여유
- **RAM Limit**: Request의 1.5~2배 (OOM 방지)

### 4.2 Prod Request/Limit

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

> **BE CPU Request 500m 근거**: 평균 0.072v이지만 피크 1.81v. Request는 "정상 운영 보장"이므로 평균의 ~7배로 설정.
> JVM은 GC 시 순간 CPU 급등 → 500m이면 GC 외 정상 시간은 throttle 없이 동작.
> 피크 1.81v 버스트는 CPU Limit 2000m으로 수용.

> **FE CPU Request 250m 근거**: 평균 0.037v이지만 SSR 렌더링 시 피크 1.86v까지 버스트.
> Request 250m은 평균의 ~7배. SSR 버스트는 Limit 1500m으로 수용.

> **MySQL RAM 1GB 근거**: InnoDB Buffer Pool을 128MB(기본)→512MB로 증설 + 연결당 메모리 + 쿼리 버퍼.
> 현재 Dev에서 VM 메모리 959MB 중 컨테이너 실사용 ~600MB. Prod에서 Buffer Pool 증설 시 ~800MB 예상.

### 4.3 Dev Request/Limit

Dev은 Prod 대비 Request를 **50% 수준**으로 낮춰 자원 절약. N-1 장애 시 Dev Pod가 먼저 Pending.

| 서비스 | CPU Req | CPU Lim | RAM Req | RAM Lim |
|--------|---------|---------|---------|---------|
| FE | 100m | 1000m | 256MB | 512MB |
| BE | 250m | 1500m | 512MB | 1.5GB |
| AI Server | 100m | 500m | 256MB | 512MB |
| MySQL | 100m | 500m | 512MB | 1GB |
| MongoDB | 100m | 500m | 256MB | 512MB |
| Redis | 50m | 250m | 128MB | 256MB |
| RabbitMQ | 50m | 250m | 128MB | 256MB |
| ChromaDB | 100m | 500m | 384MB | 1GB |

---

## 5. 워크로드 합산

### 5.1 시나리오 A: DB 단일 인스턴스 (HA 없음)

```
─── Prod Namespace ───
  FE ×2:       500m,  1.0GB
  BE ×2:       1000m, 2.0GB
  AI Server:   200m,  512MB
  MySQL:       200m,  1.0GB
  MongoDB:     150m,  512MB
  Redis:       100m,  256MB
  RabbitMQ:    100m,  256MB
  ChromaDB:    200m,  768MB
  Prod 소계:   2450m, 6.3GB

─── Dev Namespace ───
  FE:          100m,  256MB
  BE:          250m,  512MB
  AI Server:   100m,  256MB
  MySQL:       100m,  512MB
  MongoDB:     100m,  256MB
  Redis:       50m,   128MB
  RabbitMQ:    50m,   128MB
  ChromaDB:    100m,  384MB
  Dev 소계:    850m,  2.4GB

─── 공유 컴포넌트 ───
  Gateway + ArgoCD + 모니터링: 850m, 1.7GB

─── 시스템 예약 (Worker 3대) ───
  3 × 500m/1.5GB = 1500m, 4.5GB
──────────────────────────
총 필요: 5650m, 14.9GB
```

### 5.2 시나리오 B: DB HA (Primary-Replica, Q5 결정 시)

시나리오 A에 Prod Replica + Quorum 추가:

```
─── 추가분 (Prod HA) ───
  MySQL Replica:      200m,  1.0GB
  MongoDB Secondary:  150m,  512MB
  MongoDB Arbiter:    50m,   64MB
  Redis Replica:      100m,  256MB
  Redis Sentinel ×3:  150m,  192MB
  HA 추가 소계:       650m,  2.0GB
──────────────────────────
총 필요 (HA 포함): 6300m, 16.9GB
```

### 5.3 요약

| 시나리오 | CPU Request 합계 | RAM Request 합계 |
|---------|-----------------|-----------------|
| A: DB 단일 | 5650m | 14.9GB |
| B: DB HA | 6300m | 16.9GB |

---

## 6. 클라우드 인스턴스 특성 및 노드 선정

### 6.1 워크로드 특성: CPU Bound

| 지표 | 값 | 판단 |
|------|-----|------|
| CPU Request 합계 (HA) | 6300m | 높음 |
| RAM Request 합계 (HA) | 16.9GB | 낮음 |
| CPU:RAM 비율 | 1vCPU : 2.7GB | CPU가 병목 |

→ 메모리 특화(r6g) 불필요. **범용(t4g) 또는 컴퓨팅 특화(c6g)** 가 적합.
→ t4g는 버스트 모델이므로 CPU 크레딧 관리 필요. c6g는 고정 성능이지만 비용 1.5배.

### 6.2 인스턴스 후보 비교

| 인스턴스 | vCPU | RAM | 월비용 | 특성 |
|---------|------|-----|--------|------|
| t4g.large | 2 | 8GB | ~$49 | Burstable, ARM64 |
| **t4g.xlarge** | **4** | **16GB** | **~$98** | Burstable, ARM64 |
| t4g.2xlarge | 8 | 32GB | ~$196 | Burstable, ARM64 |
| c6g.xlarge | 4 | 8GB | ~$98 | 고정 성능, RAM 적음 |
| m6g.xlarge | 4 | 16GB | ~$116 | 고정 성능, 범용 |

### 6.3 Worker 대수별 비교

| 구성 | Allocatable CPU | Allocatable RAM | 월비용 | CPU 활용률 (HA) | N-1 생존 |
|------|----------------|----------------|--------|---------------|---------|
| t4g.large ×4 | 6.0v | 26.0GB | $196 | 6300/6000 = **105% (불가)** | ✗ |
| t4g.large ×5 | 7.5v | 32.5GB | $245 | 6300/7500 = 84% | 제한적 |
| **t4g.xlarge ×3** | **10.5v** | **43.5GB** | **$294** | 6300/10500 = **60%** | **✓** |
| t4g.xlarge ×2 | 7.0v | 29.0GB | $196 | 6300/7000 = 90% | ✗ |
| m6g.xlarge ×3 | 10.5v | 43.5GB | $348 | 60% | ✓ (크레딧 걱정 없음) |

> **Allocatable 산정**: vCPU에서 시스템 예약 0.5v 차감, RAM에서 1.5GB 차감 (노드당)

### 6.4 t4g.xlarge × 3 선정

| 항목 | 시나리오 A (단일) | 시나리오 B (HA) |
|------|-----------------|----------------|
| CPU 활용률 | 5650/10500 = **54%** | 6300/10500 = **60%** |
| RAM 활용률 | 14.9/43.5 = **34%** | 16.9/43.5 = **39%** |
| N-1 시 CPU | 5650/7000 = 81% | 6300/7000 = **90%** |
| N-1 시 판정 | Prod+Dev 수용 가능 | Prod 수용, Dev 일부 Pending |

- 평시 CPU 60%: HPA 버스트 + 향후 서비스 추가 여유
- RAM 39%: JVM Heap 증설, MongoDB 데이터 증가 여유
- N-1 시 90%: Prod은 유지, Dev Pod는 PriorityClass로 후순위 축출

### 6.5 EBS gp3 IOPS

| 서비스 | PVC 크기 | 기본 IOPS | 비고 |
|--------|---------|----------|------|
| MySQL | 100GB | 3000 | InnoDB의 random I/O 처리에 충분 (현재 Dev 3.1% CPU → I/O 병목 아님) |
| MongoDB | 50GB | 3000 | WiredTiger journal 쓰기 |
| 노드 루트 | 80GB | 3000 | 컨테이너 이미지 레이어 + containerd |

> gp3 기본 3000 IOPS는 현재 워크로드에 충분. 향후 MySQL 쿼리 증가 시 IOPS 프로비저닝(최대 16000) 조정.

### 6.6 T시리즈 CPU 크레딧 리스크

**실측 확인 사항**: 현행 V2에서 FE/BE의 CPU 크레딧이 거의 0까지 소진된 이력이 Prometheus에서 확인됨 (30일간 BE 최대 90.3%, FE 최대 92.8%).

**K8S 전환 후 대응**:
1. Worker 3대에 워크로드가 분산되어 **단일 노드 부하가 분산**됨
2. t4g.xlarge의 기본 성능: **40% (1.6vCPU 상시 사용 가능)** — 현재 전체 Request 합산(6.3v) ÷ 3노드 = 노드당 ~2.1v Request이지만, 실제 사용량은 avg 기준 훨씬 낮음
3. CPU Credit Balance를 Prometheus로 모니터링, 알람 설정
4. 고갈 시 **Unlimited Mode 활성화** 또는 노드 스케일아웃

---

## 7. 스케일업 경로

| 조건 | 대응 |
|------|------|
| CPU 일상 80%+ | t4g.2xlarge로 스케일업 (8vCPU, 32GB, ~$196) |
| 특정 노드만 압박 | 해당 노드만 스케일업 |
| Worker 수 부족 | W4 추가 (AZ 균형 배치) |
| 크레딧 반복 고갈 | m6g.xlarge로 교체 (고정 성능, 월 +$18/대) |

---

## 변경 이력

| 버전 | 날짜 | 변경 내용 |
|------|------|----------|
| v1.0.0 | 2026-03-02 | 초안: V2 실측 기반 requests 산정, t4g.xlarge 3대 |
| v2.0.0 | 2026-03-03 | 전면 재작성: Prometheus 실측 데이터(3d+30d) 기반, 4섹션 구조, 컨테이너 레벨 분석, Dev/Prod 분리 산정, HA 시나리오 추가 |
