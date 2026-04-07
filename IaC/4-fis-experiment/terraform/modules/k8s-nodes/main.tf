# 1 CP + 3 Worker (SSH 접속, public subnet, SSM 없음)

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

# --- Control Plane ---

resource "aws_instance" "control_plane" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.cp_subnet_id
  vpc_security_group_ids = var.cp_security_group_ids
  iam_instance_profile   = var.iam_instance_profile
  key_name               = var.key_pair_name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.common_tags, {
    Name               = "${var.project_name}-cp"
    "k8s:cluster-name" = var.cluster_name
    "k8s:role"         = "control-plane"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}

# --- Workers ---

locals {
  worker_instances = {
    for az, subnet_id in var.worker_az_subnets :
    "w-2${az}-1" => {
      az        = az
      subnet_id = subnet_id
    }
  }
}

resource "aws_instance" "workers" {
  for_each = local.worker_instances

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = each.value.subnet_id
  vpc_security_group_ids = var.worker_security_group_ids
  iam_instance_profile   = var.iam_instance_profile
  key_name               = var.key_pair_name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.common_tags, {
    Name               = "${var.project_name}-${each.key}"
    "k8s:cluster-name" = var.cluster_name
    "k8s:role"         = "worker"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}
