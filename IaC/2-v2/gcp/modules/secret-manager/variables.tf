variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "secret_ids" {
  description = "생성할 시크릿 ID 목록"
  type        = set(string)
}

variable "secret_values" {
  description = "시크릿 초기값 맵 (key = secret_id, value = 초기값)"
  type        = map(string)
  sensitive   = true
}

variable "accessor_sa_email" {
  description = "시크릿 접근 권한을 부여할 Service Account 이메일"
  type        = string
}
