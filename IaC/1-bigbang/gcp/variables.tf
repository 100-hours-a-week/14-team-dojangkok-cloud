# GCP Infrastructure Variables
# 모든 변수를 한 곳에서 관리

# ============================================
# 기본 설정
# ============================================
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

# ============================================
# GitHub 설정
# ============================================
variable "github_org" {
  description = "GitHub Organization 이름"
  type        = string
}

# ============================================
# Service Account 설정
# ============================================
variable "sa_account_id" {
  description = "Service Account ID (email prefix)"
  type        = string
  default     = "github-actions-sa"
}

variable "sa_display_name" {
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

# ============================================
# Workload Identity 설정
# ============================================
variable "wi_pool_id" {
  description = "Workload Identity Pool ID"
  type        = string
  default     = "github-pool"
}

variable "wi_pool_display_name" {
  description = "Workload Identity Pool 표시 이름"
  type        = string
  default     = "GitHub Actions Pool"
}

variable "wi_provider_id" {
  description = "Workload Identity Provider ID"
  type        = string
  default     = "github-provider"
}

variable "wi_provider_display_name" {
  description = "Workload Identity Provider 표시 이름"
  type        = string
  default     = "GitHub OIDC Provider"
}

# ============================================
# Firewall 설정
# ============================================
variable "firewall_name" {
  description = "방화벽 규칙 이름"
  type        = string
  default     = "dojangkok-ai-server-fw"
}

variable "firewall_network" {
  description = "적용할 VPC 네트워크 이름"
  type        = string
  default     = "default"
}

variable "firewall_ports" {
  description = "허용할 포트 목록"
  type        = list(string)
  default     = ["8000", "8001", "8100"]
}

variable "firewall_source_ranges" {
  description = "소스 IP 범위"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "firewall_target_tags" {
  description = "대상 네트워크 태그"
  type        = list(string)
  default     = ["ai-server"]
}

# ============================================
# AI Server 설정
# ============================================
variable "ai_server_name" {
  description = "VM 인스턴스 이름"
  type        = string
  default     = "ai-server"
}

variable "ai_server_machine_type" {
  description = "머신 타입 (GPU 연결 가능한 타입)"
  type        = string
  default     = "n1-standard-2"
}

# GPU 설정
variable "gpu_type" {
  description = "GPU 타입 (예: nvidia-tesla-t4, nvidia-tesla-v100)"
  type        = string
  default     = "nvidia-tesla-t4"
}

variable "gpu_count" {
  description = "GPU 개수 (0이면 GPU 미사용)"
  type        = number
  default     = 1
}

# 디스크 설정
variable "boot_disk_image" {
  description = "부팅 디스크 이미지"
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2204-lts"
}

variable "boot_disk_size_gb" {
  description = "부팅 디스크 크기 (GB)"
  type        = number
  default     = 200
}

variable "boot_disk_type" {
  description = "부팅 디스크 타입 (pd-standard, pd-balanced, pd-ssd)"
  type        = string
  default     = "pd-ssd"
}

variable "boot_disk_auto_delete" {
  description = "VM 삭제 시 디스크 자동 삭제"
  type        = bool
  default     = true
}

# 네트워크 설정
variable "ai_server_network" {
  description = "VPC 네트워크 이름"
  type        = string
  default     = "default"
}

variable "ai_server_subnetwork" {
  description = "서브네트워크 이름 (옵션)"
  type        = string
  default     = null
}

variable "ai_server_enable_external_ip" {
  description = "외부 IP 할당 여부"
  type        = bool
  default     = true
}

variable "ai_server_static_external_ip" {
  description = "고정 외부 IP (null이면 ephemeral)"
  type        = string
  default     = null
}

variable "ai_server_network_tier" {
  description = "네트워크 티어 (PREMIUM 또는 STANDARD)"
  type        = string
  default     = "PREMIUM"
}

variable "ai_server_network_tags" {
  description = "네트워크 태그 (방화벽 규칙 적용용)"
  type        = list(string)
  default     = ["ai-server", "dojangkok-monitoring"]
}

# 메타데이터 설정
variable "ai_server_metadata" {
  description = "VM 메타데이터"
  type        = map(string)
  default     = {}
}

variable "ai_server_enable_oslogin" {
  description = "OS Login 활성화"
  type        = bool
  default     = true
}

variable "ai_server_startup_script" {
  description = "Startup script 내용"
  type        = string
  default     = null
}

# 라벨
variable "ai_server_labels" {
  description = "VM 라벨"
  type        = map(string)
  default = {
    environment = "prod"
    service     = "ai-server"
    managed_by  = "terraform"
  }
}

# 보호 및 스케줄링
variable "ai_server_deletion_protection" {
  description = "삭제 보호 활성화"
  type        = bool
  default     = false
}

variable "ai_server_is_spot" {
  description = "Spot(Preemptible) VM 사용 여부"
  type        = bool
  default     = false
}
