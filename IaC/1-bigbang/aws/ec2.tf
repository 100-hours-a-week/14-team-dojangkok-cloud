data "aws_ami" "ubuntu" {
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

resource "aws_instance" "main" {
  ami                  = "ami-0c4788c2191655daa"
  instance_type        = "t4g.large"
  subnet_id            = aws_subnet.public.id

  lifecycle {
    ignore_changes = [ami]
  }
  
  iam_instance_profile = aws_iam_instance_profile.s3_access.name
  vpc_security_group_ids = [aws_security_group.bigbang.id]
  key_name = "${var.project_name}-kp"
  root_block_device {
    volume_size = 100
    volume_type = "gp3"
    tags = {
      Name = "${var.project_name}-single-instance-volume"
    }
  }

  tags = {
    Name = "ktb-team14-dojangkok" 
  }
}

resource "aws_eip" "main" {
  domain   = "vpc"
  instance = aws_instance.main.id

  tags = {
    Name = "${var.project_name}-single-instance"
  }
}
