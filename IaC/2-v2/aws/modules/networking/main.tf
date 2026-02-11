# ==============================================
# 단일 VPC + Secondary CIDR 기반 환경 분리
# VPC는 기존 리소스를 data로 참조
# ==============================================

# 기존 VPC 참조
data "aws_vpc" "this" {
  id = var.vpc_id
}

# 기존 IGW 참조
data "aws_internet_gateway" "this" {
  filter {
    name   = "attachment.vpc-id"
    values = [var.vpc_id]
  }
}

# Secondary CIDR 추가 (필요 시)
resource "aws_vpc_ipv4_cidr_block_association" "this" {
  count = var.secondary_cidr != null ? 1 : 0

  vpc_id     = var.vpc_id
  cidr_block = var.secondary_cidr
}

# Public Subnets
resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                  = var.vpc_id
  cidr_block              = each.value.cidr
  availability_zone       = "${var.region}${each.value.az}"
  map_public_ip_on_launch = true

  depends_on = [aws_vpc_ipv4_cidr_block_association.this]

  tags = {
    Name = "${var.project_name}-${each.key}"
    Tier = "public"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id            = var.vpc_id
  cidr_block        = each.value.cidr
  availability_zone = "${var.region}${each.value.az}"

  depends_on = [aws_vpc_ipv4_cidr_block_association.this]

  tags = {
    Name = "${var.project_name}-${each.key}"
    Tier = "private"
  }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = var.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = data.aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-public-rtb"
  }
}

resource "aws_route_table_association" "public" {
  for_each = var.public_subnets

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

# NAT Instance (cost-efficient alternative to NAT Gateway)
data "aws_ami" "nat_instance" {
  count       = var.enable_nat ? 1 : 0
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

resource "aws_instance" "nat" {
  count = var.enable_nat ? 1 : 0

  ami                    = coalesce(var.nat_ami_id, data.aws_ami.nat_instance[0].id)
  instance_type          = var.nat_instance_type
  subnet_id              = values(aws_subnet.public)[0].id
  source_dest_check      = false
  vpc_security_group_ids = [aws_security_group.nat[0].id]

  tags = {
    Name = "${var.project_name}-nat-instance"
  }
}

resource "aws_security_group" "nat" {
  count = var.enable_nat ? 1 : 0

  name        = "${var.project_name}-nat-sg"
  description = "Security group for NAT instance"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.nat_ingress_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-nat-sg"
  }
}

resource "aws_eip" "nat" {
  count    = var.enable_nat ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.nat[0].id

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

# Private Route Table (through NAT Instance)
resource "aws_route_table" "private" {
  vpc_id = var.vpc_id

  tags = {
    Name = "${var.project_name}-private-rtb"
  }
}

resource "aws_route" "private_nat" {
  count = var.enable_nat ? 1 : 0

  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat[0].primary_network_interface_id
}

resource "aws_route_table_association" "private" {
  for_each = var.private_subnets

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private.id
}
