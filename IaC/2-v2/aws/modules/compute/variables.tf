variable "project_name" {
  type = string
}

variable "instances" {
  type        = map(any)
  description = "Map of instance name to config"
}
