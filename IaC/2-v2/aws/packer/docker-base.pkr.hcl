packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "instance_type" {
  type    = string
  default = "t4g.small"
}

variable "ami_name_prefix" {
  type    = string
  default = "dojangkok-docker-base"
}

source "amazon-ebs" "ubuntu-arm64" {
  ami_name      = "${var.ami_name_prefix}-{{timestamp}}"
  instance_type = var.instance_type
  region        = var.region

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"] # Canonical
  }

  ssh_username = "ubuntu"

  tags = {
    Name       = "${var.ami_name_prefix}-{{timestamp}}"
    Base_AMI   = "{{ .SourceAMI }}"
    Build_Date = "{{timestamp}}"
    Managed_By = "packer"
  }
}

build {
  sources = ["source.amazon-ebs.ubuntu-arm64"]

  provisioner "shell" {
    script = "${path.root}/scripts/setup-docker.sh"
  }
}
