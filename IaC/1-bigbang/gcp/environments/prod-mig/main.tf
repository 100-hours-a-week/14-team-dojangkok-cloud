# ==============================================
# stellar-fin-485012-r9 — AI Server MIG (운영)
# default VPC + RunPod vLLM + mq.dojangkok.cloud
# 모니터링: 추후 설정
# ==============================================

locals {
  env           = "prod"
  instance_name = "ai-server"
  sa_email      = "github-actions-sa@${var.project_id}.iam.gserviceaccount.com"
}

# ==========================================
# 1. Secret Manager
# ==========================================
module "secrets" {
  source = "../../../../2-v2/gcp/modules/secret-manager"

  project_id = var.project_id
  secret_ids = toset([
    "dojangkok-vllm-api-key",
    "dojangkok-backend-internal-token",
    "dojangkok-ocr-api",
    "dojangkok-rabbitmq-url",
  ])
  secret_values = {
    "dojangkok-vllm-api-key"           = var.vllm_api_key
    "dojangkok-backend-internal-token" = var.backend_internal_token
    "dojangkok-ocr-api"                = var.ocr_api
    "dojangkok-rabbitmq-url"           = var.rabbitmq_url
  }
  accessor_sa_email = local.sa_email
}

# ==========================================
# 2. Cloud NAT (고정 아웃바운드 IP)
# ==========================================
resource "google_compute_address" "nat_ip" {
  name    = "ai-server-nat-ip"
  project = var.project_id
  region  = var.region
}

resource "google_compute_router" "default" {
  name    = "ai-server-router"
  project = var.project_id
  region  = var.region
  network = "default"
}

resource "google_compute_router_nat" "default" {
  name                               = "ai-server-nat"
  project                            = var.project_id
  region                             = var.region
  router                             = google_compute_router.default.name
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = [google_compute_address.nat_ip.self_link]
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# ==========================================
# 3. Firewall — GCP Health Check Probes
# ==========================================
resource "google_compute_firewall" "health_check" {
  name    = "${local.instance_name}-allow-health-check"
  project = var.project_id
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["8000"]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["ai-server"]
}

# ==========================================
# 3. Health Check (MIG auto-healing)
# ==========================================
resource "google_compute_health_check" "ai_server" {
  name    = "${local.instance_name}-hc"
  project = var.project_id

  check_interval_sec  = 30
  timeout_sec         = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 8000
    request_path = "/health"
  }
}

# ==========================================
# 4. AI Server MIG
# ==========================================
module "ai_server" {
  source = "../../../../2-v2/gcp/modules/compute-mig"

  project_id    = var.project_id
  instance_name = local.instance_name
  machine_type  = var.ai_server_machine_type
  region        = var.region
  zone          = var.zone
  target_size   = 1

  max_surge       = 1
  max_unavailable = 0

  health_check_id            = google_compute_health_check.ai_server.id
  health_check_initial_delay = 450 # Ubuntu + Docker 설치 시간 고려

  network    = "default"
  subnetwork = "default"

  enable_external_ip = false # Cloud NAT 사용 → 외부 IP 불필요
  network_tags       = ["ai-server", "monitoring"]

  service_account_email = local.sa_email

  # Ubuntu 22.04 (Packer 이미지 없음 → startup에서 Docker 설치)
  boot_disk_image   = "ubuntu-os-cloud/ubuntu-2204-lts"
  boot_disk_size_gb = 50
  boot_disk_type    = "pd-standard"

  startup_script = templatefile("${path.module}/scripts/startup-ai-server.sh", {
    project_id = var.project_id
    compose_content = templatefile("${path.module}/docker-compose.yml", {
      AI_SERVER_IMAGE                = var.ai_server_image
      APP_ENV                        = local.env
      VLLM_BASE_URL                  = var.vllm_base_url
      VLLM_MODEL                     = var.vllm_model
      VLLM_LORA_ADAPTER_CHECKLIST    = var.vllm_lora_adapter_checklist
      VLLM_LORA_ADAPTER_EASYCONTRACT = var.vllm_lora_adapter_easycontract
      BACKEND_CALLBACK_BASE_URL      = var.backend_callback_base_url
      HTTP_TIMEOUT_SEC               = var.http_timeout_sec
      RABBITMQ_ENABLED               = var.rabbitmq_enabled
      RABBITMQ_PREFETCH_COUNT        = var.rabbitmq_prefetch_count
      RABBITMQ_DECLARE_PASSIVE       = var.rabbitmq_declare_passive
    })
  })

  labels = {
    environment = local.env
    service     = "ai-server"
    managed_by  = "terraform"
  }
}
