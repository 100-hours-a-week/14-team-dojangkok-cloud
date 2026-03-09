# ============================================================
# V3 K8S IaC — k8s-dev 환경 메인 구성
# 기존 V2 dev VPC(10.0.0.0/18, vpc-08b809f7d33f0f9b1)에
# kubeadm K8S 클러스터(CP 1 + Worker 3~6) 구성
# Branch: feat/v3-k8s-iac
# ============================================================

locals {
  common_tags = {
    Project     = "dojangkok"
    Environment = "k8s-dev"
    ManagedBy   = "terraform"
  }

  # K8S 서브넷 (기존 VPC 여유 공간 활용)
  k8s_subnets = {
    "public-2b" = { cidr = "10.0.1.0/24", az = "b", tier = "public" }
    "k8s-2a"    = { cidr = "10.0.32.0/22", az = "a", tier = "private" }
    "k8s-2b"    = { cidr = "10.0.36.0/22", az = "b", tier = "private" }
    "k8s-2c"    = { cidr = "10.0.40.0/22", az = "c", tier = "private" }
  }

  availability_zones = ["a", "b", "c"]
}

# --- Data Sources: 기존 인프라 참조 ---

data "aws_vpc" "existing" {
  id = var.vpc_id
}

data "aws_internet_gateway" "existing" {
  filter {
    name   = "attachment.vpc-id"
    values = [var.vpc_id]
  }
}

