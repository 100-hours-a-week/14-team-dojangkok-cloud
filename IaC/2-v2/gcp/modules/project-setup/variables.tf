variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "enabled_apis" {
  description = "활성화할 GCP API 목록"
  type        = list(string)
  default = [
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iap.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "artifactregistry.googleapis.com",
  ]
}
