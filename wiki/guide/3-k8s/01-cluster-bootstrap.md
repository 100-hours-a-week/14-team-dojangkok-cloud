# 클러스터 구축 가이드

## 사전 준비

### 필수 도구 (로컬)

```bash
terraform -version       # 1.14+
ansible --version        # 2.15+
aws --version            # + SSM 플러그인
pip install boto3 botocore
```

### AWS 사전 설정

- `~/.aws/credentials`에 `tf` 프로필
- V2 VPC(10.0.0.0/18) 존재
- ACM 인증서 (ALB용 SSL)
- AWS Secrets Manager에 시크릿:
  - `dojangkok/dev/backend`
  - `dojangkok/dev/ai-server`
  - `dojangkok/dev/chatting-be`

---

## Step 1: Terraform — 인프라 프로비저닝

```bash
cd IaC/3-v3/aws/environments/k8s-dev

terraform plan
terraform apply
```

**생성 리소스:**
- K8S 서브넷 3개 (10.0.48-50/24)
- Security Group 2개 (CP, Worker)
- EC2: CP 1 + Worker 3
- NAT Instance (ASG)
- ALB + Target Group (NodePort 30080)
- IAM Role + Instance Profile

**확인:**
```bash
terraform output
# → CP IP, Worker IPs, ALB DNS
```

> GitHub Actions로도 실행 가능: [GitHub Actions 가이드](03-github-actions.md#terraform)

---

## Step 2: Ansible — K8S 부트스트랩

```bash
cd IaC/3-v3/ansible

# 인벤토리 확인 (EC2 태그 기반 동적)
ansible-inventory -i inventory/aws_ec2.yaml --graph

# 전체 실행
ansible-playbook -i inventory/aws_ec2.yaml playbooks/site.yml \
  -e ansible_aws_ssm_profile=tf \
  -e cluster_name=dojangkok-v3
```

**실행 순서 (site.yml):**

| Phase | 대상 | Role | 소요시간 |
|-------|------|------|---------|
| 1 | 전체 노드 | common, containerd, kubeadm-prereqs, ecr-credential | ~5분 |
| 2 | CP | kubeadm-init | ~3분 |
| 3 | Worker | kubeadm-join | ~2분 |
| 4 | CP | calico, coredns, ebs-csi, gateway-fabric, external-secrets, argocd, etcd-backup | ~10분 |

**총 ~20분**

> GitHub Actions로도 실행 가능: [GitHub Actions 가이드](03-github-actions.md#ansible)
> Ansible 불안하면 수동 세팅: [워커노드 충원 가이드](02-worker-node-setup.md)

---

## Step 3: 클러스터 확인

```bash
# CP에 SSM 접속
aws ssm start-session --target <cp-instance-id> --region ap-northeast-2

kubectl get nodes
# cp-2a         Ready    control-plane
# worker-2a     Ready    worker
# worker-2b     Ready    worker
# worker-2c     Ready    worker

kubectl get pods -A
# calico-system, kube-system, argocd, nginx-gateway 등
```

이후 앱 배포는 ArgoCD가 자동 처리 → [앱 배포 가이드](04-app-deployment.md)
