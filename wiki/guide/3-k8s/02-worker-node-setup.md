# 워커노드 충원 클러스터 세팅 가이드

- 작성일: 2026-03-22
- 작성자: Claude Code
- 관련문서: `IaC/3-v3/ansible/roles/` (원본 Ansible roles)

## 개요

V3 K8S 클러스터에 새 워커노드를 추가할 때 사용하는 수동 세팅 가이드.
Terraform으로 EC2 생성 후, SSM으로 각 워커에 접속하여 아래 명령어를 순서대로 실행한다.

**환경:** Ubuntu 24.04 LTS (ARM64) / K8S 1.31.0 / containerd 1.7 / Calico VXLAN

---

## 사전 조건

- Terraform apply 완료 → 새 EC2 running 상태
- SSM Agent 설치됨 (user_data로 자동 설치)
- CP 노드 정상 동작 중

## Step 0: SSM 접속

```bash
aws ssm start-session --target <INSTANCE_ID> --region ap-northeast-2
sudo -i
```

---

## Step 1: 시스템 패키지 설치

```bash
apt-get update -qq
apt-get install -y apt-transport-https ca-certificates curl gnupg socat conntrack ipset
```

## Step 2: Swap 비활성화

```bash
swapoff -a
sed -i '/swap/d' /etc/fstab
```

## Step 3: 커널 모듈 로드

```bash
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter
```

## Step 4: sysctl 파라미터

```bash
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
fs.inotify.max_user_instances = 512
fs.inotify.max_user_watches = 524288
EOF

sysctl --system
```

## Step 5: containerd 설치

```bash
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# SystemdCgroup 활성화 (필수)
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl enable containerd
systemctl restart containerd
```

검증: `systemctl is-active containerd` → active

## Step 6: kubeadm / kubelet / kubectl 설치

```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | \
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | \
  tee /etc/apt/sources.list.d/kubernetes.list

apt-get update -qq
apt-get install -y kubeadm=1.31.0-* kubelet=1.31.0-* kubectl=1.31.0-*

apt-mark hold kubeadm kubelet kubectl
systemctl enable kubelet
```

검증: `kubeadm version` → v1.31.0

## Step 7: ECR Credential Provider 설치

```bash
wget -q -O /usr/local/bin/ecr-credential-provider \
  https://artifacts.k8s.io/binaries/cloud-provider-aws/v1.31.0/linux/arm64/ecr-credential-provider-linux-arm64

chmod 0755 /usr/local/bin/ecr-credential-provider

cat > /etc/kubernetes/ecr-credential-provider-config.yaml <<'EOF'
apiVersion: kubelet.config.k8s.io/v1
kind: CredentialProviderConfig
providers:
  - name: ecr-credential-provider
    matchImages:
      - "*.dkr.ecr.*.amazonaws.com"
      - "*.dkr.ecr.*.amazonaws.com.cn"
      - "*.dkr.ecr-fips.*.amazonaws.com"
    defaultCacheDuration: "12h"
    apiVersion: credentialprovider.kubelet.k8s.io/v1
EOF

cat > /etc/default/kubelet <<'EOF'
KUBELET_EXTRA_ARGS=--resolv-conf=/run/systemd/resolve/resolv.conf --image-credential-provider-config=/etc/kubernetes/ecr-credential-provider-config.yaml --image-credential-provider-bin-dir=/usr/local/bin
EOF
```

---

## Step 8: 클러스터 Join

### 8-1. CP에서 join 토큰 생성

```bash
# CP 접속
aws ssm start-session --target i-0d768d11541b6ab6f --region ap-northeast-2

sudo kubeadm token create --print-join-command --ttl=2h
```

### 8-2. 새 워커에서 join 실행

```bash
# CP에서 출력된 명령어 그대로 실행
kubeadm join 10.0.48.x:6443 \
  --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:xxxx...
```

검증: `systemctl is-active kubelet` → active

## Step 9: 노드 라벨 (CP에서 실행)

```bash
# <NODE_NAME> = EC2 instance-id
# <AZ> = ap-northeast-2a / 2b / 2c

kubectl label node <NODE_NAME> \
  node-role.kubernetes.io/worker= \
  dojangkok.cloud/nodepool=default \
  topology.kubernetes.io/zone=<AZ> \
  --overwrite
```

## Step 10: 최종 검증 (CP에서 실행)

```bash
kubectl get nodes -o wide
# 새 워커 Ready 확인

kubectl get pods -n calico-system -o wide | grep <NEW_NODE_NAME>
# Calico 자동 배포 확인
```

---

## 트러블슈팅

| 증상 | 확인 / 해결 |
|------|------------|
| token expired | CP에서 `kubeadm token create --print-join-command --ttl=2h` |
| connection refused | `curl -k https://10.0.48.x:6443/healthz` → SG 6443/tcp 확인 |
| kubelet 안됨 | `journalctl -u kubelet -n 50` / containerd 소켓 확인 |
| NotReady 지속 | Calico DaemonSet 자동 배포 대기 (1~2분) |
| ECR pull 실패 | `/usr/local/bin/ecr-credential-provider` 존재 + `/etc/default/kubelet` 확인 → `systemctl restart kubelet` |

---

## 체크리스트

| # | 작업 | 위치 | 검증 |
|---|------|------|------|
| 0 | SSM 접속 + root | 워커 | |
| 1 | 패키지 설치 | 워커 | |
| 2 | Swap off | 워커 | |
| 3 | 커널 모듈 | 워커 | |
| 4 | sysctl | 워커 | |
| 5 | containerd | 워커 | `is-active` |
| 6 | kubeadm/kubelet | 워커 | `kubeadm version` |
| 7 | ECR provider | 워커 | `--version` |
| 8 | kubeadm join | CP→워커 | `is-active kubelet` |
| 9 | 라벨 | CP | |
| 10 | 검증 | CP | `get nodes` → Ready |
