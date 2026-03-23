# 앱 배포 가이드

## 디렉토리 구조

```
k8s/apps/
├── base/              # 공통 매니페스트
│   ├── backend/       # Deployment, Service, ConfigMap, ExternalSecret, HPA
│   ├── frontend/
│   ├── ai-server/
│   ├── chatting-be/
│   ├── networking/    # Gateway, HTTPRoutes
│   └── security/      # NetworkPolicies, ServiceAccounts
└── overlays/
    ├── dev/           # 이미지 태그 + HPA 오버라이드
    └── prod/          # (준비 중)
```

## ArgoCD 자동 배포 흐름

```
코드 Push (서비스 레포)
  → GitHub Actions: 빌드 → ECR Push
  → cloud 레포: overlays/dev/kustomization.yaml 이미지 태그 업데이트
  → ArgoCD 감지 (3분 이내) → auto-sync → Rolling Update
```

ArgoCD 설정: `selfHeal: true`, `prune: true`
- Git 상태와 diff 발생 시 자동 복구
- Git에서 삭제된 리소스는 클러스터에서도 삭제

## Kustomize Overlay

### dev overlay (`k8s/apps/overlays/dev/kustomization.yaml`)

```yaml
images:
- name: 662505429975.dkr.ecr.../dev-dojangkok-be
  newTag: <git-sha>       # CI가 자동 업데이트

replicas:                  # HPA 미적용 서비스만
- name: frontend
  count: 1

patches:                   # HPA 오버라이드 등
- path: patches/backend-hpa.yaml
```

### 이미지 태그 수동 변경

```bash
# kustomization.yaml의 newTag 수정 후
git add -A && git commit -m "chore: update BE image tag" && git push
# → ArgoCD가 자동 반영
```

## 수동 배포 (긴급 시)

```bash
# CP에서 직접 적용
kubectl apply -k k8s/apps/overlays/dev

# 특정 앱만 재시작
kubectl -n dojangkok rollout restart deployment backend
```

## ArgoCD 대시보드 접속

SSM + socat 방식:
```bash
# 터미널 1: CP SSM 접속
aws ssm start-session --target i-0d768d11541b6ab6f --region ap-northeast-2

# CP에서 socat 실행
sudo socat TCP-LISTEN:30443,reuseaddr,fork TCP:localhost:30443

# 터미널 2: 로컬 포트포워딩
aws ssm start-session \
  --target i-0d768d11541b6ab6f \
  --region ap-northeast-2 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["30443"],"localPortNumber":["8443"]}'

# 브라우저: https://localhost:8443
# ID: admin
# PW:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```
