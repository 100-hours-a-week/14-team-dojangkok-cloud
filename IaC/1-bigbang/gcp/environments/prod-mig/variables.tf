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

# --- AI Server ---
variable "ai_server_machine_type" {
  description = "AI Server 머신 타입"
  type        = string
  default     = "n2d-standard-2"
}

# --- AI Server 환경변수 ---
variable "vllm_api_key" {
  description = "vLLM API 키"
  type        = string
  sensitive   = true
}

variable "vllm_base_url" {
  description = "vLLM API Base URL (RunPod)"
  type        = string
  default     = "http://RUNPOD_IP:8001/v1"
}

variable "vllm_model" {
  description = "vLLM 모델명"
  type        = string
  default     = "LGAI-EXAONE/EXAONE-3.5-7.8B-Instruct"
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
  default     = "180"
}

# --- RabbitMQ ---
variable "rabbitmq_url" {
  description = "RabbitMQ 접속 URL (amqps://user:pass@host:port/)"
  type        = string
  sensitive   = true
}

variable "rabbitmq_enabled" {
  type    = string
  default = "true"
}

variable "rabbitmq_prefetch_count" {
  type    = string
  default = "3"
}

variable "rabbitmq_declare_passive" {
  type    = string
  default = "true"
}

# --- Docker Image ---
variable "ai_server_image" {
  description = "AI Server Docker 이미지 (크로스 프로젝트 GAR)"
  type        = string
  default     = "asia-northeast3-docker.pkg.dev/dojangkok-ai/dojangkok-ai/ai-server:latest"
}
