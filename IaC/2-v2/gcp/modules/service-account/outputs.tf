output "email" {
  description = "Service Account 이메일"
  value       = google_service_account.this.email
}

output "id" {
  description = "Service Account ID"
  value       = google_service_account.this.id
}

output "name" {
  description = "Service Account 전체 이름"
  value       = google_service_account.this.name
}

output "unique_id" {
  description = "Service Account 고유 ID"
  value       = google_service_account.this.unique_id
}
