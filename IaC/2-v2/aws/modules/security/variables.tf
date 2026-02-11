variable "project_name" {
  description = "리소스 이름에 사용할 프로젝트 접두사"
  type        = string
}

variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "security_groups" {
  description = "보안 그룹 맵 (name => config)"
  type = map(object({
    description = string
    ingress_rules = list(object({
      from_port       = number
      to_port         = number
      protocol        = string
      cidr_blocks     = optional(list(string))
      security_groups = optional(list(string))
      description     = optional(string)
    }))
  }))
}

variable "enable_s3_endpoint" {
  description = "S3 VPC Endpoint 생성 여부"
  type        = bool
  default     = true
}

variable "route_table_ids" {
  description = "S3 VPC Endpoint에 연결할 라우트 테이블 ID 목록"
  type        = list(string)
  default     = []
}
