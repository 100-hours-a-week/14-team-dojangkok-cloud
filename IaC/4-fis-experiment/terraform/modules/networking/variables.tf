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

variable "igw_id" {
  type = string
}

variable "secondary_cidr" {
  type = string
}

variable "subnets" {
  type = map(object({
    cidr = string
    az   = string
  }))
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
