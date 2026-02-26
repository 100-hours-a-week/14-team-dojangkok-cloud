variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "project_name" {
  type    = string
  default = "prod-dojangkok-v2"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "vpc_cidr" {
  type    = string
  default = "10.3.0.0/18"
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

variable "fe_instance_type" {
  type    = string
  default = "t4g.small"
}

variable "be_instance_type" {
  type    = string
  default = "t4g.small"
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

variable "fe_volume_size" {
  type    = number
  default = 30
}

variable "be_volume_size" {
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
  }
}

# GCP NAT IP
variable "gcp_nat_ip" {
  type        = string
  description = "GCP Cloud NAT IP for NLB security group"
  default     = ""
}

# ACM certificate ARN
variable "ssl_certificate_arn" {
  type        = string
  description = "ACM certificate ARN for ALB/NLB"
  default     = ""
}

variable "domain_name" {
  type    = string
  default = "dojangkok.cloud"
}

# Monitoring source CIDRs
variable "monitoring_source_cidrs" {
  type    = list(string)
  default = []
}

# Custom AMI (Docker + CodeDeploy Agent pre-installed)
variable "custom_ami_id" {
  type        = string
  description = "Custom AMI ID for FE/BE ASG launch templates"
  default     = ""
}

# CodeDeploy
variable "codedeploy_role_arn" {
  type        = string
  description = "IAM role ARN for CodeDeploy service"
}
