variable "project_name" {
  type = string
}

variable "s3_bucket_domain_name" {
  type        = string
  description = "S3 bucket regional domain name"
}

variable "acm_certificate_arn" {
  type        = string
  description = "ACM certificate ARN (must be in us-east-1)"
}

variable "aliases" {
  type        = list(string)
  description = "CNAME aliases for the distribution"
  default     = []
}

variable "default_root_object" {
  type    = string
  default = "index.html"
}
