variable "buckets" {
  type        = map(any)
  description = <<-EOT
    Map of bucket key to config.
    Each entry: {
      name                    = string
      block_public_acls       = bool (default: true)
      block_public_policy     = bool (default: true)
      ignore_public_acls      = bool (default: true)
      restrict_public_buckets = bool (default: true)
      versioning              = bool (default: false)
    }
  EOT
}
