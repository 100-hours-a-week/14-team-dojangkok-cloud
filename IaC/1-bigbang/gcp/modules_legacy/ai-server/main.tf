# AI Server Module
# AI 서버 Compute Instance 관리 (GPU 지원)

resource "google_compute_instance" "ai_server" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  project      = var.project_id

  # 부팅 디스크
  boot_disk {
    initialize_params {
      image = var.boot_disk_image
      size  = var.boot_disk_size_gb
      type  = var.boot_disk_type
    }
    auto_delete = var.boot_disk_auto_delete
  }

  # 네트워크 인터페이스
  network_interface {
    network    = var.network
    subnetwork = var.subnetwork

    # 외부 IP (ephemeral 또는 static)
    dynamic "access_config" {
      for_each = var.enable_external_ip ? [1] : []
      content {
        nat_ip       = var.static_external_ip
        network_tier = var.network_tier
      }
    }
  }

  # GPU 설정
  dynamic "guest_accelerator" {
    for_each = var.gpu_count > 0 ? [1] : []
    content {
      type  = var.gpu_type
      count = var.gpu_count
    }
  }

  # 서비스 계정
  service_account {
    email  = var.service_account_email
    scopes = var.service_account_scopes
  }

  # 메타데이터
  metadata = merge(
    var.metadata,
    var.enable_oslogin ? { "enable-oslogin" = "TRUE" } : {}
  )

  # 네트워크 태그
  tags = var.network_tags

  # 라벨
  labels = var.labels

  # 삭제 보호
  deletion_protection = var.deletion_protection

  # 스케줄링 설정
  # GPU 사용 시: on_host_maintenance = TERMINATE 필수
  # Spot VM 사용 시: preemptible = true, automatic_restart = false
  scheduling {
    preemptible                 = var.is_spot_instance
    automatic_restart           = var.is_spot_instance ? false : true
    on_host_maintenance         = var.gpu_count > 0 ? "TERMINATE" : "MIGRATE"
    provisioning_model          = var.is_spot_instance ? "SPOT" : "STANDARD"
    instance_termination_action = var.is_spot_instance ? "STOP" : null
  }

  # Startup script
  metadata_startup_script = var.startup_script
}
