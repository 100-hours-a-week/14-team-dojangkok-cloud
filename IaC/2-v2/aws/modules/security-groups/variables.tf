variable "project_name" {
  type = string
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "vpc_id" {
  type = string
}

variable "security_groups" {
  type        = map(any)
  description = "Map of security group name to config (description, ingress_rules)"
}

variable "enable_s3_endpoint" {
  type    = bool
  default = true
}

variable "route_table_ids" {
  type        = list(string)
  description = "Route table IDs for S3 VPC endpoint"
  default     = []
}
