variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "aws_profile" {
  type    = string
  default = ""
}

variable "project_name" {
  type    = string
  default = "fis-exp"
}

variable "cluster_name" {
  type    = string
  default = "fis-exp"
}

# --- 기존 V4 VPC ---

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  description = "기존 VPC CIDR (SG 규칙용)"
  type        = string
  default     = "10.0.0.0/24"
}

variable "igw_id" {
  description = "기존 Internet Gateway ID"
  type        = string
}

variable "secondary_cidr" {
  description = "K8S용 Secondary CIDR"
  type        = string
  default     = "10.1.0.0/16"
}

# --- data 인스턴스 SG ---

variable "data_security_group_id" {
  description = "기존 data 인스턴스의 SG ID (인바운드 룰 추가용)"
  type        = string
}

# --- EC2 ---

variable "key_pair_name" {
  type    = string
  default = "dojangkok-key"
}

variable "instance_type" {
  description = "모든 노드 공통 인스턴스 타입"
  type        = string
  default     = "t4g.medium"
}

variable "ssh_allowed_cidr" {
  description = "SSH 접속 허용 CIDR (본인 IP)"
  type        = string
  default     = "0.0.0.0/0"
}

# --- Gateway ---

variable "gateway_nodeport" {
  type    = number
  default = 30080
}

locals {
  common_tags = {
    Project     = "dojangkok"
    Environment = "fis-experiment"
    ManagedBy   = "terraform"
  }

  # SG 규칙에 사용할 VPC 내부 CIDR 목록
  vpc_internal_cidrs = [var.vpc_cidr, var.secondary_cidr]
}
