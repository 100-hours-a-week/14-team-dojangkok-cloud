# ============================================================
# V3 K8S IaC — K8S Nodes (CP + Worker EC2 인스턴스)
# workers_per_az 변수로 AZ당 워커 수 조절 (초기 1, prod 목표 2)
# Branch: feat/v3-k8s-iac
# ============================================================

# --- AMI: Ubuntu 24.04 LTS ARM64 ---

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

# --- Control Plane ---

resource "aws_instance" "control_plane" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.cp_instance_type
  subnet_id              = var.cp_subnet_id
  vpc_security_group_ids = var.cp_security_group_ids
  iam_instance_profile   = var.iam_instance_profile
  source_dest_check      = false
  user_data              = local.ssm_user_data

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = var.cp_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.common_tags, {
    Name               = "${var.project_name}-cp"
    "k8s:cluster-name" = var.cluster_name
    "k8s:role"         = "control-plane"
    "k8s:nodepool"     = "system"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}

# --- Worker Nodes ---

locals {
  ssm_user_data = <<-EOF
    #!/bin/bash
    mkdir -p /tmp/ssm && cd /tmp/ssm
    curl -fsSL "https://s3.amazonaws.com/ec2-downloads-ssm/latest/debian_arm64/amazon-ssm-agent.deb" -o amazon-ssm-agent.deb
    dpkg -i amazon-ssm-agent.deb
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
  EOF

  # workers_per_az × 3 AZ → 플랫 맵 생성
  # e.g. workers_per_az=1 → { "w-2a-1"={az="a",...}, "w-2b-1"={...}, "w-2c-1"={...} }
  # e.g. workers_per_az=2 → { "w-2a-1"={...}, "w-2a-2"={...}, "w-2b-1"={...}, ... }
  worker_instances = merge([
    for az, subnet_id in var.worker_az_subnets : {
      for i in range(1, var.workers_per_az + 1) :
      "w-2${az}-${i}" => {
        az        = az
        subnet_id = subnet_id
        index     = i
      }
    }
  ]...)
}

resource "aws_instance" "workers" {
  for_each = local.worker_instances

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  subnet_id              = each.value.subnet_id
  vpc_security_group_ids = var.worker_security_group_ids
  iam_instance_profile   = var.iam_instance_profile
  source_dest_check      = false
  user_data              = local.ssm_user_data

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = var.worker_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  tags = merge(var.common_tags, {
    Name               = "${var.project_name}-${each.key}"
    "k8s:cluster-name" = var.cluster_name
    "k8s:role"         = "worker"
    "k8s:nodepool"     = "default"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}
