variable "project_name" {
  description = "리소스 이름에 사용할 프로젝트 접두사"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "ALB를 배치할 서브넷 ID 목록"
  type        = list(string)
}

variable "security_group_ids" {
  description = "ALB에 연결할 보안 그룹 ID 목록"
  type        = list(string)
}

variable "target_groups" {
  description = "Target Group 맵 (name => config)"
  type = map(object({
    port                  = number
    health_check_path     = optional(string, "/")
    health_check_matcher  = optional(string, "200")
    health_check_interval = optional(number, 30)
    health_check_timeout  = optional(number, 5)
    healthy_threshold     = optional(number, 3)
    unhealthy_threshold   = optional(number, 3)
    path_pattern          = optional(string)
    priority              = optional(number, 100)
  }))
}

variable "ssl_certificate_arn" {
  description = "ACM 인증서 ARN (HTTPS 활성화 시)"
  type        = string
  default     = null
}
