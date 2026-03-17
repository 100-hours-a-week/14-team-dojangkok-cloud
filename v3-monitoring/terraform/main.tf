# ==============================================
# V3 Monitoring — Terraform
# EC2 + SG + EIP + S3 Bucket + IAM
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
# S3 Bucket (Monitoring Data Storage)
# ==============================================

resource "aws_s3_bucket" "monitoring" {
  bucket = var.s3_monitoring_bucket

  tags = {
    Name = var.s3_monitoring_bucket
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "monitoring" {
  bucket = aws_s3_bucket.monitoring.id

  rule {
    id     = "loki-lifecycle"
    status = "Enabled"

    filter {
      prefix = "loki/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }
  }

  rule {
    id     = "tempo-lifecycle"
    status = "Enabled"

    filter {
      prefix = "tempo/"
    }

    expiration {
      days = 30
    }
  }

  rule {
    id     = "prometheus-lifecycle"
    status = "Enabled"

    filter {
      prefix = "prometheus/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_public_access_block" "monitoring" {
  bucket = aws_s3_bucket.monitoring.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ==============================================
# IAM Role + Instance Profile
# ==============================================

resource "aws_iam_role" "monitor" {
  name = "${var.name_prefix}-monitor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.name_prefix}-monitor-role"
  }
}

resource "aws_iam_role_policy" "monitoring_s3" {
  name = "${var.name_prefix}-monitoring-s3"
  role = aws_iam_role.monitor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.monitoring.arn,
        "${aws_s3_bucket.monitoring.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.monitor.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "monitor" {
  name = "${var.name_prefix}-monitor-profile"
  role = aws_iam_role.monitor.name
}

# ==============================================
# Security Group
# ==============================================

resource "aws_security_group" "monitor" {
  name        = "${var.name_prefix}-monitor-sg"
  description = "V3 Monitoring Server SG"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-monitor-sg"
  }
}

# --- Prometheus :9090 ---

resource "aws_vpc_security_group_ingress_rule" "prometheus_vpc" {
  security_group_id = aws_security_group.monitor.id
  description       = "Prometheus-VPC"
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

resource "aws_vpc_security_group_ingress_rule" "prometheus_k8s" {
  for_each          = toset(var.k8s_nat_ips)
  security_group_id = aws_security_group.monitor.id
  description       = "Prometheus-K8S"
  from_port         = 9090
  to_port           = 9090
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

# --- Loki :3100 ---

resource "aws_vpc_security_group_ingress_rule" "loki_vpc" {
  security_group_id = aws_security_group.monitor.id
  description       = "Loki-VPC"
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

resource "aws_vpc_security_group_ingress_rule" "loki_k8s" {
  for_each          = toset(var.k8s_nat_ips)
  security_group_id = aws_security_group.monitor.id
  description       = "Loki-K8S"
  from_port         = 3100
  to_port           = 3100
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

# --- Tempo gRPC :4317 ---

resource "aws_vpc_security_group_ingress_rule" "tempo_grpc_vpc" {
  security_group_id = aws_security_group.monitor.id
  description       = "Tempo-gRPC-VPC"
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

resource "aws_vpc_security_group_ingress_rule" "tempo_grpc_k8s" {
  for_each          = toset(var.k8s_nat_ips)
  security_group_id = aws_security_group.monitor.id
  description       = "Tempo-gRPC-K8S"
  from_port         = 4317
  to_port           = 4317
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

# --- Tempo HTTP :4318 ---

resource "aws_vpc_security_group_ingress_rule" "tempo_http_vpc" {
  security_group_id = aws_security_group.monitor.id
  description       = "Tempo-HTTP-VPC"
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

resource "aws_vpc_security_group_ingress_rule" "tempo_http_k8s" {
  for_each          = toset(var.k8s_nat_ips)
  security_group_id = aws_security_group.monitor.id
  description       = "Tempo-HTTP-K8S"
  from_port         = 4318
  to_port           = 4318
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

# --- Grafana :3000 (Admin only) ---

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
  iam_instance_profile   = aws_iam_instance_profile.monitor.name

  root_block_device {
    volume_size = var.volume_size
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
# EIP (v2 이슈 해결: 재시작 시 IP 변경 방지)
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
