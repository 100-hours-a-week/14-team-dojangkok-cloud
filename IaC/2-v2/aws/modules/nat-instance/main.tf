# ==============================================
# NAT Instance Module (per-AZ)
# Cost-efficient alternative to NAT Gateway
# ==============================================
#
# ⚠️ WARNING: AMI가 AL2023 → Ubuntu 24.04로 변경됨.
# 기존 prod NAT 인스턴스(AL2023)에 적용하려면 인스턴스 교체(taint/replace) 필요.
# lifecycle { ignore_changes = [ami] } 때문에 기존 인스턴스는 자동 변경되지 않음.
# 교체 시 EIP 재할당 + 라우팅 일시 중단 발생하므로 점검 시간에 진행할 것.
# ==============================================

# Ubuntu 24.04 Noble ARM64 AMI (dev/prod 통일)
data "aws_ami" "ubuntu_arm64" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-20251212"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# NAT Instance per AZ
resource "aws_instance" "nat" {
  for_each = var.nat_instances

  ami                    = data.aws_ami.ubuntu_arm64.id
  instance_type          = var.instance_type
  subnet_id              = each.value.subnet_id
  source_dest_check      = false
  vpc_security_group_ids = [aws_security_group.nat.id]
  iam_instance_profile   = var.iam_instance_profile

  # Ubuntu 24.04 기준 user_data (AL2023의 yum → apt 변경)
  user_data = <<-EOF
    #!/bin/bash
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y iptables-persistent
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/custom-ip-forward.conf
    sysctl -p /etc/sysctl.d/custom-ip-forward.conf
    /sbin/iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE
    /sbin/iptables -F FORWARD
    netfilter-persistent save
  EOF

  tags = {
    Name = "${var.project_name}-nat-${each.key}"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

# EIP per NAT Instance
resource "aws_eip" "nat" {
  for_each = var.nat_instances

  domain   = "vpc"
  instance = aws_instance.nat[each.key].id

  tags = {
    Name = "${var.project_name}-nat-${each.key}-eip"
  }
}

# Shared Security Group for NAT Instances
resource "aws_security_group" "nat" {
  name        = "${var.project_name}-nat-instance-sg"
  description = "Security group for NAT instances"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
    description = "All traffic from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-nat-instance-sg"
  }
}

# Route for private subnets through NAT Instance
resource "aws_route" "nat" {
  for_each = var.nat_instances

  route_table_id         = each.value.route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat[each.key].primary_network_interface_id
}
