output "mig_name" {
  description = "MIG 이름"
  value       = module.ai_server.mig_name
}

output "mig_self_link" {
  description = "MIG self_link"
  value       = module.ai_server.mig_self_link
}

output "instance_template_id" {
  description = "Instance Template ID"
  value       = module.ai_server.instance_template_id
}

output "nat_ip" {
  description = "Cloud NAT 고정 아웃바운드 IP (AWS SG에 등록)"
  value       = google_compute_address.nat_ip.address
}
