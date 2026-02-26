# ==============================================
# ASG Module
# Launch Template + Auto Scaling Group
# (FE/BE with CodeDeploy Blue/Green)
# ==============================================

data "aws_ami" "ubuntu_arm64" {
  count       = var.ami_id == "" ? 1 : 0
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

resource "aws_launch_template" "this" {
  name          = "${var.project_name}-${var.name}-template"
  image_id      = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu_arm64[0].id
  instance_type = var.instance_type

  iam_instance_profile {
    name = var.iam_instance_profile
  }

  vpc_security_group_ids = var.security_group_ids

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = var.volume_size
      volume_type = "gp3"
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-${var.name}"
    }
  }

  lifecycle {
    ignore_changes = [image_id]
  }

  tags = {
    Name = "${var.project_name}-${var.name}-template"
  }
}

resource "aws_autoscaling_group" "this" {
  name                      = "${var.project_name}-${var.name}-asg"
  min_size                  = var.min_size
  max_size                  = var.max_size
  desired_capacity          = var.desired_capacity
  health_check_type         = "ELB"
  health_check_grace_period = 300
  vpc_zone_identifier       = var.subnet_ids
  target_group_arns         = var.target_group_arns

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Default"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.name}"
    propagate_at_launch = true
  }
}
