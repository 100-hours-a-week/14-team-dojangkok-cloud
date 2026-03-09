# ============================================================
# V3 K8S IaC — NAT Instance Variables
# ASG 래핑, dev: 1대 / prod: AZ별
# Branch: feat/v3-k8s-iac
# ============================================================

variable "project_name" {
  type = string
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t4g.nano"
}

variable "public_subnet_ids" {
  description = "NAT ASG 배치 가능한 public 서브넷 ID 목록 (multi-AZ)"
  type        = list(string)
}

variable "route_table_ids" {
  description = "NAT가 default route를 갱신할 private RT ID 목록"
  type        = list(string)
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
