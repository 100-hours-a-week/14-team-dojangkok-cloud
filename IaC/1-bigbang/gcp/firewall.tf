# Firewall Rules
# AI 서버 방화벽 규칙

# AI 서버 배포 포트 (FastAPI, health check)
resource "google_compute_firewall" "ai_server" {
  name        = var.firewall_name
  network     = var.firewall_network
  project     = var.project_id
  description = "Allow AI server ports (FastAPI, health check)"

  allow {
    protocol = "tcp"
    ports    = var.firewall_ports
  }

  source_ranges = var.firewall_source_ranges
  target_tags   = var.firewall_target_tags
  priority      = 1000
  direction     = "INGRESS"
}

# 모니터링 포트 (Prometheus node_exporter, nvidia_gpu_exporter)
resource "google_compute_firewall" "monitoring" {
  name        = "dojangkok-monitoring"
  network     = var.firewall_network
  project     = var.project_id
  description = "Allow monitoring ports (node_exporter, gpu_exporter)"

  allow {
    protocol = "tcp"
    ports    = ["9100", "9400"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["dojangkok-monitoring"]
  priority      = 1000
  direction     = "INGRESS"
}
