# --- Networking ---
output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID"
  value       = module.networking.private_subnet_ids
}

# --- ALB ---
output "alb_dns_name" {
  description = "ALB DNS 이름"
  value       = module.alb.alb_dns_name
}

# --- Compute (Dev 고유: Monitoring) ---
output "monitoring_public_ip" {
  description = "Monitoring 퍼블릭 IP"
  value       = module.public_servers.public_ips["monitoring"]
}

# --- DB ---
output "db_server_private_ips" {
  description = "DB 서버 프라이빗 IP"
  value       = module.db_servers.private_ips
}

# --- ASG ---
output "asg_fe_name" {
  description = "FE Auto Scaling Group 이름"
  value       = module.asg_fe.asg_name
}

output "asg_be_name" {
  description = "BE Auto Scaling Group 이름"
  value       = module.asg_be.asg_name
}
