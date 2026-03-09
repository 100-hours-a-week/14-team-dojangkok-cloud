# ==============================================
# DEV Environment
# VPC 10.1.0.0/18, 2 AZs (a, c)
# ==============================================

locals {
  # Subnet CIDR layout (10.1.0.0/18 = 10.1.0.0 ~ 10.1.63.255)
  subnets = {
    # Public subnets
    "public-2a" = { cidr = "10.1.0.0/24", az = "a", tier = "public" }
    "public-2c" = { cidr = "10.1.1.0/24", az = "c", tier = "public" }
    # Frontend
    "fe-2a" = { cidr = "10.1.10.0/24", az = "a", tier = "private" }
    "fe-2c" = { cidr = "10.1.11.0/24", az = "c", tier = "private" }
    # Backend
    "be-2a" = { cidr = "10.1.20.0/24", az = "a", tier = "private" }
    "be-2c" = { cidr = "10.1.21.0/24", az = "c", tier = "private" }
    # MySQL
    "mysql-2a" = { cidr = "10.1.30.0/24", az = "a", tier = "private" }
    "mysql-2c" = { cidr = "10.1.31.0/24", az = "c", tier = "private" }
    # Redis
    "redis-2a" = { cidr = "10.1.40.0/24", az = "a", tier = "private" }
    "redis-2c" = { cidr = "10.1.41.0/24", az = "c", tier = "private" }
    # MQ (RabbitMQ)
    "mq-2a" = { cidr = "10.1.50.0/24", az = "a", tier = "private" }
    "mq-2c" = { cidr = "10.1.51.0/24", az = "c", tier = "private" }
    # AI Server
    "ai-2a" = { cidr = "10.0.15.0/24", az = "a", tier = "private" }
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

# --- NAT Instances (per-AZ) ---
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
        { from_port = 5671, to_port = 5671, protocol = "tcp", cidr_blocks = ["10.0.15.0/24"], description = "TLS from AI server" },
      ]
    }
    fe = {
      description = "Frontend (Next.js)"
      ingress_rules = [
        { from_port = 3000, to_port = 3000, protocol = "tcp", cidr_blocks = [var.vpc_cidr], description = "app" },
      ]
    }
    be = {
      description = "Backend (Spring Boot)"
      ingress_rules = [
        { from_port = 8080, to_port = 8080, protocol = "tcp", cidr_blocks = [var.vpc_cidr], description = "app" },
      ]
    }
    mysql = {
      description = "MySQL"
      ingress_rules = [
        { from_port = 3306, to_port = 3306, protocol = "tcp", cidr_blocks = ["10.1.20.0/24", "10.1.21.0/24"], description = "mysql from BE" },
      ]
    }
    redis = {
      description = "Redis"
      ingress_rules = [
        { from_port = 6379, to_port = 6379, protocol = "tcp", cidr_blocks = ["10.1.20.0/24", "10.1.21.0/24"], description = "redis from BE" },
      ]
    }
    mq = {
      description = "RabbitMQ"
      ingress_rules = [
        { from_port = 5672, to_port = 5672, protocol = "tcp", cidr_blocks = [var.vpc_cidr], description = "AMQP" },
        { from_port = 15672, to_port = 15672, protocol = "tcp", cidr_blocks = [var.vpc_cidr], description = "Management UI" },
      ]
    }
    ai = {
      description = "AI Server (FastAPI)"
      ingress_rules = [
        { from_port = 8000, to_port = 8000, protocol = "tcp", cidr_blocks = [var.vpc_cidr], description = "FastAPI" },
      ]
    }
  }

  enable_s3_endpoint = true
  route_table_ids = concat(
    [module.networking.public_route_table_id],
    values(module.networking.private_route_table_ids),
  )
}

