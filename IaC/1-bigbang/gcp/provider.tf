# GCP Provider Configuration
# 도장콕 AI 서비스 인프라

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Backend 설정 (GCS)
  # 환경별로 prefix를 다르게 지정:
  #   terraform init -backend-config="prefix=test"  (테스트)
  #   terraform init -backend-config="prefix=prod"  (프로덕션)
  backend "gcs" {
    bucket = "dojangkok-gcp-iac-backend"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
