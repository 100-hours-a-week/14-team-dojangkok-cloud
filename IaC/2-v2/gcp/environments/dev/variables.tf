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

variable "vllm_model_revision" {
  description = "vLLM 모델 리비전 (Transformers v5 호환 회피용)"
  type        = string
  default     = "e949c91dec92095908d34e6b560af77dd0c993f8"
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

# --- RabbitMQ ---
variable "rabbitmq_url" {
  description = "RabbitMQ 접속 URL (amqps://user:pass@host:port/)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "rabbitmq_request_exchange_easy_contract" {
  description = "쉬운계약서 요청 exchange"
  type        = string
  default     = "dev.easy.req.ex"
}

variable "rabbitmq_request_queue_easy_contract" {
  description = "쉬운계약서 요청 queue"
  type        = string
  default     = "dev.easy.req.q"
}

variable "rabbitmq_request_routing_key_easy_contract" {
  description = "쉬운계약서 요청 routing key"
  type        = string
  default     = "easy.create"
}

variable "rabbitmq_request_exchange_checklist" {
  description = "체크리스트 요청 exchange"
  type        = string
  default     = "dev.chk.req.ex"
}

variable "rabbitmq_request_queue_checklist" {
  description = "체크리스트 요청 queue"
  type        = string
  default     = "dev.chk.req.q"
}

variable "rabbitmq_request_routing_key_checklist" {
  description = "체크리스트 요청 routing key"
  type        = string
  default     = "checklist.create"
}

variable "rabbitmq_cancel_exchange_easy_contract" {
  description = "쉬운계약서 취소 exchange"
  type        = string
  default     = "dev.easy.cancel.ex"
}

variable "rabbitmq_cancel_queue_easy_contract" {
  description = "쉬운계약서 취소 queue"
  type        = string
  default     = "dev.easy.cancel.q"
}

variable "rabbitmq_cancel_routing_key_easy_contract" {
  description = "쉬운계약서 취소 routing key"
  type        = string
  default     = "easy.cancel"
}

variable "rabbitmq_result_exchange" {
  description = "AI 결과 발행 exchange"
  type        = string
  default     = "dev.result.ex"
}

variable "rabbitmq_result_queue" {
  description = "AI 결과 발행 queue"
  type        = string
  default     = "dev.result.q"
}

variable "rabbitmq_result_routing_key" {
  description = "AI 결과 발행 routing key"
  type        = string
  default     = "ai.result"
}

# --- Monitoring ---
variable "monitoring_source_ips" {
  description = "AWS Monitoring 소스 IP 목록"
  type        = list(string)
}

variable "loki_url" {
  description = "Loki push API URL"
  type        = string
  default     = ""
}

variable "tempo_endpoint" {
  description = "Tempo OTLP gRPC endpoint (host:port)"
  type        = string
  default     = ""
}
