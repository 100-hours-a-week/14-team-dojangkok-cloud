output "firewall_name" {
  description = "방화벽 규칙 이름"
  value       = google_compute_firewall.this.name
}

output "firewall_self_link" {
  description = "방화벽 규칙 self_link"
  value       = google_compute_firewall.this.self_link
}
