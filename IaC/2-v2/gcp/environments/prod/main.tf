# ==============================================
# GCP PROD 환경 — V2 재설계
# VPC 격리 + Cloud NAT + IAP SSH
# RabbitMQ 도입(#107)으로 LB 제거
# ==============================================

locals {
  env = "prod"
}

# ==========================================
# 0. GCP API 자동 활성화
# ==========================================
module "project_setup" {
  source = "../../modules/project-setup"

  project_id = var.project_id
}

# ==========================================
# 1. Networking (VPC, Subnet, Cloud Router, Cloud NAT)
# ==========================================
module "networking" {
  source = "../../modules/networking"

  project_id = var.project_id
  region     = var.region
  vpc_name   = "dojangkok-ai-vpc"

  subnets = {
    main = {
      name = "dojangkok-ai-${local.env}"
      cidr = "10.10.0.0/24"
    }
  }

  router_name = "dojangkok-ai-router"
  nat_name    = "dojangkok-ai-nat"

  depends_on = [module.project_setup]
}

# ==========================================
# 2. Service Account + Workload Identity
# ==========================================
module "github_actions_sa" {
  source = "../../modules/service-account"

  project_id            = var.project_id
  account_id            = "github-actions-sa"
  display_name          = "GitHub Actions Service Account"
  enable_compute_admin     = true
  enable_iap_tunnel        = true
  enable_sa_user           = true
  enable_security_admin    = false
  enable_artifact_registry = true

  depends_on = [module.project_setup]
}

module "workload_identity" {
  source = "../../modules/workload-identity"

  project_id           = var.project_id
  pool_id              = "github-pool"
  provider_id          = "github-provider"
  attribute_condition  = "assertion.repository_owner == '${var.github_org}'"
  service_account_id   = module.github_actions_sa.id
  principal_set_filter = "attribute.repository_owner/${var.github_org}"
}

# ==========================================
# 2-1. Artifact Registry (Docker 저장소)
# ==========================================
module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id    = var.project_id
  region        = var.region
  repository_id = "dojangkok-ai"
  description   = "도장콕 AI 서비스 Docker 이미지 저장소"

  labels = {
    environment = local.env
    managed_by  = "terraform"
  }

  depends_on = [module.project_setup]
}

# ==========================================
# 3. Firewall Rules (5개)
# ==========================================

# AI Server → vLLM (서브넷 내부)
module "firewall_ai_to_vllm" {
  source = "../../modules/firewall"

  project_id    = var.project_id
  firewall_name = "dojangkok-${local.env}-allow-ai-to-vllm"
  network       = module.networking.vpc_self_link
  description   = "Allow AI Server to vLLM within VPC"
  allow_rules = [
    { protocol = "tcp", ports = ["8001"] }
  ]
  source_ranges = ["10.10.0.0/24"]
  target_tags   = ["vllm"]
  priority      = 1000
}

# AI Server → ChromaDB (서브넷 내부)
module "firewall_ai_to_chromadb" {
  source = "../../modules/firewall"

  project_id    = var.project_id
  firewall_name = "dojangkok-${local.env}-allow-ai-to-chromadb"
  network       = module.networking.vpc_self_link
  description   = "Allow AI Server to ChromaDB within VPC"
  allow_rules = [
    { protocol = "tcp", ports = ["8100"] }
  ]
  source_ranges = ["10.10.0.0/24"]
  target_tags   = ["chromadb"]
  priority      = 1000
}

# AWS Monitoring → GCP VM
module "firewall_monitoring" {
  source = "../../modules/firewall"

  project_id    = var.project_id
  firewall_name = "dojangkok-${local.env}-allow-monitoring"
  network       = module.networking.vpc_self_link
  description   = "Allow AWS monitoring to scrape metrics"
  allow_rules = [
    { protocol = "tcp", ports = ["9090", "9100", "3000"] }
  ]
  source_ranges = var.monitoring_source_ips
  target_tags   = ["dojangkok-monitoring"]
  priority      = 1000
}

# IAP SSH (Google IAP 대역만)
module "firewall_iap_ssh" {
  source = "../../modules/firewall"

  project_id    = var.project_id
  firewall_name = "dojangkok-${local.env}-allow-iap-ssh"
  network       = module.networking.vpc_self_link
  description   = "Allow SSH via IAP tunnel only"
  allow_rules = [
    { protocol = "tcp", ports = ["22"] }
  ]
  source_ranges = ["35.235.240.0/20"]
  priority      = 1000
}

# Internal (서브넷 간 통신)
module "firewall_internal" {
  source = "../../modules/firewall"

