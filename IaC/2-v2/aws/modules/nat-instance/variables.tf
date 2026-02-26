variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t4g.nano"
}

variable "iam_instance_profile" {
  type    = string
  default = null
}

variable "nat_instances" {
  type = map(object({
    subnet_id      = string
    route_table_id = string
  }))
  description = "Map of AZ suffix to subnet_id and route_table_id"
}
