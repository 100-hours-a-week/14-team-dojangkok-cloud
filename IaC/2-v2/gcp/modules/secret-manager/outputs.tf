output "secret_ids" {
  description = "생성된 시크릿 ID 맵"
  value       = { for k, v in google_secret_manager_secret.this : k => v.secret_id }
}

output "secret_names" {
  description = "생성된 시크릿 전체 이름 맵"
  value       = { for k, v in google_secret_manager_secret.this : k => v.name }
}
