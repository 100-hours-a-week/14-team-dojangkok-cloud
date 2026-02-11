# CPU Compute Instance (ChromaDB 등)
# container_image 설정 시 COS(Container-Optimized OS) 모드로 전환

locals {
  use_container = var.container_image != null

  # COS 모드: gce-container-declaration YAML 생성
  container_declaration = local.use_container ? yamlencode({
    spec = {
      containers = [{
        image = var.container_image
        env = [for k, v in var.container_env : {
          name  = k
          value = v
        }]
      }]
      restartPolicy = "Always"
    }
  }) : null

  # COS 모드면 COS 이미지, 아니면 지정된 이미지 사용
  boot_image = local.use_container ? "cos-cloud/cos-stable" : var.boot_disk_image
}

resource "google_compute_instance" "this" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  project      = var.project_id

  boot_disk {
    initialize_params {
      image = local.boot_image
      size  = var.boot_disk_size_gb
      type  = var.boot_disk_type
    }
    auto_delete = var.boot_disk_auto_delete
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork

    dynamic "access_config" {
      for_each = var.enable_external_ip ? [1] : []
      content {
        nat_ip       = var.static_external_ip
        network_tier = var.network_tier
      }
    }
  }

  service_account {
    email  = var.service_account_email
    scopes = var.service_account_scopes
  }

  metadata = merge(
    var.metadata,
    var.enable_oslogin ? { "enable-oslogin" = "TRUE" } : {},
    # COS 모드: 컨테이너 선언 메타데이터
    local.use_container ? {
      "gce-container-declaration" = local.container_declaration
    } : {}
  )

  tags = var.network_tags

  labels = local.use_container ? merge(var.labels, {
    "container-vm" = "cos-stable"
  }) : var.labels

  deletion_protection = var.deletion_protection

  scheduling {
    preemptible                 = var.is_spot_instance
    automatic_restart           = var.is_spot_instance ? false : true
    on_host_maintenance         = "MIGRATE"
    provisioning_model          = var.is_spot_instance ? "SPOT" : "STANDARD"
    instance_termination_action = var.is_spot_instance ? "STOP" : null
  }

  # 기존 모드: startup_script (COS 모드에서는 사용 안 함)
  metadata_startup_script = local.use_container ? null : var.startup_script

  lifecycle {
    ignore_changes = [boot_disk[0].initialize_params[0].image]
  }
}
