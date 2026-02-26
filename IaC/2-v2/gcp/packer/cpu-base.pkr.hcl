source "googlecompute" "cpu-base" {
  project_id          = var.project_id
  source_image_family = "ubuntu-2204-lts"
  source_image_project_id = ["ubuntu-os-cloud"]
  zone                = var.zone
  machine_type        = "e2-medium"
  image_name          = "dojangkok-cpu-base-{{timestamp}}"
  image_family        = "dojangkok-cpu-base"
  image_description   = "DojangKok CPU base image - Docker CE + compose-plugin"
  ssh_username        = "packer"
  disk_size           = 50
  disk_type           = "pd-ssd"

  # IAP 터널을 통한 SSH (외부 SSH 방화벽 불필요)
  use_iap             = true
}

build {
  sources = ["source.googlecompute.cpu-base"]

  provisioner "shell" {
    script = "scripts/install-docker.sh"
  }
}
