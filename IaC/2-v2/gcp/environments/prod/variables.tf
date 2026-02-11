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
  default     = "asia-northeast3-a"
}

variable "github_org" {
  description = "GitHub Organization 이름"
  type        = string
}

# --- AI Server (CPU) ---
variable "ai_server_machine_type" {
  description = "AI Server 머신 타입"
  type        = string
  default     = "n2d-standard-2"
}

variable "ai_server_boot_disk_image" {
  description = "AI Server 부팅 디스크 이미지 (Packer 빌드)"
  type        = string
  default     = "dojangkok-cpu-base"
}

# --- AI Server 환경변수 (docker-compose 전달) ---
variable "vllm_api_key" {
  description = "vLLM API 키"
  type        = string
  sensitive   = true
}

variable "vllm_model" {
  description = "vLLM 모델명"
  type        = string
  default     = "LGAI-EXAONE/EXAONE-3.5-2.4B-Instruct"
}

variable "vllm_lora_adapter_checklist" {
  description = "vLLM LoRA 어댑터 (체크리스트)"
  type        = string
  default     = "checklist"
}

variable "vllm_lora_adapter_easycontract" {
  description = "vLLM LoRA 어댑터 (쉬운계약서)"
  type        = string
  default     = "easycontract"
}

variable "backend_callback_base_url" {
  description = "백엔드 콜백 Base URL"
  type        = string
  default     = "https://dojangkok.cloud/api"
}

variable "backend_internal_token" {
  description = "백엔드 내부 통신 토큰"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ocr_api" {
  description = "Upstage OCR API 키"
  type        = string
  sensitive   = true
}

variable "http_timeout_sec" {
  description = "HTTP 타임아웃 (초)"
  type        = string
  default     = "30"
}

# --- ChromaDB (CPU) ---
variable "chromadb_machine_type" {
  description = "ChromaDB 머신 타입"
  type        = string
  default     = "e2-medium"
}

# --- vLLM (GPU) ---
variable "vllm_machine_type" {
  description = "vLLM 머신 타입"
  type        = string
  default     = "g2-standard-4"
}

variable "vllm_gpu_type" {
  description = "vLLM GPU 타입"
  type        = string
  default     = "nvidia-l4"
}

variable "vllm_boot_disk_image" {
  description = "vLLM 부팅 디스크 이미지 (GPU 드라이버 포함 필수)"
  type        = string
  default     = "ubuntu-os-accelerator-images/ubuntu-accelerator-2204-amd64-with-nvidia-580"
}

# --- Monitoring ---
variable "monitoring_source_ips" {
  description = "AWS Monitoring 소스 IP 목록"
  type        = list(string)
}
