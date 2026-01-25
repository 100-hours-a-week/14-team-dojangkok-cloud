# Firewall Module Variables

variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "firewall_name" {
  description = "방화벽 규칙 이름"
  type        = string
}

variable "network" {
  description = "적용할 VPC 네트워크 이름"
  type        = string
  default     = "default"
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
  # 예: [{ protocol = "tcp", ports = ["8000", "8001"] }]
}

variable "source_ranges" {
  description = "소스 IP 범위"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "target_tags" {
  description = "대상 네트워크 태그 (특정 VM에만 적용)"
  type        = list(string)
  default     = []
}

variable "priority" {
  description = "방화벽 규칙 우선순위 (낮을수록 높은 우선순위)"
  type        = number
  default     = 1000
}

variable "direction" {
  description = "트래픽 방향 (INGRESS 또는 EGRESS)"
  type        = string
  default     = "INGRESS"
}
