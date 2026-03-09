# ==============================================
# stellar-fin-485012-r9 — AI Server MIG (prod)
# default VPC + RunPod vLLM + Alloy 모니터링
# Cloud NAT / Secret Manager / SA: prod-mig에서 관리
# ==============================================

locals {
  env                   = "prod"
  instance_name         = "ai-server"
  sa_email              = "github-actions-sa@${var.project_id}.iam.gserviceaccount.com"
  alloy_config_template = "../../docker-compose/alloy/config.alloy"
}

# ==========================================
# 1. Firewall — GCP Health Check Probes
# ==========================================
module "firewall_health_check" {
  source = "../../modules/firewall"

  project_id    = var.project_id
  firewall_name = "${local.instance_name}-${local.env}-allow-health-check"
  network       = "default"
  description   = "Allow GCP health check probes to AI Server"
  allow_rules = [
    { protocol = "tcp", ports = ["8000"] }
  ]
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["ai-server"]
  priority      = 1000
}

# ==========================================
# 2. Firewall — AWS Monitoring
# ==========================================
module "firewall_monitoring" {
  source = "../../modules/firewall"

  project_id    = var.project_id
  firewall_name = "${local.instance_name}-${local.env}-allow-monitoring"
  network       = "default"
  description   = "Allow AWS monitoring to scrape metrics"
  allow_rules = [
    { protocol = "tcp", ports = ["9090", "9100", "3000"] }
  ]
  source_ranges = var.monitoring_source_ips
  target_tags   = ["monitoring"]
  priority      = 1000
}

# ==========================================
# 3. Health Check (MIG auto-healing)
# ==========================================
resource "google_compute_health_check" "ai_server" {
  name    = "${local.instance_name}-${local.env}-hc"
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
  source = "../../modules/compute-mig"

  project_id    = var.project_id
  instance_name = "${local.instance_name}-${local.env}"
  machine_type  = var.ai_server_machine_type
  region        = var.region
  zone          = var.zone
  target_size   = 1

  max_surge       = 1
  max_unavailable = 0

  health_check_id            = google_compute_health_check.ai_server.id
  health_check_initial_delay = 300

  network    = "default"
  subnetwork = "default"

  enable_external_ip = false # Cloud NAT 사용
  network_tags       = ["ai-server", "monitoring"]

  service_account_email = local.sa_email

  boot_disk_image   = var.ai_server_boot_disk_image
  boot_disk_size_gb = 50
  boot_disk_type    = "pd-standard"

  startup_script = templatefile("${path.module}/scripts/startup-ai-server.sh", {
    project_id = var.project_id
    compose_content = templatefile("../../docker-compose/ai-server.yml", {
      AI_SERVER_IMAGE                = var.ai_server_image
      APP_ENV                        = local.env
      VLLM_BASE_URL                  = var.vllm_base_url
      VLLM_MODEL                     = var.vllm_model
      VLLM_LORA_ADAPTER_CHECKLIST    = var.vllm_lora_adapter_checklist
      VLLM_LORA_ADAPTER_EASYCONTRACT = var.vllm_lora_adapter_easycontract
      CHROMADB_URL                   = ""
      BACKEND_CALLBACK_BASE_URL      = var.backend_callback_base_url
      HTTP_TIMEOUT_SEC               = var.http_timeout_sec

      RABBITMQ_ENABLED                           = var.rabbitmq_enabled
      RABBITMQ_PREFETCH_COUNT                    = var.rabbitmq_prefetch_count
      RABBITMQ_DECLARE_PASSIVE                   = var.rabbitmq_declare_passive
      WORKER_RETRY_MAX_ATTEMPTS                  = var.worker_retry_max_attempts
      WORKER_RETRY_BACKOFF_BASE_SEC              = var.worker_retry_backoff_base_sec
      EXTERNAL_RETRY_MAX_ATTEMPTS                = var.external_retry_max_attempts
      EXTERNAL_RETRY_BACKOFF_BASE_SEC            = var.external_retry_backoff_base_sec
      EASY_CONTRACT_CANCEL_TTL_SEC               = var.easy_contract_cancel_ttl_sec
      EASY_CONTRACT_CANCEL_CLEANUP_INTERVAL_SEC  = var.easy_contract_cancel_cleanup_interval_sec

      RABBITMQ_REQUEST_EXCHANGE_EASY_CONTRACT    = var.rabbitmq_request_exchange_easy_contract
      RABBITMQ_REQUEST_QUEUE_EASY_CONTRACT       = var.rabbitmq_request_queue_easy_contract
      RABBITMQ_REQUEST_ROUTING_KEY_EASY_CONTRACT = var.rabbitmq_request_routing_key_easy_contract
      RABBITMQ_REQUEST_EXCHANGE_CHECKLIST        = var.rabbitmq_request_exchange_checklist
      RABBITMQ_REQUEST_QUEUE_CHECKLIST           = var.rabbitmq_request_queue_checklist
      RABBITMQ_REQUEST_ROUTING_KEY_CHECKLIST     = var.rabbitmq_request_routing_key_checklist
      RABBITMQ_CANCEL_EXCHANGE_EASY_CONTRACT     = var.rabbitmq_cancel_exchange_easy_contract
      RABBITMQ_CANCEL_QUEUE_EASY_CONTRACT        = var.rabbitmq_cancel_queue_easy_contract
      RABBITMQ_CANCEL_ROUTING_KEY_EASY_CONTRACT  = var.rabbitmq_cancel_routing_key_easy_contract
      RABBITMQ_RESULT_EXCHANGE                   = var.rabbitmq_result_exchange
      RABBITMQ_RESULT_QUEUE                      = var.rabbitmq_result_queue
      RABBITMQ_RESULT_ROUTING_KEY                = var.rabbitmq_result_routing_key
    })
    alloy_config = templatefile(local.alloy_config_template, {
      hostname             = "${local.instance_name}-${local.env}"
      service_name         = "ai-server"
      loki_url             = var.loki_url
      tempo_endpoint       = var.tempo_endpoint
      prometheus_url       = var.prometheus_url
      enable_app_metrics   = true
      app_metrics_port     = "8000"
      enable_vllm_metrics  = false
      vllm_metrics_port    = "8001"
    })
    ar_host = "asia-northeast3-docker.pkg.dev"
  })

  labels = {
    environment = local.env
    service     = "ai-server"
    managed_by  = "terraform"
  }
}
