# ==============================================
# NAT Instance Module (per-AZ)
# Cost-efficient alternative to NAT Gateway
# ==============================================

# Amazon Linux 2023 ARM64 AMI
data "aws_ami" "al2023_arm64" {
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["137112412989"] # Amazon
}

# NAT Instance per AZ
resource "aws_instance" "nat" {
  for_each = var.nat_instances

  ami                    = data.aws_ami.al2023_arm64.id
  instance_type          = var.instance_type
  subnet_id              = each.value.subnet_id
  source_dest_check      = false
  vpc_security_group_ids = [aws_security_group.nat.id]
  iam_instance_profile   = var.iam_instance_profile

  user_data = <<-EOF
    #!/bin/bash
    yum install -y iptables-services
    systemctl enable iptables
    systemctl start iptables
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/custom-ip-forward.conf
    sysctl -p /etc/sysctl.d/custom-ip-forward.conf
    /sbin/iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE
    /sbin/iptables -F FORWARD
    service iptables save
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
