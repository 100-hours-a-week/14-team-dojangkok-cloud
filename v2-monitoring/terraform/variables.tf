# ==============================================
# Variables
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
  description = "Naming prefix (e.g. dev-dojangkok-v2)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR for SG ingress"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for monitor EC2"
  type        = string
}

variable "ami_id" {
  description = "AMI ID (Ubuntu ARM64)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t4g.medium"
}

variable "iam_instance_profile" {
  description = "IAM instance profile name"
  type        = string
}

variable "admin_ip" {
  description = "Admin IP for Grafana access (CIDR)"
  type        = string
}

variable "gcp_nat_ip" {
  description = "GCP Cloud NAT IP (CIDR, optional)"
  type        = string
  default     = ""
}

variable "extra_admin_ips" {
  description = "Additional admin IPs for Grafana access (CIDR list)"
  type        = list(string)
  default     = []
}
