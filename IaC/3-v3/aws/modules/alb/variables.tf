# ============================================================
# V3 K8S IaC — ALB Variables
# ============================================================

variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "ALB 배치할 public 서브넷 ID 목록"
  type        = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "gateway_nodeport" {
  description = "NGINX Gateway Fabric NodePort"
  type        = number
  default     = 30080
}

variable "health_check_path" {
  type    = string
  default = "/healthz"
}

variable "ssl_certificate_arn" {
  description = "ACM 인증서 ARN (null이면 HTTP only)"
  type        = string
  default     = null
}

variable "worker_instances" {
  description = "ALB TG에 등록할 Worker 인스턴스 map (key=이름, value=instance_id)"
  type        = map(string)
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
