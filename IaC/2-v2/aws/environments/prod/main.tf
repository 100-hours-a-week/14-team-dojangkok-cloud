# ==============================================
# PROD Environment
# VPC 10.3.0.0/18, 2 AZs (a, c)
# IAM roles managed in shared environment
# FE/BE: ASG + CodeDeploy Blue/Green
# ==============================================

locals {
  subnets = {
    # Public subnets (/24)
    "public-2a" = { cidr = "10.3.0.0/24", az = "a", tier = "public" }
    "public-2c" = { cidr = "10.3.1.0/24", az = "c", tier = "public" }
    # Frontend (/22)
    "fe-2a" = { cidr = "10.3.4.0/22", az = "a", tier = "private" }
    "fe-2c" = { cidr = "10.3.8.0/22", az = "c", tier = "private" }
    # Backend (/22)
    "be-2a" = { cidr = "10.3.12.0/22", az = "a", tier = "private" }
    "be-2c" = { cidr = "10.3.16.0/22", az = "c", tier = "private" }
    # MySQL (/24)
    "mysql-2a" = { cidr = "10.3.20.0/24", az = "a", tier = "private" }
    "mysql-2c" = { cidr = "10.3.21.0/24", az = "c", tier = "private" }
    # Redis (/24)
    "redis-2a" = { cidr = "10.3.22.0/24", az = "a", tier = "private" }
    "redis-2c" = { cidr = "10.3.23.0/24", az = "c", tier = "private" }
    # MQ (/24)
    "mq-2a" = { cidr = "10.3.24.0/24", az = "a", tier = "private" }
    "mq-2c" = { cidr = "10.3.25.0/24", az = "c", tier = "private" }
  }

  public_subnets  = { for k, v in local.subnets : k => v if v.tier == "public" }
  private_subnets = { for k, v in local.subnets : k => v if v.tier == "private" }
}

# --- Networking ---
module "networking" {
  source = "../../modules/networking"

  project_name       = var.project_name
  region             = var.region
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones

  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets
}

# --- NAT Instances ---
module "nat_instance" {
  source = "../../modules/nat-instance"

  project_name         = var.project_name
  vpc_id               = module.networking.vpc_id
  vpc_cidr             = var.vpc_cidr
  instance_type        = var.nat_instance_type
  iam_instance_profile = var.iam_instance_profile_names["nat-instance"]

  nat_instances = {
    a = {
      subnet_id      = module.networking.public_subnet_ids["public-2a"]
      route_table_id = module.networking.private_route_table_ids["a"]
    }
    c = {
      subnet_id      = module.networking.public_subnet_ids["public-2c"]
      route_table_id = module.networking.private_route_table_ids["c"]
    }
  }
}

# --- Security Groups ---
# SG 참조 규칙은 모듈 밖에서 aws_security_group_rule로 추가 (순환 의존 방지)
module "security_groups" {
  source = "../../modules/security-groups"

  project_name = var.project_name
  region       = var.region
  vpc_id       = module.networking.vpc_id

  security_groups = {
    alb = {
      description = "Application Load Balancer"
      ingress_rules = [
        { from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTP" },
        { from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTPS" },
      ]
    }
    nlb = {
      description = "Network Load Balancer"
      ingress_rules = [
        { from_port = 5671, to_port = 5671, protocol = "tcp", cidr_blocks = var.gcp_nat_ip != "" ? ["${var.gcp_nat_ip}/32"] : [], description = "TLS from GCP" },
      ]
    }
    fe = {
      description   = "Frontend (Next.js)"
      ingress_rules = []
    }
    be = {
      description   = "Backend (Spring Boot)"
      ingress_rules = []
    }
    mysql = {
      description   = "MySQL"
      ingress_rules = []
    }
    redis = {
      description   = "Redis"
      ingress_rules = []
    }
    mq = {
      description   = "RabbitMQ"
      ingress_rules = []
    }
  }

  enable_s3_endpoint = true
  route_table_ids = concat(
    [module.networking.public_route_table_id],
    values(module.networking.private_route_table_ids),
  )
}

# --- SG Reference Rules (SG-to-SG) ---
# fe <- alb (tcp 3000)
resource "aws_security_group_rule" "fe_from_alb" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  security_group_id        = module.security_groups.security_group_ids["fe"]
  source_security_group_id = module.security_groups.security_group_ids["alb"]
  description              = "app from ALB"
}

# be <- alb (tcp 8080)
resource "aws_security_group_rule" "be_from_alb" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = module.security_groups.security_group_ids["be"]
  source_security_group_id = module.security_groups.security_group_ids["alb"]
  description              = "app from ALB"
}

# mysql <- be (tcp 3306)
resource "aws_security_group_rule" "mysql_from_be" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = module.security_groups.security_group_ids["mysql"]
  source_security_group_id = module.security_groups.security_group_ids["be"]
  description              = "mysql from BE"
}

# redis <- be (tcp 6379)
resource "aws_security_group_rule" "redis_from_be" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = module.security_groups.security_group_ids["redis"]
  source_security_group_id = module.security_groups.security_group_ids["be"]
  description              = "redis from BE"
}

# mq <- be (tcp 5672)
resource "aws_security_group_rule" "mq_from_be" {
  type                     = "ingress"
  from_port                = 5672
  to_port                  = 5672
  protocol                 = "tcp"
  security_group_id        = module.security_groups.security_group_ids["mq"]
  source_security_group_id = module.security_groups.security_group_ids["be"]
  description              = "AMQP from BE"
}

