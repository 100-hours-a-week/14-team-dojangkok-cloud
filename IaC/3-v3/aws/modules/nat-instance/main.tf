# ============================================================
# V3 K8S IaC — NAT Instance (ASG 래핑, dev: 1대 / prod: AZ별)
# ASG Min=Max=1 + user_data에서 RT route 갱신
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

# --- Security Group ---

resource "aws_security_group" "nat" {
  name        = "${var.project_name}-nat-sg"
  description = "NAT Instance SG"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
    description = "All from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-nat-sg"
  })
}

# --- IAM Role (NAT 전용: SSM + Route 권한) ---

resource "aws_iam_role" "nat" {
  name = "${var.project_name}-nat-role"

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

  tags = var.common_tags
}

resource "aws_iam_instance_profile" "nat" {
  name = "${var.project_name}-nat-profile"
  role = aws_iam_role.nat.name
}

resource "aws_iam_role_policy_attachment" "nat_ssm" {
  role       = aws_iam_role.nat.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "nat_self_heal" {
  name = "nat-self-heal"
  role = aws_iam_role.nat.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:ModifyInstanceAttribute",
          "ec2:ReplaceRoute",
          "ec2:CreateRoute"
        ]
        Resource = "*"
      }
    ]
  })
}

# --- Launch Template ---

resource "aws_launch_template" "nat" {
  name_prefix   = "${var.project_name}-nat-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.nat.id]
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.nat.name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 8
      volume_type = "gp3"
      encrypted   = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    vpc_cidr        = var.vpc_cidr
    route_table_ids = join(",", var.route_table_ids)
    region          = var.region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.common_tags, {
      Name = "${var.project_name}-nat"
    })
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [image_id]
  }
}

# --- Auto Scaling Group (Min=Max=1, multi-AZ) ---

resource "aws_autoscaling_group" "nat" {
  name                = "${var.project_name}-nat-asg"
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = var.public_subnet_ids

  launch_template {
    id      = aws_launch_template.nat.id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 120

  tag {
    key                 = "Name"
    value               = "${var.project_name}-nat"
    propagate_at_launch = false
  }

  lifecycle {
    create_before_destroy = true
  }
}
