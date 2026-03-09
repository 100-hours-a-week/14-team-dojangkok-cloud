# ============================================================
# V3 K8S IaC — S3 Backend Config (k8s-dev)
# Branch: feat/v3-k8s-iac
# ============================================================

bucket       = "dojangkok-v3-tfstate"
key          = "k8s-dev/terraform.tfstate"
region       = "ap-northeast-2"
profile      = "tf"
encrypt      = true
use_lockfile = true
