variable "project_id" {
  type        = string
  description = "GCP 프로젝트 ID"
}

variable "region" {
  type    = string
  default = "asia-northeast3"
}

variable "zone" {
  type    = string
  default = "asia-northeast3-a"
}
