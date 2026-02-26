variable "project_name" {
  type = string
}

variable "certificates" {
  type = map(object({
    domain_name               = string
    subject_alternative_names = optional(list(string), [])
  }))
  description = "Map of certificate name to config"
}
