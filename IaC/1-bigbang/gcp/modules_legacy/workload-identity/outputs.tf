# Workload Identity Module Outputs

output "pool_name" {
  description = "Workload Identity Pool 전체 이름"
  value       = google_iam_workload_identity_pool.github.name
}

output "pool_id" {
  description = "Workload Identity Pool ID"
  value       = google_iam_workload_identity_pool.github.workload_identity_pool_id
}

output "provider_name" {
  description = "Workload Identity Provider 전체 이름"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "provider_id" {
  description = "Workload Identity Provider ID"
  value       = google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id
}

# GitHub Actions에서 사용할 workload_identity_provider 값
output "workload_identity_provider" {
  description = "GitHub Actions YAML에서 사용할 workload_identity_provider 값"
  value       = google_iam_workload_identity_pool_provider.github.name
}
