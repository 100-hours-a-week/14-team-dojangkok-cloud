variable "project_name" {
  type = string
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "public_subnets" {
  type = map(object({
    cidr = string
    az   = string
  }))
  description = "Public subnet definitions"
}

variable "private_subnets" {
  type = map(object({
    cidr = string
    az   = string
  }))
  description = "Private subnet definitions"
}

variable "availability_zones" {
  type        = list(string)
  description = "List of AZ suffixes (e.g. [\"a\", \"c\"])"
  default     = ["a", "c"]
}
