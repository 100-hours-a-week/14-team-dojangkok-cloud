# Workload Identity Module Variables

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
  description = "Workload Identity Pool 표시 이름"
  type        = string
  default     = "GitHub Actions Pool"
}

variable "provider_id" {
  description = "Workload Identity Provider ID"
  type        = string
  default     = "github-provider"
}

variable "provider_display_name" {
  description = "Workload Identity Provider 표시 이름"
  type        = string
  default     = "GitHub OIDC Provider"
}

variable "attribute_condition" {
  description = "OIDC 토큰 attribute 조건 (GitHub org/repo 제한)"
  type        = string
  # 예: "assertion.repository_owner == 'kakaotech-bootcamp-team14'"
}

variable "service_account_id" {
  description = "바인딩할 Service Account ID (full path)"
  type        = string
  # 예: "projects/PROJECT_ID/serviceAccounts/SA_EMAIL"
}

variable "principal_set_filter" {
  description = "Principal Set 필터 (attribute.repository 또는 repository_owner)"
  type        = string
  # 예: "attribute.repository_owner/kakaotech-bootcamp-team14"
  # 또는: "attribute.repository/kakaotech-bootcamp-team14/repo-name"
}
