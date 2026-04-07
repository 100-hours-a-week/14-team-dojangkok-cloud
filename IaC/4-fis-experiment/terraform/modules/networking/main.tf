# Secondary CIDR + 3 public subnets (임시 실험용, NAT 없음)

resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  vpc_id     = var.vpc_id
  cidr_block = var.secondary_cidr
}

resource "aws_subnet" "k8s" {
  for_each = var.subnets

  vpc_id                  = var.vpc_id
  cidr_block              = each.value.cidr
  availability_zone       = "${var.region}${each.value.az}"
  map_public_ip_on_launch = true

  depends_on = [aws_vpc_ipv4_cidr_block_association.secondary]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${each.key}"
  })
}

resource "aws_route_table" "k8s" {
  vpc_id = var.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = var.igw_id
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-k8s-rt"
  })
}

resource "aws_route_table_association" "k8s" {
  for_each = aws_subnet.k8s

  subnet_id      = each.value.id
  route_table_id = aws_route_table.k8s.id
}
