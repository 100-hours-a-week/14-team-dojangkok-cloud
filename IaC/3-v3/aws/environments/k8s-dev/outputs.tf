# ============================================================
# V3 K8S IaC — k8s-dev Outputs
# ============================================================

# --- K8S Nodes ---

output "control_plane" {
  description = "CP 인스턴스 정보"
  value       = module.k8s_nodes.control_plane
}

output "workers" {
  description = "Worker 인스턴스 맵"
  value       = module.k8s_nodes.workers
}

# --- Networking ---

output "nat_eip_public_ip" {
  description = "NAT EIP 퍼블릭 IP (모니터링 SG 허용 등)"
  value       = module.nat_instance.eip_public_ip
}

output "k8s_subnet_ids" {
  description = "K8S 서브넷 ID 맵"
  value       = module.k8s_networking.private_subnet_ids
}

# --- ALB ---

output "alb_dns_name" {
  description = "ALB DNS (접속 주소)"
  value       = module.alb.alb_dns_name
}
