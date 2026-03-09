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

# --- AI Server (CPU) ---
variable "ai_server_machine_type" {
  description = "AI Server 머신 타입"
  type        = string
  default     = "n2d-standard-2"
}

variable "ai_server_boot_disk_image" {
  description = "AI Server 부팅 디스크 이미지 (Packer 빌드, 크로스 프로젝트)"
  type        = string
}

variable "ai_server_image" {
  description = "AI Server Docker 이미지 (크로스 프로젝트 GAR)"
  type        = string
  default     = "asia-northeast3-docker.pkg.dev/dojangkok-ai/dojangkok-ai/ai-server:latest"
}

# --- AI Server 환경변수 ---
variable "vllm_api_key" {
  description = "vLLM API 키"
  type        = string
  sensitive   = true
}

variable "vllm_base_url" {
  description = "vLLM API Base URL (RunPod TCP Public IP)"
  type        = string
  default     = "http://RUNPOD_IP:PORT/v1"
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
variable "rabbitmq_enabled" {
  description = "RabbitMQ 활성화 여부"
  type        = string
  default     = "true"
}

variable "rabbitmq_prefetch_count" {
  description = "RabbitMQ prefetch count"
  type        = string
  default     = "3"
}

variable "rabbitmq_declare_passive" {
  description = "RabbitMQ exchange/queue passive 선언 여부"
  type        = string
  default     = "true"
}

variable "rabbitmq_url" {
  description = "RabbitMQ 접속 URL (amqps://user:pass@host:port/)"
  type        = string
  sensitive   = true
}

variable "rabbitmq_request_exchange_easy_contract" {
  description = "쉬운계약서 요청 exchange"
  type        = string
  default     = "fast.exchange"
}

variable "rabbitmq_request_queue_easy_contract" {
  description = "쉬운계약서 요청 queue"
  type        = string
  default     = "easy-contract.request"
}

variable "rabbitmq_request_routing_key_easy_contract" {
  description = "쉬운계약서 요청 routing key"
  type        = string
  default     = "easy-contract.request"
}

variable "rabbitmq_request_exchange_checklist" {
  description = "체크리스트 요청 exchange"
  type        = string
  default     = "fast.exchange"
}

variable "rabbitmq_request_queue_checklist" {
  description = "체크리스트 요청 queue"
  type        = string
  default     = "checklist.request"
}

variable "rabbitmq_request_routing_key_checklist" {
  description = "체크리스트 요청 routing key"
  type        = string
  default     = "checklist.request"
}

variable "rabbitmq_cancel_exchange_easy_contract" {
  description = "쉬운계약서 취소 exchange"
  type        = string
  default     = "fast.exchange"
}

variable "rabbitmq_cancel_queue_easy_contract" {
  description = "쉬운계약서 취소 queue"
  type        = string
  default     = "cancel.request"
}

variable "rabbitmq_cancel_routing_key_easy_contract" {
  description = "쉬운계약서 취소 routing key"
  type        = string
  default     = "cancel.request"
}

variable "rabbitmq_result_exchange" {
  description = "AI 결과 발행 exchange"
  type        = string
  default     = "fast.exchange"
}

variable "rabbitmq_result_queue" {
  description = "AI 결과 발행 queue"
  type        = string
  default     = "ai.response"
}

variable "rabbitmq_result_routing_key" {
  description = "AI 결과 발행 routing key"
  type        = string
  default     = "ai.response"
}

# --- Retry ---
variable "worker_retry_max_attempts" {
  description = "MQ 워커 재시도 최대 횟수"
  type        = string
  default     = "3"
}

variable "worker_retry_backoff_base_sec" {
  description = "MQ 워커 재시도 백오프 기본 초"
  type        = string
  default     = "0.5"
}

variable "external_retry_max_attempts" {
  description = "외부 API 호출 재시도 최대 횟수"
  type        = string
  default     = "3"
}

variable "external_retry_backoff_base_sec" {
  description = "외부 API 호출 재시도 백오프 기본 초"
  type        = string
  default     = "0.5"
}

# --- Easy Contract Cancel ---
variable "easy_contract_cancel_ttl_sec" {
  description = "쉬운계약서 취소 TTL (초)"
  type        = string
  default     = "3600"
}

variable "easy_contract_cancel_cleanup_interval_sec" {
  description = "쉬운계약서 취소 정리 주기 (초)"
  type        = string
  default     = "60"
}

# --- Monitoring ---
variable "monitoring_source_ips" {
  description = "AWS Monitoring 소스 IP 목록"
  type        = list(string)
}

variable "loki_url" {
  description = "Loki push API URL"
  type        = string
}

variable "tempo_endpoint" {
  description = "Tempo OTLP gRPC endpoint (host:port)"
  type        = string
}

variable "prometheus_url" {
  description = "Prometheus remote_write API URL"
  type        = string
}
