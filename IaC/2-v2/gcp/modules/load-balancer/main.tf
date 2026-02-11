# External HTTPS Load Balancer

# --- 글로벌 외부 고정 IP ---
resource "google_compute_global_address" "this" {
  name    = var.static_ip_name
  project = var.project_id
}

# --- Health Check ---
resource "google_compute_health_check" "this" {
  name    = var.health_check_name
  project = var.project_id

  check_interval_sec  = var.health_check_interval
  timeout_sec         = var.health_check_timeout
  healthy_threshold   = var.healthy_threshold
  unhealthy_threshold = var.unhealthy_threshold

  http_health_check {
    port         = var.health_check_port
    request_path = var.health_check_path
  }
}

# --- Backend Service ---
resource "google_compute_backend_service" "this" {
  name        = var.backend_service_name
  project     = var.project_id
  protocol    = "HTTP"
  port_name   = var.backend_port_name
  timeout_sec = var.backend_timeout

  health_checks = [google_compute_health_check.this.id]

  backend {
    group           = var.instance_group
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
  }

  log_config {
    enable      = true
    sample_rate = 0.5
  }
}

# --- URL Map ---
resource "google_compute_url_map" "this" {
  name            = var.url_map_name
  project         = var.project_id
  default_service = google_compute_backend_service.this.id
}

# --- HTTP Target Proxy (SSL 인증서 없을 때) ---
resource "google_compute_target_http_proxy" "this" {
  count = var.ssl_certificate_domains == null ? 1 : 0

  name    = "${var.url_map_name}-http-proxy"
  project = var.project_id
  url_map = google_compute_url_map.this.id
}

# --- HTTP Forwarding Rule (SSL 없을 때) ---
resource "google_compute_global_forwarding_rule" "http" {
  count = var.ssl_certificate_domains == null ? 1 : 0

  name       = "${var.url_map_name}-http-rule"
  project    = var.project_id
  target     = google_compute_target_http_proxy.this[0].id
  ip_address = google_compute_global_address.this.address
  port_range = "80"
}

# --- Managed SSL Certificate (도메인 있을 때) ---
resource "google_compute_managed_ssl_certificate" "this" {
  count = var.ssl_certificate_domains != null ? 1 : 0

  name    = "${var.url_map_name}-ssl-cert"
  project = var.project_id

  managed {
    domains = var.ssl_certificate_domains
  }
}

# --- HTTPS Target Proxy (SSL 인증서 있을 때) ---
resource "google_compute_target_https_proxy" "this" {
  count = var.ssl_certificate_domains != null ? 1 : 0

  name             = "${var.url_map_name}-https-proxy"
  project          = var.project_id
  url_map          = google_compute_url_map.this.id
  ssl_certificates = [google_compute_managed_ssl_certificate.this[0].id]
}

# --- HTTPS Forwarding Rule (SSL 있을 때) ---
resource "google_compute_global_forwarding_rule" "https" {
  count = var.ssl_certificate_domains != null ? 1 : 0

  name       = "${var.url_map_name}-https-rule"
  project    = var.project_id
  target     = google_compute_target_https_proxy.this[0].id
  ip_address = google_compute_global_address.this.address
  port_range = "443"
}
