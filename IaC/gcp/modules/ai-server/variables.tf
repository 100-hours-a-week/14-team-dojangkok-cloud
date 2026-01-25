# AI Server Module Variables

variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "instance_name" {
  description = "VM 인스턴스 이름"
  type        = string
  default     = "ai-server"
}

variable "machine_type" {
  description = "머신 타입 (예: e2-medium, n1-standard-4)"
  type        = string
  default     = "e2-medium"
}

variable "zone" {
  description = "배포 존"
  type        = string
  default     = "asia-northeast3-a"
}

# GPU 설정
variable "gpu_type" {
  description = "GPU 타입 (예: nvidia-tesla-t4, nvidia-tesla-v100)"
  type        = string
  default     = ""
}

variable "gpu_count" {
  description = "GPU 개수 (0이면 GPU 미사용)"
  type        = number
  default     = 0
}

# 부팅 디스크
variable "boot_disk_image" {
  description = "부팅 디스크 이미지"
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2204-lts"
}

variable "boot_disk_size_gb" {
  description = "부팅 디스크 크기 (GB)"
  type        = number
  default     = 30
}

variable "boot_disk_type" {
  description = "부팅 디스크 타입 (pd-standard, pd-balanced, pd-ssd)"
  type        = string
  default     = "pd-balanced"
}

variable "boot_disk_auto_delete" {
  description = "VM 삭제 시 디스크 자동 삭제"
  type        = bool
  default     = true
}

# 네트워크
variable "network" {
  description = "VPC 네트워크 이름"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "서브네트워크 이름 (옵션)"
  type        = string
  default     = null
}

variable "enable_external_ip" {
  description = "외부 IP 할당 여부"
  type        = bool
  default     = true
}

variable "static_external_ip" {
  description = "고정 외부 IP (null이면 ephemeral)"
  type        = string
  default     = null
}

variable "network_tier" {
  description = "네트워크 티어 (PREMIUM 또는 STANDARD)"
  type        = string
  default     = "PREMIUM"
}

variable "network_tags" {
  description = "네트워크 태그 (방화벽 규칙 적용용)"
  type        = list(string)
  default     = []
}

# 서비스 계정
variable "service_account_email" {
  description = "VM에 연결할 서비스 계정 이메일"
  type        = string
  default     = null
}

variable "service_account_scopes" {
  description = "서비스 계정 스코프"
  type        = list(string)
  default     = ["cloud-platform"]
}

# 메타데이터
variable "metadata" {
  description = "VM 메타데이터"
  type        = map(string)
  default     = {}
}

variable "enable_oslogin" {
  description = "OS Login 활성화"
  type        = bool
  default     = true
}

variable "startup_script" {
  description = "Startup script 내용"
  type        = string
  default     = null
}

# 라벨
variable "labels" {
  description = "VM 라벨"
  type        = map(string)
  default     = {}
}

# 보호 및 스케줄링
variable "deletion_protection" {
  description = "삭제 보호 활성화"
  type        = bool
  default     = false
}

variable "is_spot_instance" {
  description = "Spot(Preemptible) VM 사용 여부"
  type        = bool
  default     = false
}
