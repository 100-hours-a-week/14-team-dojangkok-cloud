variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "region" {
  description = "GCP 리전"
  type        = string
  default     = "asia-northeast3"
}

variable "vpc_name" {
  description = "VPC 이름"
  type        = string
  default     = "dojangkok-ai-vpc"
}

variable "subnets" {
  description = "서브넷 맵 (key = 환경명)"
  type = map(object({
    name = string
    cidr = string
  }))
}

variable "router_name" {
  description = "Cloud Router 이름"
  type        = string
  default     = "dojangkok-ai-router"
}

variable "nat_name" {
  description = "Cloud NAT 이름"
  type        = string
  default     = "dojangkok-ai-nat"
}
