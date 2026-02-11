variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "pool_id" {
  description = "Workload Identity Pool ID"
  type        = string
  default     = "github-pool"
}

variable "pool_display_name" {
  description = "Pool 표시 이름"
  type        = string
  default     = "GitHub Actions Pool"
}

variable "provider_id" {
  description = "Provider ID"
  type        = string
  default     = "github-provider"
}

variable "provider_display_name" {
  description = "Provider 표시 이름"
  type        = string
  default     = "GitHub OIDC Provider"
}

variable "attribute_condition" {
  description = "OIDC 토큰 attribute 조건"
  type        = string
}

variable "service_account_id" {
  description = "바인딩할 Service Account ID (full path)"
  type        = string
}

variable "principal_set_filter" {
  description = "Principal Set 필터"
  type        = string
}
