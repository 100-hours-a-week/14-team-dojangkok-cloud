variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "instance_name" {
  description = "VM 인스턴스 이름"
  type        = string
}

variable "machine_type" {
  description = "머신 타입 (GPU 호환)"
  type        = string
  default     = "g2-standard-4"
}

variable "zone" {
  description = "배포 존"
  type        = string
  default     = "asia-northeast3-a"
}

variable "gpu_type" {
  description = "GPU 타입"
  type        = string
  default     = "nvidia-l4"
}

variable "gpu_count" {
  description = "GPU 개수"
  type        = number
  default     = 1
}

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
  description = "부팅 디스크 타입"
  type        = string
  default     = "pd-ssd"
}

variable "boot_disk_auto_delete" {
  description = "VM 삭제 시 디스크 자동 삭제"
  type        = bool
  default     = true
}

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

variable "static_external_ip" {
  description = "고정 외부 IP"
  type        = string
  default     = null
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

variable "labels" {
  description = "VM 라벨"
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "삭제 보호"
  type        = bool
  default     = false
}

variable "is_spot_instance" {
  description = "Spot VM 사용 여부"
  type        = bool
  default     = false
}

# 컨테이너 (Docker 모드 — COS는 GPU 미지원)
variable "container_image" {
  description = "컨테이너 이미지 URI (설정 시 Docker + nvidia-toolkit 자동 설치, null이면 기존 동작 유지)"
  type        = string
  default     = null
}

variable "container_env" {
  description = "컨테이너 환경변수 (container_image 설정 시 사용)"
  type        = map(string)
  default     = {}
}

variable "container_ports" {
  description = "컨테이너 포트 매핑 (host:container)"
  type        = list(string)
  default     = []
}

variable "container_args" {
  description = "컨테이너 추가 docker run 인자"
  type        = string
  default     = ""
}
