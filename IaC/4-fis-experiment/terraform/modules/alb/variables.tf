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

variable "gateway_nodeport" {
  type    = number
  default = 30080
}

variable "worker_instances" {
  description = "Worker name → instance ID"
  type        = map(string)
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
