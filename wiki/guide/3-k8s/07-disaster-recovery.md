# 장애 복구 가이드

## 1. etcd 백업 현황

| 항목 | 값 |
|------|-----|
| 클러스터 | dojangkok-v3 (kubeadm, stacked etcd) |
| CP | i-0d768d11541b6ab6f |
| etcd 버전 | 3.5.15 (K8S 1.31.0 번들) |
| 백업 버킷 | s3://dojangkok-v3-etcd-backup |
| 백업 주기 | systemd timer (1h) |
| S3 보존 | 7일 자동 만료 |

### 백업 흐름

```
systemd timer → etcd-backup.sh
  1. etcdctl snapshot save → /var/lib/etcd-backup/
  2. etcdctl snapshot status → 무결성 검증
  3. aws s3 cp → S3 업로드
  4. 로컬 정리 (최근 2개 유지)
```

### 백업 상태 확인

```bash
# CP에서
systemctl list-timers etcd-backup.timer
sudo journalctl -u etcd-backup.service -n 30
ls -la /var/lib/etcd-backup/
aws s3 ls s3://dojangkok-v3-etcd-backup/snapshots/ --recursive
```

---

## 2. Worker 노드 장애

```bash
# 1. 노드 상태 확인
kubectl get nodes
# NotReady → 5분 후 Pod 자동 eviction

# 2. EC2 상태 확인 → Start 또는 Terminate
# 3. 새 노드: Terraform 재생성 → 수동 세팅 (02-worker-node-setup.md)
```

---

## 3. CP 장애 수동 복구 (전체 절차)

### 전제

- S3에 유효한 etcd 스냅샷 존재
- Worker 노드는 살아있는 상태
- 최대 데이터 손실: 마지막 백업 이후 (최대 1시간)
- ArgoCD GitOps로 앱은 자동 재수렴

### 복구 흐름

```
GitHub Actions → Terraform apply → 새 CP EC2 생성
  ↓
SSM 접속 → 이하 모든 작업 새 CP에서 수동 진행
```

---

### Step 1. Terraform으로 새 CP 생성

```
GitHub → Actions → "Terraform V3 K8S"
  → workflow_dispatch → action: apply → ref: <커밋 SHA>
```

### Step 2. SSM 접속

```bash
aws ssm start-session --target <새_CP_인스턴스_ID> --region ap-northeast-2
sudo -i
```

### Step 3. 기본 패키지

```bash
apt update
apt install -y apt-transport-https ca-certificates curl gnupg socat conntrack ipset unzip
swapoff -a
sed -i '/\sswap\s/d' /etc/fstab
```

### Step 4. 커널 모듈 + sysctl

```bash
modprobe overlay && modprobe br_netfilter

cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
EOF

cat > /etc/sysctl.d/k8s.conf << 'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
fs.inotify.max_user_instances = 512
fs.inotify.max_user_watches = 524288
EOF

sysctl --system
```

### Step 5. containerd

```bash
apt install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd
```

### Step 6. kubeadm / kubelet / kubectl

```bash
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" > /etc/apt/sources.list.d/kubernetes.list

apt update
apt install -y kubeadm=1.31.0-* kubelet=1.31.0-* kubectl=1.31.0-*
apt-mark hold kubeadm kubelet kubectl
systemctl enable kubelet
```

### Step 7. ECR Credential Provider

```bash
curl -Lo /usr/local/bin/ecr-credential-provider \
  https://artifacts.k8s.io/binaries/cloud-provider-aws/v1.31.0/linux/arm64/ecr-credential-provider-linux-arm64
chmod 755 /usr/local/bin/ecr-credential-provider

mkdir -p /etc/kubernetes
cat > /etc/kubernetes/ecr-credential-provider-config.yaml << 'EOF'
apiVersion: kubelet.config.k8s.io/v1
kind: CredentialProviderConfig
providers:
  - name: ecr-credential-provider
    matchImages:
      - "*.dkr.ecr.*.amazonaws.com"
    defaultCacheDuration: "12h"
    apiVersion: credentialprovider.kubelet.k8s.io/v1
EOF

cat > /etc/default/kubelet << 'EOF'
KUBELET_EXTRA_ARGS=--resolv-conf=/run/systemd/resolve/resolv.conf --image-credential-provider-config=/etc/kubernetes/ecr-credential-provider-config.yaml --image-credential-provider-bin-dir=/usr/local/bin
EOF
```

