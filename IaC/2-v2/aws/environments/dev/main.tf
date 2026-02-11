# ==============================================
# DEV 환경 — Primary CIDR (10.0.x.x)
# ALB + ASG(FE/BE), DB 단일 인스턴스, Monitoring 통합
# ==============================================

locals {
  # DEV는 Primary CIDR 사용 → Secondary CIDR 불필요
  env_cidr       = "10.0.0.0/18"
  public_cidr    = "10.0.0.0/24"
  alb_dummy_cidr = "10.0.6.0/28"   # AZ-c, ALB 2-AZ 요건 충족용
  fe_cidr        = "10.0.1.0/24"
  be_cidr        = "10.0.2.0/24"
  rdb_cidr       = "10.0.3.0/24"
  mq_cidr        = "10.0.4.0/24"
  cache_cidr     = "10.0.5.0/24"
  # Monitoring은 dev-public에 위치 → 전 환경 exporter 수집
  monitoring_src = [local.public_cidr]
}

# --- Networking ---
module "networking" {
  source = "../../modules/networking"

  project_name   = var.project_name
  region         = var.region
  vpc_id         = var.vpc_id
  secondary_cidr = null # Primary CIDR 사용

  public_subnets = {
    "dev-public"   = { cidr = local.public_cidr, az = "a" }
    "dev-public-c" = { cidr = local.alb_dummy_cidr, az = "c" }  # ALB 2-AZ 요건
  }

  private_subnets = {
    "dev-pri-fe"    = { cidr = local.fe_cidr, az = "a" }
    "dev-pri-be"    = { cidr = local.be_cidr, az = "a" }
    "dev-pri-rdb"   = { cidr = local.rdb_cidr, az = "a" }
    "dev-pri-mq"    = { cidr = local.mq_cidr, az = "a" }
    "dev-pri-cache" = { cidr = local.cache_cidr, az = "a" }
  }

  enable_nat        = true
  nat_instance_type = "t4g.nano"
  nat_ingress_cidrs = [local.env_cidr]
  nat_ami_id        = var.nat_ami_id
}

# --- Security ---
module "security" {
  source = "../../modules/security"

  project_name = var.project_name
  region       = var.region
  vpc_id       = module.networking.vpc_id

