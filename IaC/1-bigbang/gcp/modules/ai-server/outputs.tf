# AI Server Module Outputs

output "instance_name" {
  description = "VM 인스턴스 이름"
  value       = google_compute_instance.ai_server.name
}

output "instance_id" {
  description = "VM 인스턴스 ID"
  value       = google_compute_instance.ai_server.instance_id
}

output "self_link" {
  description = "VM self_link"
  value       = google_compute_instance.ai_server.self_link
}

output "internal_ip" {
  description = "내부 IP 주소"
  value       = google_compute_instance.ai_server.network_interface[0].network_ip
}

output "external_ip" {
  description = "외부 IP 주소 (할당된 경우)"
  value       = try(google_compute_instance.ai_server.network_interface[0].access_config[0].nat_ip, null)
}

output "zone" {
  description = "VM 배포 존"
  value       = google_compute_instance.ai_server.zone
}

output "machine_type" {
  description = "VM 머신 타입"
  value       = google_compute_instance.ai_server.machine_type
}