# 기존 V2 public 서브넷 (NAT Instance + ALB 배치용)
data "aws_subnet" "existing_public_2a" {
  filter {
    name   = "tag:Name"
    values = ["dev-dojangkok-v2-public-2a"]
  }
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

data "aws_subnet" "existing_public_2c" {
  filter {
    name   = "tag:Name"
    values = ["dev-dojangkok-v2-public-2c"]
  }
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

# ============================================================
# 1. Networking — K8S 서브넷 추가
# ============================================================

module "k8s_networking" {
  source = "../../modules/k8s-networking"

  project_name       = var.project_name
  vpc_id             = var.vpc_id
  igw_id             = data.aws_internet_gateway.existing.id
  subnets            = local.k8s_subnets
  availability_zones = local.availability_zones
  common_tags        = local.common_tags
}

# ============================================================
# 2. Security Groups — K8S 전용
# ============================================================

module "security_groups" {
  source = "../../modules/security-groups"

  project_name = var.project_name
  vpc_id       = var.vpc_id
  common_tags  = local.common_tags

  security_groups = {
    "alb" = {
      description = "K8S ALB"
      ingress_rules = [
        { from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTP" },
        { from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTPS" },
      ]
    }

    "k8s-cp" = {
      description = "K8S Control Plane"
      ingress_rules = [
        { from_port = 6443, to_port = 6443, protocol = "tcp", cidr_blocks = [var.vpc_cidr], description = "kube-apiserver" },
        { from_port = 2379, to_port = 2380, protocol = "tcp", cidr_blocks = [var.vpc_cidr], description = "etcd" },
        { from_port = 10250, to_port = 10250, protocol = "tcp", cidr_blocks = [var.vpc_cidr], description = "kubelet" },
        { from_port = 10257, to_port = 10257, protocol = "tcp", cidr_blocks = [var.vpc_cidr], description = "kube-controller-manager" },
        { from_port = 10259, to_port = 10259, protocol = "tcp", cidr_blocks = [var.vpc_cidr], description = "kube-scheduler" },
        { from_port = 4789, to_port = 4789, protocol = "udp", cidr_blocks = [var.vpc_cidr], description = "Calico VXLAN" },
        { from_port = 5473, to_port = 5473, protocol = "tcp", cidr_blocks = [var.vpc_cidr], description = "Calico Typha" },
      ]
    }

    "k8s-worker" = {
      description = "K8S Worker Nodes"
      ingress_rules = [
        { from_port = 10250, to_port = 10250, protocol = "tcp", cidr_blocks = [var.vpc_cidr], description = "kubelet" },
        { from_port = 4789, to_port = 4789, protocol = "udp", cidr_blocks = [var.vpc_cidr], description = "Calico VXLAN" },
        { from_port = 5473, to_port = 5473, protocol = "tcp", cidr_blocks = [var.vpc_cidr], description = "Calico Typha" },
        { from_port = 30000, to_port = 32767, protocol = "tcp", cidr_blocks = [var.vpc_cidr], description = "NodePort range" },
      ]
    }
  }
}

# ALB -> Worker NodePort 허용 (SG-to-SG 규칙)
resource "aws_security_group_rule" "alb_to_worker_nodeport" {
  type                     = "ingress"
  from_port                = var.gateway_nodeport
  to_port                  = var.gateway_nodeport
  protocol                 = "tcp"
  source_security_group_id = module.security_groups.security_group_ids["alb"]
  security_group_id        = module.security_groups.security_group_ids["k8s-worker"]
  description              = "ALB to Worker Gateway NodePort"
}

# ============================================================
# 3. IAM — K8S 노드 역할
# ============================================================

module "iam" {
  source = "../../modules/iam"

  project_name = var.project_name
  common_tags  = local.common_tags
}

# ============================================================
# 4. NAT Instance — ASG 래핑, 단일 NAT (dev 비용 최적화)
# 설계 원안: AZ별 NAT x3, dev 운영 노트에 따라 1대로 운영
# ============================================================

module "nat_instance" {
  source = "../../modules/nat-instance"

  project_name = var.project_name
  vpc_id       = var.vpc_id
  vpc_cidr     = var.vpc_cidr
  common_tags  = local.common_tags

  public_subnet_ids = concat(
    [data.aws_subnet.existing_public_2a.id, data.aws_subnet.existing_public_2c.id],
    [module.k8s_networking.subnet_ids["public-2b"]]
  )

  route_table_ids = [
    module.k8s_networking.private_route_table_ids["a"],
    module.k8s_networking.private_route_table_ids["b"],
    module.k8s_networking.private_route_table_ids["c"],
  ]
}

# ============================================================
# 5. K8S Nodes — CP 1 + Worker (workers_per_az x 3 AZ)
# ============================================================

module "k8s_nodes" {
  source = "../../modules/k8s-nodes"

  project_name         = var.project_name
  cluster_name         = var.cluster_name
  cp_instance_type     = var.cp_instance_type
  worker_instance_type = var.worker_instance_type
  workers_per_az       = var.workers_per_az
  iam_instance_profile = module.iam.instance_profile_name
  common_tags          = local.common_tags

  cp_subnet_id          = module.k8s_networking.subnet_ids["k8s-2a"]
  cp_security_group_ids = [module.security_groups.security_group_ids["k8s-cp"]]

  worker_az_subnets = {
    "a" = module.k8s_networking.subnet_ids["k8s-2a"]
    "b" = module.k8s_networking.subnet_ids["k8s-2b"]
    "c" = module.k8s_networking.subnet_ids["k8s-2c"]
  }
  worker_security_group_ids = [module.security_groups.security_group_ids["k8s-worker"]]
}

# ============================================================
# 6. ALB — 단일 TG, Gateway Fabric NodePort
# ============================================================

module "alb" {
  source = "../../modules/alb"

  project_name        = var.project_name
  vpc_id              = var.vpc_id
  gateway_nodeport    = var.gateway_nodeport
  ssl_certificate_arn = var.ssl_certificate_arn
  worker_instances    = { for k, v in module.k8s_nodes.workers : k => v.id }
  common_tags         = local.common_tags

  subnet_ids = concat(
    [data.aws_subnet.existing_public_2a.id, data.aws_subnet.existing_public_2c.id],
    [module.k8s_networking.subnet_ids["public-2b"]]
  )

  security_group_ids = [module.security_groups.security_group_ids["alb"]]
}
