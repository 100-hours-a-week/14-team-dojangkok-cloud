# =============================================================================
# FIS 실험 환경 — 메인 오케스트레이션
# 기존 V4 VPC(10.0.0.0/24)에 Secondary CIDR 추가, K8S 클러스터 구축
# =============================================================================

# --- Networking ---

module "networking" {
  source = "./modules/networking"

  project_name   = var.project_name
  region         = var.region
  vpc_id         = var.vpc_id
  igw_id         = var.igw_id
  secondary_cidr = var.secondary_cidr

  subnets = {
    k8s-2a = { cidr = "10.1.1.0/24", az = "a" }
    k8s-2b = { cidr = "10.1.2.0/24", az = "b" }
    k8s-2c = { cidr = "10.1.3.0/24", az = "c" }
  }

  common_tags = local.common_tags
}

# --- Security Groups ---

module "security_groups" {
  source = "./modules/security-groups"

  project_name           = var.project_name
  vpc_id                 = var.vpc_id
  secondary_cidr         = var.secondary_cidr
  data_security_group_id = var.data_security_group_id
  common_tags            = local.common_tags

  security_groups = {
    k8s-alb = {
      description = "FIS experiment ALB"
      ingress_rules = [
        { from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTP" },
      ]
    }

    k8s-cp = {
      description = "FIS experiment K8S Control Plane"
      ingress_rules = [
        { from_port = 6443,  to_port = 6443,  protocol = "tcp", cidr_blocks = local.vpc_internal_cidrs, description = "kube-apiserver" },
        { from_port = 2379,  to_port = 2380,  protocol = "tcp", cidr_blocks = local.vpc_internal_cidrs, description = "etcd" },
        { from_port = 10250, to_port = 10250, protocol = "tcp", cidr_blocks = local.vpc_internal_cidrs, description = "kubelet" },
        { from_port = 10257, to_port = 10257, protocol = "tcp", cidr_blocks = local.vpc_internal_cidrs, description = "kube-controller-manager" },
        { from_port = 10259, to_port = 10259, protocol = "tcp", cidr_blocks = local.vpc_internal_cidrs, description = "kube-scheduler" },
        { from_port = 4789,  to_port = 4789,  protocol = "udp", cidr_blocks = local.vpc_internal_cidrs, description = "Calico VXLAN" },
        { from_port = 5473,  to_port = 5473,  protocol = "tcp", cidr_blocks = local.vpc_internal_cidrs, description = "Calico Typha" },
        { from_port = 22,    to_port = 22,    protocol = "tcp", cidr_blocks = [var.ssh_allowed_cidr],    description = "SSH" },
      ]
    }

    k8s-worker = {
      description = "FIS experiment K8S Worker"
      ingress_rules = [
        { from_port = 10250, to_port = 10250, protocol = "tcp", cidr_blocks = local.vpc_internal_cidrs, description = "kubelet" },
        { from_port = 4789,  to_port = 4789,  protocol = "udp", cidr_blocks = local.vpc_internal_cidrs, description = "Calico VXLAN" },
        { from_port = 5473,  to_port = 5473,  protocol = "tcp", cidr_blocks = local.vpc_internal_cidrs, description = "Calico Typha" },
        { from_port = 22,    to_port = 22,    protocol = "tcp", cidr_blocks = [var.ssh_allowed_cidr],    description = "SSH" },
        # ALB → NodePort: SG-to-SG 룰은 아래에서 별도 추가
      ]
    }
  }
}

# ALB SG → Worker NodePort (SG-to-SG 룰)
resource "aws_security_group_rule" "alb_to_worker_nodeport" {
  type                     = "ingress"
  from_port                = var.gateway_nodeport
  to_port                  = var.gateway_nodeport
  protocol                 = "tcp"
  source_security_group_id = module.security_groups.sg_ids["k8s-alb"]
  description              = "ALB to NGF NodePort"
  security_group_id        = module.security_groups.sg_ids["k8s-worker"]
}

# --- S3 (etcd backup) ---

resource "aws_s3_bucket" "etcd_backup" {
  bucket = "fis-exp-etcd-backup"
  tags   = local.common_tags
}

resource "aws_s3_bucket" "ansible_ssm" {
  bucket = "fis-exp-ansible-ssm"
  tags   = local.common_tags
}

resource "aws_s3_bucket_lifecycle_configuration" "etcd_backup" {
  bucket = aws_s3_bucket.etcd_backup.id

  rule {
    id     = "expire-7d"
    status = "Enabled"
    expiration {
      days = 7
    }
  }
}

# --- IAM ---

module "iam" {
  source = "./modules/iam"

  project_name       = var.project_name
  etcd_backup_bucket = aws_s3_bucket.etcd_backup.id
  ansible_ssm_bucket = aws_s3_bucket.ansible_ssm.id
  common_tags        = local.common_tags
}

# --- K8S Nodes ---

module "k8s_nodes" {
  source = "./modules/k8s-nodes"

  project_name  = var.project_name
  cluster_name  = var.cluster_name
  instance_type = var.instance_type
  key_pair_name = var.key_pair_name

  cp_subnet_id          = module.networking.subnet_ids["k8s-2a"]
  cp_security_group_ids = [module.security_groups.sg_ids["k8s-cp"]]

  worker_az_subnets = {
    a = module.networking.subnet_ids["k8s-2a"]
    b = module.networking.subnet_ids["k8s-2b"]
    c = module.networking.subnet_ids["k8s-2c"]
  }
  worker_security_group_ids = [module.security_groups.sg_ids["k8s-worker"]]

  iam_instance_profile = module.iam.instance_profile_name
  common_tags          = local.common_tags
}

# --- ALB ---

module "alb" {
  source = "./modules/alb"

  project_name     = var.project_name
  vpc_id           = var.vpc_id
  subnet_ids       = module.networking.subnet_ids_list
  security_group_ids = [module.security_groups.sg_ids["k8s-alb"]]
  gateway_nodeport = var.gateway_nodeport
  worker_instances = module.k8s_nodes.worker_instance_ids
  common_tags      = local.common_tags
}
