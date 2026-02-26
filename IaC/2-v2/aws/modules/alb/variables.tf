variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "ssl_certificate_arn" {
  type    = string
  default = null
}

variable "target_groups" {
  type        = map(any)
  description = "Map of target group name to config"
}