### Step 8. AWS CLI + etcdctl

```bash
curl -LO https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip
unzip awscli-exe-linux-aarch64.zip && ./aws/install
rm -rf awscli-exe-linux-aarch64.zip aws/

curl -LO https://github.com/etcd-io/etcd/releases/download/v3.5.15/etcd-v3.5.15-linux-arm64.tar.gz
tar xzf etcd-v3.5.15-linux-arm64.tar.gz etcd-v3.5.15-linux-arm64/etcdctl
mv etcd-v3.5.15-linux-arm64/etcdctl /usr/local/bin/
chmod 755 /usr/local/bin/etcdctl
rm -rf etcd-v3.5.15-linux-arm64*
```

### Step 9. etcd 스냅샷 복원

```bash
# 최신 스냅샷 확인
aws s3 ls s3://dojangkok-v3-etcd-backup/snapshots/ --recursive --region ap-northeast-2

# 다운로드
aws s3 cp s3://dojangkok-v3-etcd-backup/snapshots/ip-10-0-48-191/<최신파일>.db \
  /tmp/etcd-snapshot.db --region ap-northeast-2

# 무결성 확인
etcdctl snapshot status /tmp/etcd-snapshot.db --write-out=table

# 복원
rm -rf /var/lib/etcd
ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-snapshot.db --data-dir=/var/lib/etcd
```

### Step 10. kubeadm init (복원된 etcd)

```bash
cat > /tmp/kubeadm-config.yaml << 'EOF'
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v1.31.0
networking:
  podSubnet: 192.168.0.0/16
  serviceSubnet: 10.96.0.0/12
etcd:
  local:
    dataDir: /var/lib/etcd
EOF

kubeadm init --config /tmp/kubeadm-config.yaml \
  --ignore-preflight-errors=DirAvailable--var-lib-etcd
```

### Step 11. kubeconfig + Helm

```bash
mkdir -p /home/ubuntu/.kube
cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config
export KUBECONFIG=/home/ubuntu/.kube/config

curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Step 12. Worker 재연결

```bash
# Worker kubelet이 자동 재접속 시도
# 안 되면 토큰 재생성:
kubeadm token create --print-join-command --ttl=2h

# 각 Worker에서 (SSM 접속):
kubeadm reset -f
kubeadm join <CP_IP>:6443 --token <token> --discovery-token-ca-cert-hash <hash>
```

### Step 13. 검증

```bash
kubectl get nodes
kubectl get pods -A
kubectl get applications -n argocd
```

### Step 14. etcd 백업 타이머 복원

```bash
mkdir -p /var/lib/etcd-backup && chmod 700 /var/lib/etcd-backup
# etcd-backup.sh, .service, .timer 배포 (Ansible etcd-backup role 참고)
systemctl daemon-reload
systemctl enable --now etcd-backup.timer
```

---

## 4. 전체 클러스터 재구축 (최후 수단)

```bash
cd IaC/3-v3/aws/environments/k8s-dev
terraform destroy
terraform apply

cd IaC/3-v3/ansible
ansible-playbook -i inventory/aws_ec2.yaml playbooks/site.yml \
  -e ansible_aws_ssm_profile=tf

# ArgoCD가 앱 자동 재배포 → 총 ~30분
```

---

## 5. 복구 후 자동 수렴

| 컴포넌트 | 복구 방식 |
|----------|----------|
| K8S 리소스 | etcd 스냅샷에서 복원 |
| 앱 (FE, BE, AI, Chat) | ArgoCD auto-sync |
| CNI (Calico) | DaemonSet 자동 복구 |
| Secrets | ESO 재동기화 |
| 모니터링 (Alloy) | DaemonSet 자동 복구 |

## 6. 주의사항

- CP Private IP 변경 시 Worker kubelet의 apiserver 주소 업데이트 필요
- etcd 스냅샷은 **동일 버전**(3.5.15)으로 복원
- S3 스냅샷 7일 후 자동 삭제 — 장기 보관 시 lifecycle 조정
