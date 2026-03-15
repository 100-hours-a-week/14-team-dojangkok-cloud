variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "project_name" {
  type    = string
  default = "tf-test-dojangkok-dev"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.1.0.0/18"
}

variable "availability_zones" {
  type    = list(string)
  default = ["a", "c"]
}

# Instance types
variable "mysql_instance_type" {
  type    = string
  default = "t4g.medium"
}

variable "redis_instance_type" {
  type    = string
  default = "t4g.small"
}

variable "mq_instance_type" {
  type    = string
  default = "t4g.small"
}

variable "nat_instance_type" {
  type    = string
  default = "t4g.nano"
}

# Volume sizes
variable "mysql_volume_size" {
  type    = number
  default = 100
}

variable "redis_volume_size" {
  type    = number
  default = 30
}

variable "mq_volume_size" {
  type    = number
  default = 30
}

# IAM instance profiles (from shared state)
variable "iam_instance_profile_names" {
  type        = map(string)
  description = "Instance profile names from shared IAM (keys: be, fe, mq, mysql, nat-instance, redis)"
  default = {
    be           = "dojangkok-v2-be-role"
    fe           = "dojangkok-v2-fe-role"
    mq           = "dojangkok-v2-mq-role"
    mysql        = "dojangkok-v2-mysql-role"
    nat-instance = "dojangkok-v2-nat-instance-role"
    redis        = "dojangkok-v2-redis-role"
    ai           = "dojangkok-v2-ai-role"
  }
}

# GCP NAT IP (for NLB SG)
variable "gcp_nat_ip" {
  type        = string
  description = "GCP Cloud NAT IP for NLB security group"
  default     = ""
}

# ACM certificate ARN (from shared state)
variable "ssl_certificate_arn" {
  type        = string
  description = "ACM certificate ARN for ALB/NLB"
  default     = ""
}

# CloudFront
variable "cloudfront_acm_arn" {
  type        = string
  description = "ACM certificate ARN in us-east-1 for CloudFront"
  default     = ""
}

variable "landing_page_bucket_domain" {
  type        = string
  description = "S3 landing page bucket domain name"
  default     = ""
}

variable "domain_name" {
  type    = string
  default = "dojangkok.cloud"
}

# Monitoring source CIDRs (cross-VPC)
variable "monitoring_source_cidrs" {
  type    = list(string)
  default = []
}

# ==============================================
# AI Server (GCP → AWS 이전)
# ==============================================

variable "custom_ami_id" {
  type        = string
  description = "Packer docker-base AMI ID (arm64)"
  default     = ""
}

variable "ai_instance_type" {
  type    = string
  default = "t4g.medium"
}

variable "ai_volume_size" {
  type    = number
  default = 30
}

# AI Secrets (passed via -var flag)
variable "ai_vllm_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "ai_backend_internal_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "ai_ocr_api" {
  type      = string
  sensitive = true
  default   = ""
}

variable "ai_rabbitmq_url" {
  type        = string
  sensitive   = true
  description = "amqps://user:pass@mq.dev.dojangkok.cloud:5671/"
  default     = ""
}

# AI Environment
variable "ai_vllm_base_url" {
  type    = string
  default = "http://63.141.33.33:22140/v1"
}

variable "ai_vllm_model" {
  type    = string
  default = "LGAI-EXAONE/EXAONE-3.5-7.8B-Instruct"
}

variable "ai_vllm_lora_adapter_checklist" {
  type    = string
  default = "checklist"
}

variable "ai_vllm_lora_adapter_easycontract" {
  type    = string
  default = "easycontract"
}

variable "ai_backend_callback_base_url" {
  type    = string
  default = "https://dev.dojangkok.cloud/api"
}

variable "ai_http_timeout_sec" {
  type    = string
  default = "180"
}

# Monitoring
variable "loki_url" {
  type    = string
  default = ""
}

variable "tempo_endpoint" {
  type    = string
  default = ""
}

variable "prometheus_url" {
  type    = string
  default = ""
}