# --- Compute: MySQL, Redis, MQ ---
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
    ai = {
      instance_type        = var.ai_instance_type
      ami                  = var.custom_ami_id
      subnet_id            = module.networking.private_subnet_ids["ai-2a"]
      security_group_ids   = [module.security_groups.security_group_ids["ai"]]
      iam_instance_profile = var.iam_instance_profile_names["ai"]
      volume_size          = var.ai_volume_size
      user_data = templatefile("${path.module}/scripts/startup-ai-server.sh", {
        region       = var.region
        environment  = var.environment
        project_name = var.project_name
        ecr_registry = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
        compose_content = templatefile("../../gcp/docker-compose/ai-server.yml", {
          AI_SERVER_IMAGE                = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/dev-dojangkok-ai:latest"
          APP_ENV                        = var.environment
          VLLM_BASE_URL                  = var.ai_vllm_base_url
          VLLM_MODEL                     = var.ai_vllm_model
          VLLM_LORA_ADAPTER_CHECKLIST    = var.ai_vllm_lora_adapter_checklist
          VLLM_LORA_ADAPTER_EASYCONTRACT = var.ai_vllm_lora_adapter_easycontract
          CHROMADB_URL                   = ""
          BACKEND_CALLBACK_BASE_URL      = var.ai_backend_callback_base_url
          HTTP_TIMEOUT_SEC               = var.ai_http_timeout_sec
          RABBITMQ_ENABLED                           = "true"
          RABBITMQ_PREFETCH_COUNT                    = "3"
          RABBITMQ_DECLARE_PASSIVE                   = "true"
          RABBITMQ_REQUEST_EXCHANGE_EASY_CONTRACT    = var.rabbitmq_request_exchange_easy_contract
          RABBITMQ_REQUEST_QUEUE_EASY_CONTRACT       = var.rabbitmq_request_queue_easy_contract
          RABBITMQ_REQUEST_ROUTING_KEY_EASY_CONTRACT = var.rabbitmq_request_routing_key_easy_contract
          RABBITMQ_REQUEST_EXCHANGE_CHECKLIST        = var.rabbitmq_request_exchange_checklist
          RABBITMQ_REQUEST_QUEUE_CHECKLIST           = var.rabbitmq_request_queue_checklist
          RABBITMQ_REQUEST_ROUTING_KEY_CHECKLIST     = var.rabbitmq_request_routing_key_checklist
          RABBITMQ_CANCEL_EXCHANGE_EASY_CONTRACT     = var.rabbitmq_cancel_exchange_easy_contract
          RABBITMQ_CANCEL_QUEUE_EASY_CONTRACT        = var.rabbitmq_cancel_queue_easy_contract
          RABBITMQ_CANCEL_ROUTING_KEY_EASY_CONTRACT  = var.rabbitmq_cancel_routing_key_easy_contract
          RABBITMQ_RESULT_EXCHANGE                   = var.rabbitmq_result_exchange
          RABBITMQ_RESULT_QUEUE                      = var.rabbitmq_result_queue
          RABBITMQ_RESULT_ROUTING_KEY                = var.rabbitmq_result_routing_key
        })
        alloy_config = templatefile("../../gcp/docker-compose/alloy/config.alloy", {
          hostname             = "${var.project_name}-ai"
          service_name         = "ai-server"
          loki_url             = var.loki_url
          tempo_endpoint       = var.tempo_endpoint
          prometheus_url       = var.prometheus_url
          enable_dcgm_exporter = false
        })
      })
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
      health_check_path = "/"
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

# --- NLB (GCP -> RabbitMQ) ---
module "nlb" {
  source = "../../modules/nlb"

  project_name = var.project_name
  vpc_id       = module.networking.vpc_id
  subnet_ids   = values(module.networking.public_subnet_ids)

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
  user_data = <<-EOF
    #!/bin/bash
    set -e
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
    aws s3 cp s3://${var.alloy_config_s3_bucket}/alloy-configs/fe.alloy /etc/alloy/config.alloy --region ${var.region}
    sed -i "s/INSTANCE_LABEL/${var.project_name}-fe-$${PRIVATE_IP}/g" /etc/alloy/config.alloy
    systemctl restart alloy
  EOF
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
  user_data = <<-EOF
    #!/bin/bash
    set -e
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
    aws s3 cp s3://${var.alloy_config_s3_bucket}/alloy-configs/be.alloy /etc/alloy/config.alloy --region ${var.region}
    sed -i "s/INSTANCE_LABEL/${var.project_name}-be-$${PRIVATE_IP}/g" /etc/alloy/config.alloy
    systemctl restart alloy
  EOF
}

# --- CloudFront (Landing Page) ---
module "cloudfront" {
  count  = var.landing_page_bucket_domain != "" ? 1 : 0
  source = "../../modules/cloudfront"

  project_name          = var.project_name
  s3_bucket_domain_name = var.landing_page_bucket_domain
  acm_certificate_arn   = var.cloudfront_acm_arn
  aliases               = ["home.${var.domain_name}"]
}

# --- Data Sources ---
data "aws_caller_identity" "current" {}

# --- AI Server: SSM Parameters (Secrets) ---
resource "aws_ssm_parameter" "ai_secrets" {
  for_each = {
    "vllm-api-key"          = var.ai_vllm_api_key
    "backend-internal-token" = var.ai_backend_internal_token
    "ocr-api"               = var.ai_ocr_api
    "rabbitmq-url"          = var.ai_rabbitmq_url
  }

  name  = "/dojangkok/${var.environment}/ai/${each.key}"
  type  = "SecureString"
  value = each.value

  tags = {
    Name = "${var.project_name}-ai-${each.key}"
  }
}

# --- AI Server: ECR Repository ---
module "ai_ecr" {
  source       = "../../modules/ecr"
  repositories = ["dev-dojangkok-ai"]
}
