variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "target_groups" {
  type        = map(any)
  description = "Map of target group name to config (port)"
}

variable "target_group_attachments" {
  type = map(object({
    target_id = string
    port      = number
  }))
  description = "Map of target group key to attachment config"
  default     = {}
}

variable "listeners" {
  type        = map(any)
  description = "Map of listener name to config (port, protocol, certificate_arn, target_group_key)"
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs for NLB (optional)"
  default     = []
}
