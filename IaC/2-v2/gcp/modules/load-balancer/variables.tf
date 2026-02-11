variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

# 고정 IP
variable "static_ip_name" {
  description = "글로벌 외부 고정 IP 이름"
  type        = string
  default     = "dojangkok-ai-lb-ip"
}

# Health Check
variable "health_check_name" {
  description = "Health Check 이름"
  type        = string
  default     = "dojangkok-ai-health-check"
}

variable "health_check_port" {
  description = "Health Check 포트"
  type        = number
  default     = 8000
}

variable "health_check_path" {
  description = "Health Check 경로"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Health Check 주기 (초)"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Health Check 타임아웃 (초)"
  type        = number
  default     = 10
}

variable "healthy_threshold" {
  description = "정상 판정 임계값"
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "비정상 판정 임계값"
  type        = number
  default     = 3
}

# Backend Service
variable "backend_service_name" {
  description = "Backend Service 이름"
  type        = string
  default     = "dojangkok-ai-backend"
}

variable "backend_port_name" {
  description = "Backend 포트 이름 (MIG named port)"
  type        = string
  default     = "fastapi"
}

variable "backend_timeout" {
  description = "Backend 타임아웃 (초)"
  type        = number
  default     = 30
}

variable "instance_group" {
  description = "Backend에 연결할 MIG instance_group URL"
  type        = string
}

# URL Map
variable "url_map_name" {
  description = "URL Map 이름"
  type        = string
  default     = "dojangkok-ai-url-map"
}

# SSL (선택)
variable "ssl_certificate_domains" {
  description = "관리형 SSL 인증서용 도메인 목록 (null이면 HTTP LB)"
  type        = list(string)
  default     = null
}
