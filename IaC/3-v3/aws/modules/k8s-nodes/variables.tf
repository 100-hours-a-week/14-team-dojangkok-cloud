# ============================================================
# V3 K8S IaC — K8S Nodes Variables
# ============================================================

variable "project_name" {
  type = string
}

variable "cluster_name" {
  description = "K8S 클러스터 이름 (태그 + Ansible 필터용)"
  type        = string
  default     = "dojangkok-v3"
}

# --- Control Plane ---

variable "cp_instance_type" {
  type    = string
  default = "t4g.medium"
}

variable "cp_subnet_id" {
  description = "CP가 배치될 서브넷 ID (AZ-a)"
  type        = string
}

variable "cp_security_group_ids" {
  type = list(string)
}

variable "cp_volume_size" {
  type    = number
  default = 30
}

# --- Workers ---

variable "worker_instance_type" {
  type    = string
  default = "t4g.large"
}

variable "workers_per_az" {
  description = "AZ당 워커 노드 수 (초기 1, prod 목표 2)"
  type        = number
  default     = 1
}

variable "worker_az_subnets" {
  description = "AZ suffix → subnet ID 맵 (e.g. {a = 'subnet-xxx', b = '...', c = '...'})"
  type        = map(string)
}

variable "worker_security_group_ids" {
  type = list(string)
}

variable "worker_volume_size" {
  type    = number
  default = 30
}

# --- Shared ---

variable "iam_instance_profile" {
  description = "K8S 노드용 IAM instance profile 이름"
  type        = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