  project_id    = var.project_id
  firewall_name = "dojangkok-${local.env}-allow-internal"
  network       = module.networking.vpc_self_link
  description   = "Allow all internal traffic within VPC subnets"
  allow_rules = [
    { protocol = "tcp", ports = ["0-65535"] },
    { protocol = "udp", ports = ["0-65535"] },
    { protocol = "icmp", ports = [] }
  ]
  source_ranges = ["10.10.0.0/24"]
  priority      = 1100
}

# ==========================================
# 4. Health Check (MIG auto-healing용, LB 없이 독립)
# ==========================================
resource "google_compute_health_check" "ai_server" {
  name    = "dojangkok-${local.env}-ai-server-hc"
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
# 5. Compute — AI Server (CPU, MIG)
#    Packer Ubuntu 베이스 + docker-compose
#    CD: MIG 롤링 업데이트 (Instance Template 교체)
# ==========================================
module "ai_server" {
  source = "../../modules/compute-mig"

  project_id    = var.project_id
  instance_name = "dojangkok-${local.env}-ai-server"
  machine_type  = var.ai_server_machine_type
  region        = var.region
  zone          = var.zone
  target_size   = 1

  max_surge       = 1
  max_unavailable = 0

  health_check_id = google_compute_health_check.ai_server.id

  network    = module.networking.vpc_self_link
  subnetwork = module.networking.subnet_self_links["main"]

  network_tags          = ["ai-server", "dojangkok-monitoring"]
  service_account_email = module.github_actions_sa.email

  # Packer 이미지 + startup_script 모드 (COS 제거)
  boot_disk_image = var.ai_server_boot_disk_image

  startup_script = templatefile("${path.module}/scripts/startup-ai-server.sh", {
    compose_content = templatefile("../../docker-compose/ai-server.yml", {
      AI_SERVER_IMAGE            = "${module.artifact_registry.repository_url}/ai-server:latest"
      APP_ENV                    = local.env
      VLLM_BASE_URL              = "http://${module.vllm.internal_ip}:8001/v1"
      VLLM_API_KEY               = var.vllm_api_key
      VLLM_MODEL                 = var.vllm_model
      VLLM_LORA_ADAPTER_CHECKLIST   = var.vllm_lora_adapter_checklist
      VLLM_LORA_ADAPTER_EASYCONTRACT = var.vllm_lora_adapter_easycontract
      CHROMADB_URL               = "http://${module.chromadb.internal_ip}:8100"
      BACKEND_CALLBACK_BASE_URL  = var.backend_callback_base_url
      BACKEND_INTERNAL_TOKEN     = var.backend_internal_token
      OCR_API                    = var.ocr_api
      HTTP_TIMEOUT_SEC           = var.http_timeout_sec
    })
    ar_host = "asia-northeast3-docker.pkg.dev"
  })

  labels = {
    environment = local.env
    service     = "ai-server"
    managed_by  = "terraform"
  }
}

# ==========================================
# 6. Compute — ChromaDB (CPU)
# ==========================================
module "chromadb" {
  source = "../../modules/compute"

  project_id    = var.project_id
  instance_name = "dojangkok-${local.env}-chromadb"
  machine_type  = var.chromadb_machine_type
  zone          = var.zone

  boot_disk_size_gb   = 100
  deletion_protection = true

  network    = module.networking.vpc_self_link
  subnetwork = module.networking.subnet_self_links["main"]

  network_tags          = ["chromadb"]
  service_account_email = module.github_actions_sa.email

  # 컨테이너 모드 (COS)
  container_image = "chromadb/chroma:latest"

  labels = {
    environment = local.env
    service     = "chromadb"
    managed_by  = "terraform"
  }
}

# ==========================================
# 7. Compute — vLLM (GPU)
# ==========================================
module "vllm" {
  source = "../../modules/gpu-compute"

  project_id    = var.project_id
  instance_name = "dojangkok-${local.env}-vllm"
  machine_type  = var.vllm_machine_type
  zone          = var.zone
  gpu_type      = var.vllm_gpu_type
  gpu_count     = 1

  boot_disk_image     = var.vllm_boot_disk_image
  boot_disk_size_gb   = 200
  boot_disk_type      = "pd-ssd"
  deletion_protection = true

  network    = module.networking.vpc_self_link
  subnetwork = module.networking.subnet_self_links["main"]

  network_tags          = ["vllm", "dojangkok-monitoring"]
  service_account_email = module.github_actions_sa.email

  # 컨테이너 모드 (Docker + nvidia-toolkit)
  container_image = "${module.artifact_registry.repository_url}/vllm:latest"

  labels = {
    environment = local.env
    service     = "vllm"
    managed_by  = "terraform"
  }
}