  security_groups = {
    # --- Public Subnet ---
    alb = {
      description = "Application Load Balancer"
      ingress_rules = [
        { from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTP" },
        { from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTPS" },
      ]
    }
    monitoring = {
      description = "Prometheus/Grafana/Loki (전 환경 통합)"
      ingress_rules = [
        { from_port = 3000, to_port = 3000, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "Grafana" },
        { from_port = 9090, to_port = 9090, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "Prometheus" },
        { from_port = 3100, to_port = 3100, protocol = "tcp", cidr_blocks = [local.env_cidr, "10.1.0.0/18", "10.2.0.0/18", var.gcp_ai_server_cidr], description = "Loki (VPC + GCP AI)" },
      ]
    }
    # --- Private Subnet ---
    fe = {
      description = "Frontend (Next.js)"
      ingress_rules = [
        { from_port = 3000, to_port = 3000, protocol = "tcp", cidr_blocks = [local.env_cidr], description = "app" },
        { from_port = 9100, to_port = 9100, protocol = "tcp", cidr_blocks = local.monitoring_src, description = "node_exporter" },
      ]
    }
    be = {
      description = "Backend (Spring Boot)"
      ingress_rules = [
        { from_port = 8080, to_port = 8080, protocol = "tcp", cidr_blocks = [local.env_cidr], description = "app" },
        { from_port = 8080, to_port = 8080, protocol = "tcp", cidr_blocks = local.monitoring_src, description = "jvm_exporter" },
        { from_port = 9100, to_port = 9100, protocol = "tcp", cidr_blocks = local.monitoring_src, description = "node_exporter" },
      ]
    }
    mysql = {
      description = "MySQL"
      ingress_rules = [
        { from_port = 3306, to_port = 3306, protocol = "tcp", cidr_blocks = [local.be_cidr], description = "mysql" },
        { from_port = 9104, to_port = 9104, protocol = "tcp", cidr_blocks = local.monitoring_src, description = "mysql_exporter" },
        { from_port = 9100, to_port = 9100, protocol = "tcp", cidr_blocks = local.monitoring_src, description = "node_exporter" },
      ]
    }
    rabbitmq = {
      description = "RabbitMQ (AMQPS)"
      ingress_rules = [
        { from_port = 5672, to_port = 5672, protocol = "tcp", cidr_blocks = [local.env_cidr], description = "amqp" },
        { from_port = 15672, to_port = 15672, protocol = "tcp", cidr_blocks = local.monitoring_src, description = "management" },
        { from_port = 9100, to_port = 9100, protocol = "tcp", cidr_blocks = local.monitoring_src, description = "node_exporter" },
      ]
    }
    redis = {
      description = "Redis"
      ingress_rules = [
        { from_port = 6379, to_port = 6379, protocol = "tcp", cidr_blocks = [local.be_cidr], description = "redis" },
        { from_port = 9121, to_port = 9121, protocol = "tcp", cidr_blocks = local.monitoring_src, description = "redis_exporter" },
        { from_port = 9100, to_port = 9100, protocol = "tcp", cidr_blocks = local.monitoring_src, description = "node_exporter" },
      ]
    }
  }

  enable_s3_endpoint = true
  route_table_ids = [
    module.networking.public_route_table_id,
    module.networking.private_route_table_id,
  ]
}

# --- IAM (import 방식) ---
# 최초 적용 시: terraform import module.iam.aws_iam_role.ec2 <role_name>
#               terraform import module.iam.aws_iam_instance_profile.ec2 <profile_name>
#               terraform import module.iam.aws_iam_role.codedeploy[0] <codedeploy_role_name>
module "iam" {
  source = "../../modules/iam"

  ec2_role_name             = var.ec2_role_name
  ec2_instance_profile_name = var.ec2_instance_profile_name

  policy_arns = [
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ]

  codedeploy_role_name = var.codedeploy_role_name
}

# --- ALB ---
module "alb" {
  source = "../../modules/alb"

  project_name        = var.project_name
  vpc_id              = module.networking.vpc_id
  subnet_ids          = values(module.networking.public_subnet_ids)
  security_group_ids  = [module.security.security_group_ids["alb"]]
  ssl_certificate_arn = var.ssl_certificate_arn

  target_groups = {
    fe = {
      port              = 3000
      health_check_path = "/"
      path_pattern      = "/*"
      priority          = 200
    }
    be = {
      port              = 8080
      health_check_path = "/actuator/health"
      path_pattern      = "/api/*"
      priority          = 100
    }
  }
}

# --- ASG (FE) ---
module "asg_fe" {
  source = "../../modules/asg"

  project_name         = var.project_name
  service_name         = "fe"
  ami_id               = var.docker_ami_id
  instance_type        = var.fe_instance_type
  subnet_ids           = [module.networking.private_subnet_ids["dev-pri-fe"]]
  security_group_ids   = [module.security.security_group_ids["fe"]]
  target_group_arns    = [module.alb.target_group_arns["fe"]]
  iam_instance_profile = module.iam.ec2_instance_profile_name

  min_size         = var.fe_min_size
  max_size         = var.fe_max_size
  desired_capacity = var.fe_desired_capacity
  volume_size      = var.fe_volume_size
}

# --- ASG (BE) ---
module "asg_be" {
  source = "../../modules/asg"

  project_name         = var.project_name
  service_name         = "be"
  ami_id               = var.docker_ami_id
  instance_type        = var.be_instance_type
  subnet_ids           = [module.networking.private_subnet_ids["dev-pri-be"]]
  security_group_ids   = [module.security.security_group_ids["be"]]
  target_group_arns    = [module.alb.target_group_arns["be"]]
  iam_instance_profile = module.iam.ec2_instance_profile_name

  min_size         = var.be_min_size
  max_size         = var.be_max_size
  desired_capacity = var.be_desired_capacity
  volume_size      = var.be_volume_size
}

# --- Public 인스턴스: Monitoring ---
module "public_servers" {
  source = "../../modules/compute"

  project_name = var.project_name

  instances = {
    monitoring = {
      instance_type        = var.monitoring_instance_type
      ami                  = var.docker_ami_id
      subnet_id            = module.networking.public_subnet_ids["dev-public"]
      security_group_ids   = [module.security.security_group_ids["monitoring"]]
      iam_instance_profile = module.iam.ec2_instance_profile_name
      volume_size          = var.monitoring_volume_size
      assign_eip           = true
    }
  }
}

# --- DB 서버 (Private Subnet) ---
module "db_servers" {
  source = "../../modules/compute"

  project_name = var.project_name

  instances = {
    mysql = {
      instance_type        = var.mysql_instance_type
      ami                  = var.docker_ami_id
      subnet_id            = module.networking.private_subnet_ids["dev-pri-rdb"]
      security_group_ids   = [module.security.security_group_ids["mysql"]]
      iam_instance_profile = module.iam.ec2_instance_profile_name
      volume_size          = var.mysql_volume_size
    }
    rabbitmq = {
      instance_type        = var.rabbitmq_instance_type
      ami                  = var.docker_ami_id
      subnet_id            = module.networking.private_subnet_ids["dev-pri-mq"]
      security_group_ids   = [module.security.security_group_ids["rabbitmq"]]
      iam_instance_profile = module.iam.ec2_instance_profile_name
      volume_size          = var.rabbitmq_volume_size
    }
    redis = {
      instance_type        = var.redis_instance_type
      ami                  = var.docker_ami_id
      subnet_id            = module.networking.private_subnet_ids["dev-pri-cache"]
      security_group_ids   = [module.security.security_group_ids["redis"]]
      iam_instance_profile = module.iam.ec2_instance_profile_name
      volume_size          = var.redis_volume_size
    }
  }
}
