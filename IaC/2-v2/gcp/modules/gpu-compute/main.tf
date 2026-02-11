# GPU Compute Instance (vLLM)
# COS는 GPU를 지원하지 않으므로 accelerator 이미지 위에
# Docker + NVIDIA Container Toolkit을 설치하여 컨테이너 실행

locals {
  use_container = var.container_image != null

  # null-safe 이미지 참조 (heredoc에서 사용)
  _container_image = coalesce(var.container_image, "placeholder")

  # Docker 환경변수 -e 플래그 생성
  docker_env_flags = join(" ", [for k, v in var.container_env : "-e ${k}='${v}'"])

  # Docker 포트 매핑 -p 플래그 생성
  docker_port_flags = join(" ", [for p in var.container_ports : "-p ${p}"])

  # Docker 모드 startup_script (항상 생성, use_container=false면 사용 안 됨)
  docker_startup_script = <<-SCRIPT
#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/container-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[$(date)] Starting Docker container setup..."

# Docker가 이미 설치되어 있으면 스킵
if command -v docker &> /dev/null && docker info &> /dev/null; then
  echo "[$(date)] Docker already installed, skipping installation"
else
  echo "[$(date)] Installing Docker..."
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
  systemctl enable docker
  systemctl start docker
  echo "[$(date)] Docker installed successfully"
fi

# NVIDIA Container Toolkit 설치
if dpkg -l | grep -q nvidia-container-toolkit; then
  echo "[$(date)] NVIDIA Container Toolkit already installed, skipping"
else
  echo "[$(date)] Installing NVIDIA Container Toolkit..."
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' > /etc/apt/sources.list.d/nvidia-container-toolkit.list
  apt-get update -y
  apt-get install -y nvidia-container-toolkit
  nvidia-ctk runtime configure --runtime=docker
  systemctl restart docker
  echo "[$(date)] NVIDIA Container Toolkit installed successfully"
fi

# Artifact Registry 인증 (pkg.dev 이미지인 경우)
if echo "${local._container_image}" | grep -q "pkg.dev"; then
  echo "[$(date)] Configuring Docker auth for Artifact Registry..."
  REGISTRY_HOST=$(echo "${local._container_image}" | grep -oP '^[^/]+')
  gcloud auth configure-docker "$REGISTRY_HOST" --quiet 2>/dev/null || true
fi

# 기존 컨테이너 중지/삭제
CONTAINER_NAME="gpu-app"
docker stop $CONTAINER_NAME 2>/dev/null || true
docker rm $CONTAINER_NAME 2>/dev/null || true

# 이미지 pull
echo "[$(date)] Pulling image: ${local._container_image}"
docker pull ${local._container_image}

# 컨테이너 실행
echo "[$(date)] Starting container..."
docker run -d \
  --name $CONTAINER_NAME \
  --gpus all \
  --restart unless-stopped \
  --network host \
  ${local.docker_env_flags} \
  ${local.docker_port_flags} \
  ${var.container_args} \
  ${local._container_image}

echo "[$(date)] Container started successfully"
docker ps
SCRIPT

  # Docker 모드면 자동 생성 스크립트, 아니면 사용자 지정 스크립트
  effective_startup_script = local.use_container ? local.docker_startup_script : var.startup_script
}

resource "google_compute_instance" "this" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  project      = var.project_id

  boot_disk {
    initialize_params {
      image = var.boot_disk_image
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

  guest_accelerator {
    type  = var.gpu_type
    count = var.gpu_count
  }

  service_account {
    email  = var.service_account_email
    scopes = var.service_account_scopes
  }

  metadata = merge(
    var.metadata,
    var.enable_oslogin ? { "enable-oslogin" = "TRUE" } : {}
  )

  tags = var.network_tags

  labels = local.use_container ? merge(var.labels, {
    "container-mode" = "docker-gpu"
  }) : var.labels

  deletion_protection = var.deletion_protection

  # GPU requires TERMINATE on host maintenance
  scheduling {
    preemptible                 = var.is_spot_instance
    automatic_restart           = var.is_spot_instance ? false : true
    on_host_maintenance         = "TERMINATE"
    provisioning_model          = var.is_spot_instance ? "SPOT" : "STANDARD"
    instance_termination_action = var.is_spot_instance ? "STOP" : null
  }

  metadata_startup_script = local.effective_startup_script

  lifecycle {
    ignore_changes = [boot_disk[0].initialize_params[0].image]
  }
}
