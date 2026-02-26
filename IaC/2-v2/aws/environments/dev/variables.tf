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
