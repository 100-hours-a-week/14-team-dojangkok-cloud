variable "project_name" {
  type = string
}

variable "name" {
  type        = string
  description = "Name suffix (e.g., fe, be)"
}

variable "instance_type" {
  type    = string
  default = "t4g.small"
}

variable "volume_size" {
  type    = number
  default = 30
}

variable "iam_instance_profile" {
  type = string
}

variable "security_group_ids" {
  type = list(string)
}

variable "subnet_ids" {
  type = list(string)
}

variable "target_group_arns" {
  type    = list(string)
  default = []
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 1
}

variable "desired_capacity" {
  type    = number
  default = 1
}

variable "ami_id" {
  type        = string
  description = "Custom AMI ID. If empty, uses latest Ubuntu 22.04 ARM64."
  default     = ""
}
