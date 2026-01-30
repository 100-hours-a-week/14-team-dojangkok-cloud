# Workload Identity
# GitHub OIDC 인증을 위한 Pool, Provider, IAM Binding 관리

# Workload Identity Pool
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = var.wi_pool_id
  display_name              = var.wi_pool_display_name
  description               = "Workload Identity Pool for GitHub Actions OIDC"
  project                   = var.project_id
  disabled                  = false
}

# Workload Identity Provider (GitHub OIDC)
resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.wi_provider_id
  display_name                       = var.wi_provider_display_name
  description                        = "GitHub OIDC Provider"
  project                            = var.project_id

  # GitHub OIDC issuer
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  # Attribute mapping
  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }

  # Attribute condition (GitHub org 전체 허용)
  attribute_condition = "assertion.repository_owner == '${var.github_org}'"
}

# Service Account <-> Workload Identity Binding
resource "google_service_account_iam_member" "workload_identity_user" {
  service_account_id = google_service_account.github_actions.id
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository_owner/${var.github_org}"
}
