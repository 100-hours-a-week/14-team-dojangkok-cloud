# CPU Compute with MIG (Managed Instance Group)
# AI Server 등 롤링 업데이트가 필요한 CPU VM용
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

resource "google_compute_instance_template" "this" {
  name_prefix  = "${var.instance_name}-"
  machine_type = var.machine_type
  project      = var.project_id
  region       = var.region

  disk {
    source_image = local.boot_image
    disk_size_gb = var.boot_disk_size_gb
    disk_type    = var.boot_disk_type
    auto_delete  = var.boot_disk_auto_delete
    boot         = true
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork

    dynamic "access_config" {
      for_each = var.enable_external_ip ? [1] : []
      content {
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
    # 기존 모드: startup_script 메타데이터
    !local.use_container && var.startup_script != null ? { "startup-script" = var.startup_script } : {},
    # COS 모드: 컨테이너 선언 메타데이터
    local.use_container ? {
      "gce-container-declaration" = local.container_declaration
    } : {}
  )

  tags = var.network_tags

  labels = local.use_container ? merge(var.labels, {
    "container-vm" = "cos-stable"
  }) : var.labels

  scheduling {
    preemptible                 = var.is_spot_instance
    automatic_restart           = var.is_spot_instance ? false : true
    on_host_maintenance         = "MIGRATE"
    provisioning_model          = var.is_spot_instance ? "SPOT" : "STANDARD"
    instance_termination_action = var.is_spot_instance ? "STOP" : null
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Managed Instance Group
resource "google_compute_instance_group_manager" "this" {
  name               = "${var.instance_name}-mig"
  base_instance_name = var.instance_name
  zone               = var.zone
  project            = var.project_id
  target_size        = var.target_size

  version {
    instance_template = google_compute_instance_template.this.self_link_unique
  }

  # 롤링 업데이트 정책
  update_policy {
    type                         = "PROACTIVE"
    minimal_action               = "REPLACE"
    most_disruptive_allowed_action = "REPLACE"
    max_surge_fixed              = var.max_surge
    max_unavailable_fixed        = var.max_unavailable
    replacement_method           = "SUBSTITUTE"
  }

  dynamic "named_port" {
    for_each = var.named_ports
    content {
      name = named_port.value.name
      port = named_port.value.port
    }
  }

  dynamic "auto_healing_policies" {
    for_each = var.health_check_id != null ? [1] : []
    content {
      health_check      = var.health_check_id
      initial_delay_sec = var.health_check_initial_delay
    }
  }

  # CD 파이프라인이 instance template을 직접 관리하므로
  # Terraform이 version 변경을 감지해도 되돌리지 않도록 무시
  lifecycle {
    ignore_changes = [version]
  }
}
