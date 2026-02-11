output "pool_name" {
  description = "Pool 전체 이름"
  value       = google_iam_workload_identity_pool.this.name
}

output "pool_id" {
  description = "Pool ID"
  value       = google_iam_workload_identity_pool.this.workload_identity_pool_id
}

output "provider_name" {
  description = "Provider 전체 이름"
  value       = google_iam_workload_identity_pool_provider.this.name
}

output "workload_identity_provider" {
  description = "GitHub Actions에서 사용할 workload_identity_provider 값"
  value       = google_iam_workload_identity_pool_provider.this.name
}
