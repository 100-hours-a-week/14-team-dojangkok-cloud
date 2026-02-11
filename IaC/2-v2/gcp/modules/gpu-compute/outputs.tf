output "instance_name" {
  description = "VM 인스턴스 이름"
  value       = google_compute_instance.this.name
}

output "instance_id" {
  description = "VM 인스턴스 ID"
  value       = google_compute_instance.this.instance_id
}

output "self_link" {
  description = "VM self_link"
  value       = google_compute_instance.this.self_link
}

output "internal_ip" {
  description = "내부 IP"
  value       = google_compute_instance.this.network_interface[0].network_ip
}

output "external_ip" {
  description = "외부 IP"
  value       = try(google_compute_instance.this.network_interface[0].access_config[0].nat_ip, null)
}

output "zone" {
  description = "VM 배포 존"
  value       = google_compute_instance.this.zone
}
