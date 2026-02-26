variable "applications" {
  type = map(object({
    name = string
  }))
  description = "Map of CodeDeploy applications"
}

variable "deployment_groups" {
  type        = map(any)
  description = "Map of deployment group name to config"
  default     = {}
}

variable "codedeploy_role_arn" {
  type        = string
  description = "IAM role ARN for CodeDeploy"
}
