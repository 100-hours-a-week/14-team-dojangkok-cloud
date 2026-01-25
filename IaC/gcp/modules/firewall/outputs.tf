# Firewall Module Outputs

output "firewall_name" {
  description = "방화벽 규칙 이름"
  value       = google_compute_firewall.allow_ports.name
}

output "firewall_id" {
  description = "방화벽 규칙 ID"
  value       = google_compute_firewall.allow_ports.id
}

output "firewall_self_link" {
  description = "방화벽 규칙 self_link"
  value       = google_compute_firewall.allow_ports.self_link
}
