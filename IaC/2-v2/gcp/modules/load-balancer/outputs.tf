output "lb_ip" {
  description = "Load Balancer 외부 IP"
  value       = google_compute_global_address.this.address
}

output "health_check_id" {
  description = "Health Check ID"
  value       = google_compute_health_check.this.id
}

output "backend_service_id" {
  description = "Backend Service ID"
  value       = google_compute_backend_service.this.id
}

output "url_map_id" {
  description = "URL Map ID"
  value       = google_compute_url_map.this.id
}
