# Production Environment Outputs

# Service Account
output "service_account_email" {
  description = "GitHub Actions Service Account 이메일"
  value       = module.github_actions_sa.service_account_email
}

# Workload Identity
output "workload_identity_provider" {
  description = "GitHub Actions에서 사용할 Workload Identity Provider"
  value       = module.workload_identity.workload_identity_provider
}

output "workload_identity_pool_name" {
  description = "Workload Identity Pool 이름"
  value       = module.workload_identity.pool_name
}

# Firewall
output "firewall_name" {
  description = "방화벽 규칙 이름"
  value       = module.firewall_ai_server.firewall_name
}

# AI Server
output "ai_server_name" {
  description = "AI 서버 인스턴스 이름"
  value       = module.ai_server.instance_name
}

output "ai_server_external_ip" {
  description = "AI 서버 외부 IP"
  value       = module.ai_server.external_ip
}

output "ai_server_zone" {
  description = "AI 서버 존"
  value       = module.ai_server.zone
}
