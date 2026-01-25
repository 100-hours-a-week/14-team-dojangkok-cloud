# Production Environment Variables

variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "region" {
  description = "GCP 리전"
  type        = string
  default     = "asia-northeast3"
}

variable "zone" {
  description = "GCP 존"
  type        = string
  default     = "asia-northeast3-b"
}

# GitHub 설정
variable "github_org" {
  description = "GitHub Organization 이름"
  type        = string
}

# AI Server 설정
variable "ai_server_machine_type" {
  description = "AI 서버 머신 타입 (GPU 연결 가능한 타입)"
  type        = string
  default     = "n1-standard-4"
}

variable "gpu_type" {
  description = "GPU 타입"
  type        = string
  default     = "nvidia-tesla-t4"
}

variable "gpu_count" {
  description = "GPU 개수"
  type        = number
  default     = 1
}

variable "boot_disk_size_gb" {
  description = "부팅 디스크 크기 (GB)"
  type        = number
  default     = 200
}
