# ============================================================
# V3 K8S IaC — k8s-dev Variables
# 기존 V2 dev VPC(10.0.0.0/18)에 kubeadm K8S 클러스터 구성
# Branch: feat/v3-k8s-iac
# ============================================================

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "project_name" {
  description = "리소스 네이밍 접두사"
  type        = string
  default     = "k8s-dev"
}

variable "cluster_name" {
  description = "K8S 클러스터 이름 (태그 + Ansible 필터)"
  type        = string
  default     = "dojangkok-v3"
}

# --- 기존 VPC ---

variable "vpc_id" {
  description = "기존 V2 dev VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "기존 V2 dev VPC CIDR"
  type        = string
  default     = "10.0.0.0/18"
}

# --- K8S Nodes ---

variable "workers_per_az" {
  description = "AZ당 워커 노드 수 (초기 1, 스케일업 시 2)"
  type        = number
  default     = 1

  validation {
    condition     = var.workers_per_az >= 1 && var.workers_per_az <= 3
    error_message = "workers_per_az must be between 1 and 3."
  }
}

variable "cp_instance_type" {
  type    = string
  default = "t4g.medium"
}

variable "worker_instance_type" {
  type    = string
  default = "t4g.large"
}

# --- ALB ---

variable "gateway_nodeport" {
  description = "NGINX Gateway Fabric 고정 NodePort"
  type        = number
  default     = 30080
}

variable "ssl_certificate_arn" {
  description = "ACM 인증서 ARN (null이면 HTTP only)"
  type        = string
  default     = null
}

variable "aws_profile" {
  description = "AWS CLI profile (null = 환경변수 사용, CI/OIDC용)"
  type        = string
  default     = null
}
