output "enabled_apis" {
  description = "활성화된 API 목록"
  value       = [for api in google_project_service.apis : api.service]
}
