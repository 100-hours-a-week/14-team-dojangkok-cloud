output "vpc_self_link" {
  description = "VPC self_link"
  value       = google_compute_network.this.self_link
}

output "vpc_name" {
  description = "VPC 이름"
  value       = google_compute_network.this.name
}

output "subnet_self_links" {
  description = "서브넷 self_link 맵"
  value       = { for k, v in google_compute_subnetwork.subnets : k => v.self_link }
}

output "subnet_cidrs" {
  description = "서브넷 CIDR 맵"
  value       = { for k, v in google_compute_subnetwork.subnets : k => v.ip_cidr_range }
}

output "router_name" {
  description = "Cloud Router 이름"
  value       = google_compute_router.this.name
}

output "nat_name" {
  description = "Cloud NAT 이름"
  value       = google_compute_router_nat.this.name
}
