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
    "k8s-2a"    = { cidr = "10.0.48.0/24", az = "a", tier = "private" }
    "k8s-2b"    = { cidr = "10.0.49.0/24", az = "b", tier = "private" }
    "k8s-2c"    = { cidr = "10.0.50.0/24", az = "c", tier = "private" }
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
# 2-1. 서비스 SG 브릿지 — Worker → 기존 V2 서비스 접근 허용
# destroy 시 이 룰이 먼저 삭제되어 SG DependencyViolation 방지
# ============================================================

data "aws_security_group" "mysql_nlb" {
  filter {
    name   = "group-name"
    values = ["dev-dojangkok-v2-mysql-cluster-nlb-sg"]
  }
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

data "aws_security_group" "redis" {
  filter {
    name   = "group-name"
    values = ["dev-dojangkok-v2-redis-sg"]
  }
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

data "aws_security_group" "redis_sentinel" {
  filter {
    name   = "group-name"
    values = ["dev-dojangkok-v2-redis-sentinel-sg"]
  }
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

data "aws_security_group" "mongodb" {
  filter {
    name   = "group-name"
    values = ["dev-dojangkok-v2-mongodb-sg"]
  }
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

data "aws_security_group" "mq_nlb" {
  filter {
    name   = "group-name"
    values = ["dev-dojangkok-v2-mq-cluster-nlb-sg"]
  }
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

# Worker → MySQL NLB (3306)
resource "aws_security_group_rule" "mysql_nlb_from_worker" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = module.security_groups.security_group_ids["k8s-worker"]
  security_group_id        = data.aws_security_group.mysql_nlb.id
  description              = "K8S Worker to MySQL NLB"
}

# Worker → Redis Master (6379)
resource "aws_security_group_rule" "redis_from_worker" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = module.security_groups.security_group_ids["k8s-worker"]
  security_group_id        = data.aws_security_group.redis.id
  description              = "K8S Worker to Redis Master"
}

# Worker → Redis Sentinel (26379)
resource "aws_security_group_rule" "redis_sentinel_from_worker" {
  type                     = "ingress"
  from_port                = 26379
  to_port                  = 26379
  protocol                 = "tcp"
  source_security_group_id = module.security_groups.security_group_ids["k8s-worker"]
  security_group_id        = data.aws_security_group.redis_sentinel.id
  description              = "K8S Worker to Redis Sentinel"
}

# Worker → MongoDB (27017)
resource "aws_security_group_rule" "mongodb_from_worker" {
  type                     = "ingress"
  from_port                = 27017
  to_port                  = 27017
  protocol                 = "tcp"
  source_security_group_id = module.security_groups.security_group_ids["k8s-worker"]
  security_group_id        = data.aws_security_group.mongodb.id
  description              = "K8S Worker to MongoDB"
}

# Worker → RabbitMQ NLB (5672)
resource "aws_security_group_rule" "mq_nlb_from_worker" {
  type                     = "ingress"
  from_port                = 5672
  to_port                  = 5672
  protocol                 = "tcp"
  source_security_group_id = module.security_groups.security_group_ids["k8s-worker"]
  security_group_id        = data.aws_security_group.mq_nlb.id
  description              = "K8S Worker to RabbitMQ NLB"
}

# ============================================================
# 3. IAM — K8S 노드 역할
# ============================================================

data "aws_caller_identity" "current" {}

module "iam" {
  source = "../../modules/iam"

  project_name   = var.project_name
  aws_region     = var.region
  aws_account_id = data.aws_caller_identity.current.account_id
  common_tags    = local.common_tags
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

  # NOTE: 2b 일시 제외 — t4g.nano capacity 부족 (2026-03-17)
  public_subnet_ids = [data.aws_subnet.existing_public_2a.id, data.aws_subnet.existing_public_2c.id]

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

# ============================================================
# 7. S3 — etcd 스냅샷 백업 버킷
# ============================================================

resource "aws_s3_bucket" "etcd_backup" {
  bucket = "dojangkok-v3-etcd-backup"
  tags   = merge(local.common_tags, { Name = "dojangkok-v3-etcd-backup" })
}

resource "aws_s3_bucket_lifecycle_configuration" "etcd_backup" {
  bucket = aws_s3_bucket.etcd_backup.id

  rule {
    id     = "expire-old-snapshots"
    status = "Enabled"

    filter {
      prefix = "snapshots/"
    }

    expiration {
      days = 7
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "etcd_backup" {
  bucket = aws_s3_bucket.etcd_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "etcd_backup" {
  bucket = aws_s3_bucket.etcd_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
