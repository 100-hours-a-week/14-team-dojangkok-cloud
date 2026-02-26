# Secret Manager — 시크릿 생성 + 초기 버전 + IAM 바인딩
# lifecycle ignore_changes로 이후 값 변경은 Console/gcloud에서 관리
# secret_ids (non-sensitive)로 for_each, secret_values (sensitive)로 값 주입

resource "google_secret_manager_secret" "this" {
  for_each  = var.secret_ids
  project   = var.project_id
  secret_id = each.value

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "this" {
  for_each    = var.secret_ids
  secret      = google_secret_manager_secret.this[each.value].id
  secret_data = var.secret_values[each.value]

  lifecycle {
    ignore_changes = [secret_data]
  }
}

resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each  = var.secret_ids
  project   = var.project_id
  secret_id = google_secret_manager_secret.this[each.value].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.accessor_sa_email}"
}
