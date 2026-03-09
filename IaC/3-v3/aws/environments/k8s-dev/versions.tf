# ============================================================
# V3 K8S IaC — k8s-dev Provider & Backend
# 기존 V2 dev VPC(10.0.0.0/18)에 kubeadm K8S 클러스터 구성
# Branch: feat/v3-k8s-iac
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile
}
