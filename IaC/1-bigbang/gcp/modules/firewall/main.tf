# Firewall Module
# 배포 포트 방화벽 규칙 관리

resource "google_compute_firewall" "allow_ports" {
  name        = var.firewall_name
  network     = var.network
  project     = var.project_id
  description = var.description

  # 허용할 포트 및 프로토콜
  dynamic "allow" {
    for_each = var.allow_rules
    content {
      protocol = allow.value.protocol
      ports    = allow.value.ports
    }
  }

  # 소스 범위 (기본: 모든 IP)
  source_ranges = var.source_ranges

  # 대상 태그 (특정 VM에만 적용)
  target_tags = var.target_tags

  # 우선순위
  priority = var.priority

  # 방향 (기본: INGRESS)
  direction = var.direction
}
