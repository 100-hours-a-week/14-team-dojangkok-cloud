variable "roles" {
  type        = map(any)
  description = <<-EOT
    Map of service key to IAM role config.
    Each entry: {
      role_name               = string
      service_principal       = string (default: "ec2.amazonaws.com")
      create_instance_profile = bool (default: true)
      policy_arns             = list(string)
      inline_policy           = string (optional, JSON)
    }
  EOT
}
