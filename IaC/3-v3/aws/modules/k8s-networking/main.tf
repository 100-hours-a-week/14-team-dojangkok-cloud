# ============================================================
# V3 K8S IaC — Networking (기존 VPC에 K8S 서브넷 추가)
# 기존 V2 dev VPC(10.0.0.0/18)에 kubeadm K8S 클러스터 구성
# Branch: feat/v3-k8s-iac
# ============================================================

# --- Subnets ---

resource "aws_subnet" "subnets" {
  for_each = var.subnets

  vpc_id            = var.vpc_id
  cidr_block        = each.value.cidr
  availability_zone = "${var.region}${each.value.az}"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${each.key}"
    Tier = each.value.tier
  })
}

# --- Route Tables ---

# Public route table (shared, routes to IGW)
resource "aws_route_table" "public" {
  count  = length([for k, v in var.subnets : k if v.tier == "public"]) > 0 ? 1 : 0
  vpc_id = var.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = var.igw_id
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-k8s-public-rt"
  })
}

# Private route tables (per-AZ, NAT routes added externally)
resource "aws_route_table" "private" {
  for_each = toset(var.availability_zones)
  vpc_id   = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-k8s-private-rt-${each.key}"
  })
}

# --- Route Table Associations ---

resource "aws_route_table_association" "public" {
  for_each = { for k, v in var.subnets : k => v if v.tier == "public" }

  subnet_id      = aws_subnet.subnets[each.key].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table_association" "private" {
  for_each = { for k, v in var.subnets : k => v if v.tier == "private" }

  subnet_id      = aws_subnet.subnets[each.key].id
  route_table_id = aws_route_table.private[each.value.az].id
}
