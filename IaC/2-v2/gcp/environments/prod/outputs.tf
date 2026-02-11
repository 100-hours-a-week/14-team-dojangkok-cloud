# --- Service Account ---
output "service_account_email" {
  description = "GitHub Actions SA 이메일"
  value       = module.github_actions_sa.email
}

# --- Workload Identity ---
output "workload_identity_provider" {
  description = "GitHub Actions workload_identity_provider 값"
  value       = module.workload_identity.workload_identity_provider
}

# --- Networking ---
output "vpc_name" {
  description = "VPC 이름"
  value       = module.networking.vpc_name
}

output "subnet_self_links" {
  description = "서브넷 self_link 맵"
  value       = module.networking.subnet_self_links
}

# --- Compute ---
output "ai_server_mig_name" {
  description = "AI Server MIG 이름"
  value       = module.ai_server.mig_name
}

output "chromadb_internal_ip" {
  description = "ChromaDB 내부 IP"
  value       = module.chromadb.internal_ip
}

output "vllm_internal_ip" {
  description = "vLLM 내부 IP"
  value       = module.vllm.internal_ip
}
