# VPC + Subnet + Cloud Router + Cloud NAT

# --- VPC ---
resource "google_compute_network" "this" {
  name                    = var.vpc_name
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# --- Subnets ---
resource "google_compute_subnetwork" "subnets" {
  for_each = var.subnets

  name                     = each.value.name
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.this.self_link
  ip_cidr_range            = each.value.cidr
  private_ip_google_access = true
}

# --- Cloud Router ---
resource "google_compute_router" "this" {
  name    = var.router_name
  project = var.project_id
  region  = var.region
  network = google_compute_network.this.self_link
}

# --- Cloud NAT ---
resource "google_compute_router_nat" "this" {
  name                               = var.nat_name
  project                            = var.project_id
  region                             = var.region
  router                             = google_compute_router.this.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
