# ==============================================
# Compute Module
# Generic EC2 instances (MySQL, Redis, MQ, etc.)
# ==============================================

data "aws_ami" "ubuntu_arm64" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

resource "aws_instance" "this" {
  for_each = var.instances

  ami                    = coalesce(lookup(each.value, "ami", null), data.aws_ami.ubuntu_arm64.id)
  instance_type          = each.value.instance_type
  subnet_id              = each.value.subnet_id
  vpc_security_group_ids = each.value.security_group_ids
  iam_instance_profile   = lookup(each.value, "iam_instance_profile", null)
  user_data              = lookup(each.value, "user_data", null)

  root_block_device {
    volume_size = lookup(each.value, "volume_size", 20)
    volume_type = lookup(each.value, "volume_type", "gp3")

    tags = {
      Name = "${var.project_name}-${each.key}-volume"
    }
  }

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name = "${var.project_name}-${each.key}"
  }
}
