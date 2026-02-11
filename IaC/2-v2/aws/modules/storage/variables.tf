variable "s3_buckets" {
  description = "S3 버킷 맵 (key => config)"
  type = map(object({
    name = string
  }))
  default = {}
}

variable "ecr_repositories" {
  description = "ECR 리포지토리 이름 목록"
  type        = list(string)
  default     = []
}
