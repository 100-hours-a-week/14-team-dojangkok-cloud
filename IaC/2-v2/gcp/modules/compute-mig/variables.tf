variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "instance_name" {
  description = "인스턴스 베이스 이름"
  type        = string
}

variable "machine_type" {
  description = "머신 타입"
  type        = string
  default     = "n2d-standard-2"
}

variable "region" {
  description = "리전 (Instance Template용)"
  type        = string
  default     = "asia-northeast3"
}

variable "zone" {
  description = "MIG 배포 존"
  type        = string
  default     = "asia-northeast3-a"
}

# MIG 설정
variable "target_size" {
  description = "MIG 인스턴스 수"
  type        = number
  default     = 1
}

variable "max_surge" {
  description = "롤링 업데이트 시 추가 인스턴스 수"
  type        = number
  default     = 1
}

variable "max_unavailable" {
  description = "롤링 업데이트 시 허용 불가용 인스턴스 수"
  type        = number
  default     = 0
}

variable "named_ports" {
  description = "Named ports (로드밸런서 연동용)"
  type = list(object({
    name = string
    port = number
  }))
  default = []
}

variable "health_check_id" {
  description = "Auto Healing용 Health Check ID (null이면 미사용)"
  type        = string
  default     = null
}

variable "health_check_initial_delay" {
  description = "Health Check 초기 대기 시간 (초)"
  type        = number
  default     = 300
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
  description = "부팅 디스크 타입"
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
  description = "VPC 네트워크 self_link 또는 이름"
  type        = string
}

variable "subnetwork" {
  description = "서브네트워크 self_link 또는 이름"
  type        = string
}

variable "enable_external_ip" {
  description = "외부 IP 할당 여부"
  type        = bool
  default     = false
}

variable "network_tier" {
  description = "네트워크 티어"
  type        = string
  default     = "PREMIUM"
}

variable "network_tags" {
  description = "네트워크 태그"
  type        = list(string)
  default     = []
}

# 서비스 계정
variable "service_account_email" {
  description = "서비스 계정 이메일"
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
  description = "Startup script"
  type        = string
  default     = null
}

# 라벨
variable "labels" {
  description = "VM 라벨"
  type        = map(string)
  default     = {}
}

# 스케줄링
variable "is_spot_instance" {
  description = "Spot VM 사용 여부"
  type        = bool
  default     = false
}

# 컨테이너 (COS 모드)
variable "container_image" {
  description = "컨테이너 이미지 URI (설정 시 COS 모드로 전환, null이면 기존 동작 유지)"
  type        = string
  default     = null
}

variable "container_env" {
  description = "컨테이너 환경변수 (container_image 설정 시 사용)"
  type        = map(string)
  default     = {}
}
