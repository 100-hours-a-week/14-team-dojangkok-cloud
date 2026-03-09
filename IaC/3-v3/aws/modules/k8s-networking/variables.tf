# ============================================================
# V3 K8S IaC — Networking Variables
# ============================================================

variable "project_name" {
  type = string
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "vpc_id" {
  description = "기존 VPC ID (data source로 전달)"
  type        = string
}

variable "igw_id" {
  description = "기존 Internet Gateway ID"
  type        = string
}

variable "subnets" {
  description = "생성할 서브넷 맵 (public + private)"
  type = map(object({
    cidr = string
    az   = string
    tier = string # "public" or "private"
  }))
}

variable "availability_zones" {
  description = "사용할 AZ suffix 목록"
  type        = list(string)
  default     = ["a", "b", "c"]
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
