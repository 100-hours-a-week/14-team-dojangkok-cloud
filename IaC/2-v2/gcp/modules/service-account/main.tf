# Service Account 및 IAM 권한 관리
resource "google_service_account" "this" {
  account_id   = var.account_id
  display_name = var.display_name
  description  = var.description
  project      = var.project_id
}

resource "google_project_iam_member" "compute_instance_admin" {
  count   = var.enable_compute_admin ? 1 : 0
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.this.email}"
}

resource "google_project_iam_member" "iap_tunnel_user" {
  count   = var.enable_iap_tunnel ? 1 : 0
  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:${google_service_account.this.email}"
}

resource "google_project_iam_member" "service_account_user" {
  count   = var.enable_sa_user ? 1 : 0
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.this.email}"
}

resource "google_project_iam_member" "compute_security_admin" {
  count   = var.enable_security_admin ? 1 : 0
  project = var.project_id
  role    = "roles/compute.securityAdmin"
  member  = "serviceAccount:${google_service_account.this.email}"
}

resource "google_project_iam_member" "artifact_registry_writer" {
  count   = var.enable_artifact_registry ? 1 : 0
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.this.email}"
}
