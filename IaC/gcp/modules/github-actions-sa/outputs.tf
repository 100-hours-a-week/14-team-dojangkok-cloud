# GitHub Actions Service Account Module Outputs

output "service_account_email" {
  description = "Service Account 이메일"
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

output "service_account_unique_id" {
  description = "Service Account 고유 ID"
  value       = google_service_account.github_actions.unique_id
}
