# GitHub Actions Service Account Module Variables

variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "account_id" {
  description = "Service Account ID (email prefix)"
  type        = string
  default     = "github-actions-sa"
}

variable "display_name" {
  description = "Service Account 표시 이름"
  type        = string
  default     = "GitHub Actions Service Account"
}

variable "enable_compute_admin" {
  description = "Compute Instance Admin 권한 활성화"
  type        = bool
  default     = true
}

variable "enable_iap_tunnel" {
  description = "IAP Tunnel User 권한 활성화"
  type        = bool
  default     = true
}

variable "enable_sa_user" {
  description = "Service Account User 권한 활성화"
  type        = bool
  default     = true
}

variable "enable_security_admin" {
  description = "Compute Security Admin 권한 활성화 (방화벽 관리)"
  type        = bool
  default     = false
}