# mq <- nlb (tcp 5672)
resource "aws_security_group_rule" "mq_from_nlb" {
  type                     = "ingress"
  from_port                = 5672
  to_port                  = 5672
  protocol                 = "tcp"
  security_group_id        = module.security_groups.security_group_ids["mq"]
  source_security_group_id = module.security_groups.security_group_ids["nlb"]
  description              = "AMQP from NLB"
}

# --- Compute (stateful: mysql, redis, mq) ---
module "compute" {
  source = "../../modules/compute"

  project_name = var.project_name

  instances = {
    mysql = {
      instance_type        = var.mysql_instance_type
      subnet_id            = module.networking.private_subnet_ids["mysql-2a"]
      security_group_ids   = [module.security_groups.security_group_ids["mysql"]]
      iam_instance_profile = var.iam_instance_profile_names["mysql"]
      volume_size          = var.mysql_volume_size
    }
    redis = {
      instance_type        = var.redis_instance_type
      subnet_id            = module.networking.private_subnet_ids["redis-2a"]
      security_group_ids   = [module.security_groups.security_group_ids["redis"]]
      iam_instance_profile = var.iam_instance_profile_names["redis"]
      volume_size          = var.redis_volume_size
    }
    mq = {
      instance_type        = var.mq_instance_type
      subnet_id            = module.networking.private_subnet_ids["mq-2a"]
      security_group_ids   = [module.security_groups.security_group_ids["mq"]]
      iam_instance_profile = var.iam_instance_profile_names["mq"]
      volume_size          = var.mq_volume_size
    }
  }
}

# --- ALB ---
module "alb" {
  source = "../../modules/alb"

  project_name        = var.project_name
  vpc_id              = module.networking.vpc_id
  subnet_ids          = values(module.networking.public_subnet_ids)
  security_group_ids  = [module.security_groups.security_group_ids["alb"]]
  ssl_certificate_arn = var.ssl_certificate_arn

  target_groups = {
    fe = {
      port              = 3000
      health_check_path = "/health-check"
      path_patterns     = ["/*"]
      priority          = 200
    }
    be = {
      port              = 8080
      health_check_path = "/actuator/health"
      path_patterns     = ["/api/*", "/actuator/*", "/login/*", "/oauth2/*"]
      priority          = 100
    }
  }
}

# --- NLB ---
module "nlb" {
  source = "../../modules/nlb"

  project_name       = var.project_name
  vpc_id             = module.networking.vpc_id
  subnet_ids         = values(module.networking.public_subnet_ids)
  security_group_ids = [module.security_groups.security_group_ids["nlb"]]

  target_groups = {
    mq = {
      port = 5672
    }
  }

  target_group_attachments = {
    mq = {
      target_id = module.compute.instance_ids["mq"]
      port      = 5672
    }
  }

  listeners = {
    tls = {
      port             = 5671
      protocol         = "TLS"
      certificate_arn  = var.ssl_certificate_arn
      target_group_key = "mq"
    }
  }
}

# --- ASG (FE/BE) ---
module "fe_asg" {
  source = "../../modules/asg"

  project_name         = var.project_name
  name                 = "fe"
  instance_type        = var.fe_instance_type
  volume_size          = var.fe_volume_size
  ami_id               = var.custom_ami_id
  iam_instance_profile = var.iam_instance_profile_names["fe"]
  security_group_ids   = [module.security_groups.security_group_ids["fe"]]
  subnet_ids = [
    module.networking.private_subnet_ids["fe-2a"],
    module.networking.private_subnet_ids["fe-2c"],
  ]
  target_group_arns = [module.alb.target_group_arns["fe"]]
}

module "be_asg" {
  source = "../../modules/asg"

  project_name         = var.project_name
  name                 = "be"
  instance_type        = var.be_instance_type
  volume_size          = var.be_volume_size
  ami_id               = var.custom_ami_id
  iam_instance_profile = var.iam_instance_profile_names["be"]
  security_group_ids   = [module.security_groups.security_group_ids["be"]]
  subnet_ids = [
    module.networking.private_subnet_ids["be-2a"],
    module.networking.private_subnet_ids["be-2c"],
  ]
  target_group_arns = [module.alb.target_group_arns["be"]]
}

# --- CodeDeploy (Blue/Green) ---
module "codedeploy" {
  source = "../../modules/codedeploy"

  codedeploy_role_arn = var.codedeploy_role_arn

  applications = {
    be = { name = "${var.project_name}-be" }
    fe = { name = "${var.project_name}-fe" }
  }

  deployment_groups = {
    be = {
      name               = "${var.project_name}-be-dg"
      app_key            = "be"
      deployment_config  = "CodeDeployDefault.AllAtOnce"
      deployment_type    = "BLUE_GREEN"
      autoscaling_groups = [module.be_asg.asg_name]
      target_group_name  = "${var.project_name}-be-tg"
    }
    fe = {
      name               = "${var.project_name}-fe-dg"
      app_key            = "fe"
      deployment_config  = "CodeDeployDefault.AllAtOnce"
      deployment_type    = "BLUE_GREEN"
      autoscaling_groups = [module.fe_asg.asg_name]
      target_group_name  = "${var.project_name}-fe-tg"
    }
  }
}
