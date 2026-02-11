source "googlecompute" "gpu-base" {
  project_id          = var.project_id
  source_image_family = "ubuntu-accelerator-2204-amd64-with-nvidia-580"
  source_image_project_id = ["ubuntu-os-accelerator-images"]
  zone                = var.zone
  machine_type        = "g2-standard-4"
  image_name          = "dojangkok-gpu-base-{{timestamp}}"
  image_family        = "dojangkok-gpu-base"
  image_description   = "DojangKok GPU base image - Docker CE + compose-plugin + NVIDIA Container Toolkit"
  ssh_username        = "packer"
  disk_size           = 200
  disk_type           = "pd-ssd"

  accelerator_type    = "projects/${var.project_id}/zones/${var.zone}/acceleratorTypes/nvidia-l4"
  accelerator_count   = 1
  on_host_maintenance = "TERMINATE"
}

build {
  sources = ["source.googlecompute.gpu-base"]

  provisioner "shell" {
    script = "scripts/install-nvidia-docker.sh"
  }
}
