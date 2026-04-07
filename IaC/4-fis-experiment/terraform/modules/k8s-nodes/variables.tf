variable "project_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t4g.medium"
}

variable "key_pair_name" {
  type = string
}

variable "cp_subnet_id" {
  type = string
}

variable "cp_security_group_ids" {
  type = list(string)
}

variable "worker_az_subnets" {
  description = "AZ suffix → subnet ID (e.g. {a = 'subnet-xxx', b = '...', c = '...'})"
  type        = map(string)
}

variable "worker_security_group_ids" {
  type = list(string)
}

variable "iam_instance_profile" {
  type = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
