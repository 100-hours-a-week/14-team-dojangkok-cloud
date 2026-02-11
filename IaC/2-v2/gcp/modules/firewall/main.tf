# Firewall Rules
resource "google_compute_firewall" "this" {
  name        = var.firewall_name
  network     = var.network
  project     = var.project_id
  description = var.description

  dynamic "allow" {
    for_each = var.allow_rules
    content {
      protocol = allow.value.protocol
      ports    = allow.value.ports
    }
  }

  source_ranges = var.source_ranges
  target_tags   = var.target_tags
  priority      = var.priority
  direction     = var.direction
}
