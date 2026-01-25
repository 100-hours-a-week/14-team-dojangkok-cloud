# Production Environment (dojangkok-ai)
# GCP 프로덕션 환경 인프라 정의

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Backend 설정 (local 또는 GCS)
  # 추후 GCS로 변경 시:
  # backend "gcs" {
  #   bucket = "dojangkok-terraform-state"
  #   prefix = "prod"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ============================================
# GitHub Actions Service Account
# ============================================
module "github_actions_sa" {
  source = "../../modules/github-actions-sa"

  project_id           = var.project_id
  account_id           = "github-actions-sa"
  display_name         = "GitHub Actions Service Account"
  enable_compute_admin = true
  enable_iap_tunnel    = true
  enable_sa_user       = true
}

# ============================================
# Workload Identity (GitHub OIDC)
# ============================================
module "workload_identity" {
  source = "../../modules/workload-identity"

  project_id            = var.project_id
  pool_id               = "github-pool"
  pool_display_name     = "GitHub Actions Pool"
  provider_id           = "github-provider"
  provider_display_name = "GitHub OIDC Provider"

  # GitHub Organization 전체 허용 (여러 레포에서 접근 가능)
  attribute_condition = "assertion.repository_owner == '${var.github_org}'"

  # Service Account와 바인딩
  service_account_id   = module.github_actions_sa.service_account_id
  principal_set_filter = "attribute.repository_owner/${var.github_org}"

  depends_on = [module.github_actions_sa]
}

# ============================================
# Firewall Rule (배포 포트)
# ============================================
module "firewall_ai_server" {
  source = "../../modules/firewall"

  project_id    = var.project_id
  firewall_name = "dojangkok-ai-server-fw"
  network       = "default"
  description   = "Allow AI server ports (FastAPI, health check)"

  allow_rules = [
    {
      protocol = "tcp"
      ports    = ["8000", "8001", "8100"]
    }
  ]

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ai-server"]
}

# ============================================
# AI Server VM Instance
# 현재 운영 환경 반영 (n1-standard-4 + T4 GPU)
# 참고: 기존 VM은 수동 관리 중. 재생성 시 이 코드 사용
# ============================================
module "ai_server" {
  source = "../../modules/ai-server"

  project_id    = var.project_id
  instance_name = "ai-server"
  machine_type  = var.ai_server_machine_type
  zone          = var.zone

  # GPU 설정
  gpu_type  = var.gpu_type
  gpu_count = var.gpu_count

  # 디스크 설정
  boot_disk_image   = "ubuntu-os-cloud/ubuntu-2204-lts"
  boot_disk_size_gb = var.boot_disk_size_gb
  boot_disk_type    = "pd-ssd"

  # 네트워크 설정
  network            = "default"
  enable_external_ip = true
  network_tags       = ["ai-server"]

  # 서비스 계정 및 보안
  service_account_email = module.github_actions_sa.service_account_email
  enable_oslogin        = true

  # 라벨
  labels = {
    environment = "prod"
    service     = "ai-server"
    managed_by  = "terraform"
  }

  depends_on = [module.github_actions_sa]
}
