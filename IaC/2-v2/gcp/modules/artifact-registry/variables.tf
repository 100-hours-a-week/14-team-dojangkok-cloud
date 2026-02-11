variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "region" {
  description = "리전"
  type        = string
  default     = "asia-northeast3"
}

variable "repository_id" {
  description = "저장소 ID"
  type        = string
}

variable "description" {
  description = "저장소 설명"
  type        = string
  default     = "Docker container images"
}

variable "labels" {
  description = "리소스 라벨"
  type        = map(string)
  default     = {}
}
