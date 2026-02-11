variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "firewall_name" {
  description = "방화벽 규칙 이름"
  type        = string
}

variable "network" {
  description = "VPC 네트워크 self_link 또는 이름"
  type        = string
}

variable "description" {
  description = "방화벽 규칙 설명"
  type        = string
  default     = ""
}

variable "allow_rules" {
  description = "허용할 프로토콜 및 포트 목록"
  type = list(object({
    protocol = string
    ports    = list(string)
  }))
}

variable "source_ranges" {
  description = "소스 IP 범위 (필수 — 0.0.0.0/0 금지)"
  type        = list(string)
}

variable "target_tags" {
  description = "대상 네트워크 태그"
  type        = list(string)
  default     = []
}

variable "priority" {
  description = "방화벽 규칙 우선순위"
  type        = number
  default     = 1000
}

variable "direction" {
  description = "트래픽 방향"
  type        = string
  default     = "INGRESS"
}
