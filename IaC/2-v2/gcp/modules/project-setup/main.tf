# GCP API 자동 활성화
# 다른 GCP 계정/프로젝트에서도 terraform apply만으로 동작하도록 필수 API 활성화

resource "google_project_service" "apis" {
  for_each = toset(var.enabled_apis)

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}
