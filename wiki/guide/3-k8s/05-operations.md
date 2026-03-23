# 운영 가이드

## 스케일링

### Pod (HPA)

backend, ai-server는 HPA가 관리 (base: `hpa.yaml`).
Deployment에 `spec.replicas`를 넣지 않는다 — ArgoCD selfHeal 충돌 방지.

```bash
# HPA 상태 확인
kubectl -n dojangkok get hpa

# HPA 오버라이드는 overlay patch로:
# k8s/apps/overlays/dev/patches/backend-hpa.yaml
```

frontend, chatting-be는 kustomization.yaml의 `replicas:`로 관리.

### 워커노드 추가

Terraform `workers_per_az` 변경 → apply → Ansible 또는 [수동 세팅](02-worker-node-setup.md)

## 이미지 업데이트

CI가 자동 처리. 수동 시:
```bash
# overlays/dev/kustomization.yaml 수정
images:
- name: .../dev-dojangkok-be
  newTag: <새 커밋 해시>

# push → ArgoCD 자동 반영
```

## 로그 확인

```bash
# 실시간 로그
kubectl -n dojangkok logs -f deployment/backend

# 이전 컨테이너 (크래시 시)
kubectl -n dojangkok logs <pod-name> --previous

# 전체 이벤트
kubectl -n dojangkok get events --sort-by='.lastTimestamp'
```

## 리소스 현황

```bash
kubectl top nodes
kubectl top pods -n dojangkok
kubectl describe node <worker> | grep -A 10 "Allocated"
```

## 시크릿 갱신

AWS Secrets Manager에서 값 변경 → ESO가 자동 동기화 (기본 1시간).

즉시 동기화:
```bash
kubectl -n dojangkok annotate externalsecret backend-secret \
  force-sync=$(date +%s) --overwrite
```

## SSM으로 CP 접속

```bash
aws ssm start-session --target i-0d768d11541b6ab6f --region ap-northeast-2
```
