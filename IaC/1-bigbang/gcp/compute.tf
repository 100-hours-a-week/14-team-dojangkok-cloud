# AI Server Compute Instance
# GPU 지원 AI 서버 VM

resource "google_compute_instance" "ai_server" {
  name         = var.ai_server_name
  machine_type = var.ai_server_machine_type
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
    network    = var.ai_server_network
    subnetwork = var.ai_server_subnetwork

    # 외부 IP (ephemeral 또는 static)
    dynamic "access_config" {
      for_each = var.ai_server_enable_external_ip ? [1] : []
      content {
        nat_ip       = var.ai_server_static_external_ip
        network_tier = var.ai_server_network_tier
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
    email  = google_service_account.github_actions.email
    scopes = ["cloud-platform"]
  }

  # 메타데이터
  metadata = merge(
    var.ai_server_metadata,
    var.ai_server_enable_oslogin ? { "enable-oslogin" = "TRUE" } : {}
  )

  # 네트워크 태그
  tags = var.ai_server_network_tags

  # 라벨
  labels = var.ai_server_labels

  # 삭제 보호
  deletion_protection = var.ai_server_deletion_protection

  # 스케줄링 설정
  # GPU 사용 시: on_host_maintenance = TERMINATE 필수
  # Spot VM 사용 시: preemptible = true, automatic_restart = false
  scheduling {
    preemptible                 = var.ai_server_is_spot
    automatic_restart           = var.ai_server_is_spot ? false : true
    on_host_maintenance         = var.gpu_count > 0 ? "TERMINATE" : "MIGRATE"
    provisioning_model          = var.ai_server_is_spot ? "SPOT" : "STANDARD"
    instance_termination_action = var.ai_server_is_spot ? "STOP" : null
  }

  # Startup script
  metadata_startup_script = var.ai_server_startup_script

  depends_on = [google_service_account.github_actions]
}
