variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "security_groups" {
  type = map(object({
    description   = string
    ingress_rules = list(any)
  }))
}

variable "secondary_cidr" {
  description = "K8S secondary CIDR (data SG 룰용)"
  type        = string
}

variable "data_security_group_id" {
  description = "기존 data 인스턴스의 SG ID"
  type        = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
