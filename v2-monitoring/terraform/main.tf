# ==============================================
# V2 Monitoring — Terraform (dev)
# EC2 + SG + EIP import & 관리
# ==============================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

# ==============================================
# Security Group
# ==============================================

resource "aws_security_group" "monitor" {
  name        = "${var.name_prefix}-monitor-sg"
  description = "V2 Monitoring Server SG"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-monitor-sg"
  }
}

# --- Ingress Rules ---

resource "aws_vpc_security_group_ingress_rule" "prometheus_vpc" {
  security_group_id = aws_security_group.monitor.id
  description       = "Prometheus-DevVPC"
  from_port         = 9090
  to_port           = 9090
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_ingress_rule" "prometheus_gcp" {
  count             = var.gcp_nat_ip != "" ? 1 : 0
  security_group_id = aws_security_group.monitor.id
  description       = "Prometheus-GCP"
  from_port         = 9090
  to_port           = 9090
  ip_protocol       = "tcp"
  cidr_ipv4         = var.gcp_nat_ip
}

resource "aws_vpc_security_group_ingress_rule" "loki_vpc" {
  security_group_id = aws_security_group.monitor.id
  description       = "Loki-DevVPC"
  from_port         = 3100
  to_port           = 3100
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_ingress_rule" "loki_gcp" {
  count             = var.gcp_nat_ip != "" ? 1 : 0
  security_group_id = aws_security_group.monitor.id
  description       = "Loki-GCP"
  from_port         = 3100
  to_port           = 3100
  ip_protocol       = "tcp"
  cidr_ipv4         = var.gcp_nat_ip
}

resource "aws_vpc_security_group_ingress_rule" "tempo_grpc_vpc" {
  security_group_id = aws_security_group.monitor.id
  description       = "Tempo-gRPC-DevVPC"
  from_port         = 4317
  to_port           = 4317
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_ingress_rule" "tempo_grpc_gcp" {
  count             = var.gcp_nat_ip != "" ? 1 : 0
  security_group_id = aws_security_group.monitor.id
  description       = "Tempo-gRPC-GCP"
  from_port         = 4317
  to_port           = 4317
  ip_protocol       = "tcp"
  cidr_ipv4         = var.gcp_nat_ip
}

resource "aws_vpc_security_group_ingress_rule" "tempo_http_vpc" {
  security_group_id = aws_security_group.monitor.id
  description       = "Tempo-HTTP-DevVPC"
  from_port         = 4318
  to_port           = 4318
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_ingress_rule" "tempo_http_gcp" {
  count             = var.gcp_nat_ip != "" ? 1 : 0
  security_group_id = aws_security_group.monitor.id
  description       = "Tempo-HTTP-GCP"
  from_port         = 4318
  to_port           = 4318
  ip_protocol       = "tcp"
  cidr_ipv4         = var.gcp_nat_ip
}

resource "aws_vpc_security_group_ingress_rule" "grafana_admin" {
  security_group_id = aws_security_group.monitor.id
  description       = "Grafana-Admin"
  from_port         = 3000
  to_port           = 3000
  ip_protocol       = "tcp"
  cidr_ipv4         = var.admin_ip
}

resource "aws_vpc_security_group_ingress_rule" "grafana_extra" {
  for_each          = toset(var.extra_admin_ips)
  security_group_id = aws_security_group.monitor.id
  description       = "Grafana-Extra"
  from_port         = 3000
  to_port           = 3000
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

# --- Egress ---

resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.monitor.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ==============================================
# EC2 Instance
# ==============================================

resource "aws_instance" "monitor" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.monitor.id]
  iam_instance_profile   = var.iam_instance_profile

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.name_prefix}-monitor"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# ==============================================
# EIP
# ==============================================

resource "aws_eip" "monitor" {
  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-monitor-eip"
  }
}

resource "aws_eip_association" "monitor" {
  allocation_id = aws_eip.monitor.id
  instance_id   = aws_instance.monitor.id
}
