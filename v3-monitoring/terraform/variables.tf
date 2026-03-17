# ==============================================
# V3 Monitoring — Variables
# ==============================================

variable "region" {
  description = "AWS region"
  type        = string
}

variable "aws_profile" {
  description = "AWS CLI profile"
  type        = string
}

variable "name_prefix" {
  description = "Naming prefix (e.g. dev-dojangkok-v3)"
  type        = string
}

# --- VPC / Subnet ---

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR for SG ingress"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for monitor EC2 (public)"
  type        = string
}

# --- EC2 ---

variable "ami_id" {
  description = "AMI ID (Ubuntu ARM64, Docker pre-installed)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t4g.medium"
}

variable "volume_size" {
  description = "Root EBS volume size (GB)"
  type        = number
  default     = 50
}

# --- Security Group Sources ---

variable "admin_ip" {
  description = "Admin IP for Grafana access (CIDR)"
  type        = string
}

variable "gcp_nat_ip" {
  description = "GCP Cloud NAT IP (CIDR, optional)"
  type        = string
  default     = ""
}

variable "k8s_nat_ips" {
  description = "K8S NAT Instance EIPs (CIDR list)"
  type        = list(string)
  default     = []
}

variable "extra_admin_ips" {
  description = "Additional admin IPs for Grafana access (CIDR list)"
  type        = list(string)
  default     = []
}

# --- S3 ---

variable "s3_monitoring_bucket" {
  description = "S3 bucket name for monitoring data (Loki/Tempo/Thanos)"
  type        = string
}
