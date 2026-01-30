# GitHub Actions Service Account
# Service Account 및 IAM 권한 관리

resource "google_service_account" "github_actions" {
  account_id   = var.sa_account_id
  display_name = var.sa_display_name
  description  = "Service Account for GitHub Actions CD pipeline"
  project      = var.project_id
}

# Compute Instance Admin 권한 (VM 관리)
resource "google_project_iam_member" "compute_instance_admin" {
  count   = var.enable_compute_admin ? 1 : 0
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# IAP Tunnel User 권한 (SSH 접속)
resource "google_project_iam_member" "iap_tunnel_user" {
  count   = var.enable_iap_tunnel ? 1 : 0
  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Service Account User 권한
resource "google_project_iam_member" "service_account_user" {
  count   = var.enable_sa_user ? 1 : 0
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Compute Security Admin 권한 (방화벽 관리)
resource "google_project_iam_member" "compute_security_admin" {
  count   = var.enable_security_admin ? 1 : 0
  project = var.project_id
  role    = "roles/compute.securityAdmin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}
