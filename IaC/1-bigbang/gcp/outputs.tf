# GCP Infrastructure Outputs
# 모든 출력을 한 곳에서 관리

# ============================================
# Service Account
# ============================================
output "service_account_email" {
  description = "GitHub Actions Service Account 이메일"
  value       = google_service_account.github_actions.email
}

output "service_account_id" {
  description = "Service Account ID"
  value       = google_service_account.github_actions.id
}

output "service_account_name" {
  description = "Service Account 전체 이름"
  value       = google_service_account.github_actions.name
}

# ============================================
# Workload Identity
# ============================================
output "workload_identity_provider" {
  description = "GitHub Actions에서 사용할 Workload Identity Provider"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "workload_identity_pool_name" {
  description = "Workload Identity Pool 이름"
  value       = google_iam_workload_identity_pool.github.name
}

output "workload_identity_pool_id" {
  description = "Workload Identity Pool ID"
  value       = google_iam_workload_identity_pool.github.workload_identity_pool_id
}

# ============================================
# Firewall
# ============================================
output "firewall_ai_server_name" {
  description = "AI 서버 방화벽 규칙 이름"
  value       = google_compute_firewall.ai_server.name
}

output "firewall_monitoring_name" {
  description = "모니터링 방화벽 규칙 이름"
  value       = google_compute_firewall.monitoring.name
}

# ============================================
# AI Server
# ============================================
output "ai_server_name" {
  description = "AI 서버 인스턴스 이름"
  value       = google_compute_instance.ai_server.name
}

output "ai_server_external_ip" {
  description = "AI 서버 외부 IP"
  value       = try(google_compute_instance.ai_server.network_interface[0].access_config[0].nat_ip, null)
}

output "ai_server_internal_ip" {
  description = "AI 서버 내부 IP"
  value       = google_compute_instance.ai_server.network_interface[0].network_ip
}

output "ai_server_zone" {
  description = "AI 서버 존"
  value       = google_compute_instance.ai_server.zone
}

output "ai_server_machine_type" {
  description = "AI 서버 머신 타입"
  value       = google_compute_instance.ai_server.machine_type
}
