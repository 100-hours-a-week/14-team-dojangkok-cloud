# 5단계: V3 모니터링 설계 (v1.0.0)

- 작성일: 2026-03-09
- 최종수정일: 2026-03-09
- 작성자: infra (claude-code)
- 상태: draft
- 관련문서: `./design-step5.md` (v3.0.0), `./iac-plan.md` (v1.0.0), `./cicd-plan.md` (v1.0.0)

> **스코프**: V2 모니터링 스택(Prometheus/Loki/Grafana/Tempo + Alloy)을 V3 K8S 환경에 맞게 확장.
> 기존 외부 모니터링 서버는 유지하고, K8S 메트릭 수집 경로를 추가한다.

---

## 목차

1. [V2 → V3 변경 요약](#1-v2--v3-변경-요약)
2. [아키텍처](#2-아키텍처)
3. [메트릭 수집 — Alloy DaemonSet](#3-메트릭-수집--alloy-daemonset)
4. [K8S 메트릭 — kube-state-metrics](#4-k8s-메트릭--kube-state-metrics)
5. [애플리케이션 메트릭](#5-애플리케이션-메트릭)
6. [로그 수집](#6-로그-수집)
7. [Grafana 대시보드](#7-grafana-대시보드)
8. [알림](#8-알림)
9. [구현 순서](#9-구현-순서)

---

## 1. V2 → V3 변경 요약

| 항목 | V2 | V3 |
|------|-----|-----|
| **모니터링 서버** | 외부 EC2 (Docker Compose) | **변경 없음** — 기존 서버 유지 |
| **에이전트** | Alloy (VM별 설치) | Alloy **DaemonSet** (Worker 노드당 1개) |
| **노드 메트릭** | Alloy built-in node-exporter | **동일** |
| **K8S 메트릭** | 없음 | **추가** — kube-state-metrics |
| **앱 메트릭** | Alloy → Prometheus remote-write | **동일** (Pod 엔드포인트 변경) |
| **로그** | Alloy → Loki push | **동일** (컨테이너 로그 경로 변경) |
| **대시보드** | ai-server, node-exporter, rabbitmq, vllm | **추가** — K8S 클러스터, Pod, HPA |

### 변경되지 않는 것

- 모니터링 서버 (Prometheus :9090, Loki :3100, Tempo :3200, Grafana :3000)
- Prometheus remote-write 수신 (Alloy push 방식)
- Grafana datasource 설정
- 기존 대시보드 JSON

### 변경/추가되는 것

- Alloy: VM 직접 설치 → K8S DaemonSet 배포
- kube-state-metrics: K8S 오브젝트 상태 메트릭 (신규)
- 스크래핑 대상: EC2 IP → K8S Pod/Service IP
- 대시보드: K8S 전용 추가
- 알림 규칙: K8S 관련 추가

---

## 2. 아키텍처

### V2 (현재)

```
[AWS EC2 / GCP VM]
  Alloy (systemd)
    └─ node-exporter (built-in)
    └─ app metrics scrape
    └─ container log 수집
        ↓ remote-write / push
[모니터링 서버 EC2]
  Prometheus :9090 ← 메트릭
  Loki :3100      ← 로그
  Tempo :3200     ← 트레이스
  Grafana :3000   ← 시각화
```

### V3 (K8S)

```
[K8S 클러스터]
  ┌──────────────────────────────────────┐
  │ Alloy DaemonSet (Worker 노드당 1개)    │
  │   └─ node-exporter (built-in)         │
  │   └─ Pod 메트릭 scrape (kubelet)       │
  │   └─ 컨테이너 로그 수집 (/var/log/pods) │
  │       ↓ remote-write / push           │
  ├──────────────────────────────────────┤
  │ kube-state-metrics (Deployment × 1)   │
  │   └─ K8S API → 오브젝트 상태 메트릭    │
  │       ↓ Alloy가 scrape               │
  └──────────────────────────────────────┘
        ↓ (NAT Instance → 인터넷 또는 VPC Peering)
[모니터링 서버 EC2 — 기존 유지]
  Prometheus :9090 ← 메트릭 (remote-write)
  Loki :3100      ← 로그 (push)
  Tempo :3200     ← 트레이스 (OTLP)
  Grafana :3000   ← 시각화
```

### 네트워크 경로

Alloy DaemonSet(K8S Worker) → NAT Instance → 모니터링 서버

> 모니터링 서버 SG에 K8S NAT Instance EIP 3개 허용 필요. V2에서 GCP NAT IP를 허용한 것과 동일한 패턴.

---

## 3. 메트릭 수집 — Alloy DaemonSet

### V2 Alloy와 차이점

| 항목 | V2 | V3 |
|------|-----|-----|
| 배포 방식 | systemd (VM에 직접) | K8S DaemonSet |
| 수량 | VM당 1개 (수동 설치) | Worker 노드당 1개 (자동) |
| 설정 배포 | 파일 복사 | ConfigMap |
| 스크래핑 대상 | localhost 앱 포트 | Pod IP (K8S service discovery) |
| 로그 경로 | `/var/log/*.log` | `/var/log/pods/` (containerd) |

### DaemonSet 정의

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: alloy
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: alloy
  template:
    metadata:
      labels:
        app: alloy
    spec:
      serviceAccountName: alloy-sa
      hostNetwork: false
      containers:
      - name: alloy
        image: grafana/alloy:latest
        args:
        - run
        - /etc/alloy/config.alloy
        ports:
        - containerPort: 12345     # Alloy UI
        volumeMounts:
        - name: config
          mountPath: /etc/alloy
        - name: host-proc
          mountPath: /host/proc
          readOnly: true
        - name: host-sys
          mountPath: /host/sys
          readOnly: true
        - name: pod-logs
          mountPath: /var/log/pods
          readOnly: true
        resources:
          requests:
            cpu: 40m
            memory: 48Mi
          limits:
            cpu: 100m
            memory: 128Mi
      volumes:
      - name: config
        configMap:
          name: alloy-config
      - name: host-proc
        hostPath:
          path: /proc
      - name: host-sys
        hostPath:
          path: /sys
      - name: pod-logs
        hostPath:
          path: /var/log/pods
```

> Resource: node-sizing.md §2.3 기준 (40m/48MB per node, 총 6대 = 240m/288MB).

### Alloy 설정 (ConfigMap)

```hcl
// config.alloy (Alloy River 문법)

// ── node-exporter (built-in) ──
prometheus.exporter.unix "node" {
  procfs_path = "/host/proc"
  sysfs_path  = "/host/sys"
}

prometheus.scrape "node" {
  targets    = prometheus.exporter.unix.node.targets
  forward_to = [prometheus.remote_write.monitor.receiver]
}

// ── kubelet 메트릭 ──
discovery.kubernetes "pods" {
  role = "pod"
}

prometheus.scrape "pods" {
  targets    = discovery.kubernetes.pods.targets
  forward_to = [prometheus.remote_write.monitor.receiver]
}

// ── kube-state-metrics scrape ──
prometheus.scrape "kube_state" {
  targets = [{
    __address__ = "kube-state-metrics.monitoring.svc.cluster.local:8080",
  }]
  forward_to = [prometheus.remote_write.monitor.receiver]
}

// ── remote-write to 모니터링 서버 ──
prometheus.remote_write "monitor" {
  endpoint {
    url = "http://{MONITOR_IP}:9090/api/v1/write"
  }
}

// ── 로그 수집 ──
loki.source.kubernetes "pods" {
  targets    = discovery.kubernetes.pods.targets
  forward_to = [loki.write.monitor.receiver]
}

loki.write "monitor" {
  endpoint {
    url = "http://{MONITOR_IP}:3100/loki/api/v1/push"
  }
}
```

### ServiceAccount & RBAC

Alloy가 K8S API로 Pod/Service 정보를 조회해야 하므로 ClusterRole 필요:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: alloy-reader
rules:
- apiGroups: [""]
  resources: ["nodes", "nodes/metrics", "pods", "services", "endpoints"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["nodes/proxy"]
  verbs: ["get"]
```

> design-step5.md §19: monitoring NS의 SA는 ClusterRole (전 NS 접근 필요).

---

## 4. K8S 메트릭 — kube-state-metrics

V2에 없던 신규 컴포넌트. K8S API 서버를 조회하여 오브젝트 상태를 Prometheus 메트릭으로 변환.

### 설치

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-state-metrics prometheus-community/kube-state-metrics \
  --namespace monitoring --create-namespace
```

### 제공 메트릭 (주요)

| 메트릭 | 의미 | 알림 활용 |
|--------|------|----------|
| `kube_deployment_status_replicas_available` | 실행 중인 Pod 수 | < desired → Pod 이상 |
| `kube_pod_status_phase` | Pod 상태 (Running/Pending/Failed) | Pending 지속 → 스케줄링 실패 |
| `kube_node_status_condition` | 노드 상태 (Ready/NotReady) | NotReady → 노드 장애 |
| `kube_pod_container_resource_requests` | Pod Resource Request | 클러스터 활용률 계산 |
| `kube_hpa_status_current_replicas` | HPA 현재 Pod 수 | max 도달 → 스케일 한계 |
| `kube_pod_container_status_restarts_total` | Pod 재시작 횟수 | 급증 → 앱 장애 |

### Resource

```yaml
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 100m
    memory: 128Mi
```

> node-sizing.md §2.3에 kube-state-metrics (50m/64MB) 포함됨.

---

## 5. 애플리케이션 메트릭

### BE (Spring Boot Actuator / Micrometer)

V2와 동일한 메트릭, 수집 경로만 변경:

| V2 | V3 |
|-----|-----|
| Alloy → `EC2_IP:8080/actuator/prometheus` | Alloy → Pod discovery → `:8080/actuator/prometheus` |

K8S에서는 Pod annotation으로 스크래핑 대상 지정:

```yaml
# BE Deployment의 Pod template
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/actuator/prometheus"
```

주요 메트릭:
- `http_server_requests_seconds_*` — API 응답시간
- `jvm_memory_used_bytes` — JVM 힙 메모리
- `jvm_threads_live_threads` — 활성 스레드
- `jvm_gc_pause_seconds_*` — GC Pause

### FE (Next.js)

V2와 동일. 커스텀 메트릭 엔드포인트가 있으면 동일 annotation 방식.

### AI Server (FastAPI)

V2에서 `/metrics` 엔드포인트를 제공하면 동일하게 Pod annotation으로 수집.

---

## 6. 로그 수집

### V2 vs V3

| 항목 | V2 | V3 |
|------|-----|-----|
| 로그 위치 | `/var/log/app.log` (파일) | `/var/log/pods/{ns}_{pod}_{uid}/` (containerd) |
| 수집 방식 | Alloy file tail | Alloy K8S log discovery |
| 라벨 | 수동 (job, instance) | 자동 (namespace, pod, container) |

### K8S 로그 자동 라벨링

Alloy의 `loki.source.kubernetes`는 자동으로:
- `namespace` — Pod가 속한 NS
- `pod` — Pod 이름
- `container` — 컨테이너 이름
- `node` — 실행 중인 노드

Grafana에서 `{namespace="dojangkok", pod=~"be-.*"}` 같은 LogQL 쿼리 가능.

### 로그 보존

기존 Loki 설정 유지. 특별한 변경 없음.

---

## 7. Grafana 대시보드

### 기존 유지

| 대시보드 | 파일 | 변경 |
|---------|------|------|
| AI Server | `ai-server.json` / `ai-server-new.json` | K8S Pod 라벨 기반으로 job 필터 조정 |
| Node Exporter | `node-exporter.json` | K8S Worker 노드로 instance 필터 변경 |
| RabbitMQ | `rabbitmq.json` | Phase 2에서 K8S Pod 메트릭으로 전환 |
| vLLM | `vllm.json` | RunPod 외부이므로 변경 없음 |

### 신규 추가

| 대시보드 | 내용 | 데이터 소스 |
|---------|------|-----------|
| **K8S Cluster** | 노드 상태, Pod 수, Resource 활용률 | kube-state-metrics |
| **K8S Pods** | Pod별 CPU/RAM, 재시작 횟수, 상태 | kube-state-metrics + Alloy |
| **K8S HPA** | HPA 현재/min/max replica, CPU 사용률 | kube-state-metrics |
| **Gateway Fabric** | 요청 처리량, 응답시간, 에러율 | Gateway Fabric 메트릭 |

### K8S Cluster 대시보드 주요 패널

1. **노드 상태** — Ready/NotReady 게이지 (6 Worker + 1 CP)
2. **Pod 상태** — Running/Pending/Failed 파이 차트
3. **CPU 활용률** — 노드별 CPU Request vs Allocatable (%)
4. **RAM 활용률** — 노드별 Memory Request vs Allocatable (%)
5. **N-1 여유** — (Allocatable - Used) / Allocatable, 69% 기준선 표시
6. **Pod 재시작** — 최근 1시간 재시작 Top 5

---

## 8. 알림

### V2 기존 알림

기존 `alert-rules.yml` 유지.

### V3 추가 알림

| 알림 | 조건 | 심각도 |
|------|------|--------|
| **NodeNotReady** | `kube_node_status_condition{condition="Ready",status="true"} == 0` 5분 지속 | Critical |
| **PodCrashLoop** | `kube_pod_container_status_restarts_total` 증가 > 5회/10분 | Warning |
| **PodPending** | `kube_pod_status_phase{phase="Pending"}` 5분 지속 | Warning |
| **HPAMaxReplicas** | `kube_hpa_status_current_replicas == kube_hpa_spec_max_replicas` | Warning |
| **CPUThrottled** | T4g `CPUCreditBalance` < 100 | Warning |
| **CertExpiry** | kubeadm 인증서 만료 30일 전 | Warning |
| **DiskPressure** | 노드 디스크 사용률 > 85% | Warning |

### 알림 채널

V2와 동일 (Grafana → Slack/Discord 등). 기존 설정 유지.

---

## 9. 구현 순서

```
┌───────────────────────────────────────────┐
│ 1. 모니터링 서버 SG 업데이트                │
│    - K8S NAT EIP 3개 허용 (Prometheus, Loki)│
└────────────────┬──────────────────────────┘
                 │
┌────────────────▼──────────────────────────┐
│ 2. monitoring NS + RBAC 생성               │
│    - Namespace, ServiceAccount, ClusterRole │
└────────────────┬──────────────────────────┘
                 │
┌────────────────▼──────────────────────────┐
│ 3. kube-state-metrics 설치 (Helm)          │
│    - 설치 후 메트릭 확인                     │
│      curl kube-state-metrics:8080/metrics  │
└────────────────┬──────────────────────────┘
                 │
┌────────────────▼──────────────────────────┐
│ 4. Alloy DaemonSet 배포                    │
│    - ConfigMap (config.alloy)              │
│    - DaemonSet (6 Pod — Worker당 1개)       │
│    - remote-write 연결 확인                 │
└────────────────┬──────────────────────────┘
                 │
┌────────────────▼──────────────────────────┐
│ 5. Grafana 대시보드 추가                    │
│    - K8S Cluster, Pods, HPA 대시보드        │
│    - 기존 대시보드 라벨 필터 조정             │
└────────────────┬──────────────────────────┘
                 │
┌────────────────▼──────────────────────────┐
│ 6. 알림 규칙 추가                           │
│    - alert-rules.yml에 K8S 규칙 추가        │
│    - Prometheus reload                     │
└───────────────────────────────────────────┘
```

> 핵심: **4번 Alloy DaemonSet 배포 후** Grafana에서 K8S 노드 메트릭이 보이는지 확인. 이 시점에서 node-exporter 메트릭과 kube-state-metrics 모두 수신되어야 한다.

---

## 변경 이력

| 버전 | 날짜 | 변경 내용 |
|------|------|----------|
| v1.0.0 | 2026-03-09 | 초안: V2 모니터링 계승, Alloy DaemonSet, kube-state-metrics, 대시보드/알림 설계 |
