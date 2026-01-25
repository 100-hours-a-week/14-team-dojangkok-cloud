variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "리소스 이름에 사용할 프로젝트 접두사"
  type        = string
  default     = "ktb-team14-dojangkok"
}

variable "vpc_cidr" {
  description = "VPC의 CIDR 블록"
  type        = string
  default     = "10.0.0.0/18"
}
