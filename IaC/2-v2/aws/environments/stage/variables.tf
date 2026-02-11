variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "리소스 이름에 사용할 프로젝트 접두사"
  type        = string
  default     = "dojangkok-stage"
}

variable "vpc_id" {
  description = "기존 VPC ID"
  type        = string
  default     = "vpc-060a437112ddb879d"
}

variable "ssl_certificate_arn" {
  description = "ACM 인증서 ARN (HTTPS)"
  type        = string
  default     = null
}

# IAM (import 대상 - 기존 AWS 리소스 이름)
variable "ec2_role_name" {
  description = "기존 EC2 IAM Role 이름"
  type        = string
}

variable "ec2_instance_profile_name" {
  description = "기존 EC2 Instance Profile 이름"
  type        = string
}

variable "codedeploy_role_name" {
  description = "기존 CodeDeploy Role 이름 (없으면 null)"
  type        = string
  default     = null
}

# --- AMI ---
variable "docker_ami_id" {
  description = "Docker 프리인스톨 AMI ID (FE/BE/DB)"
  type        = string
  default     = null  # TODO: 커스텀 AMI ID 확정 후 입력
}

variable "nat_ami_id" {
  description = "NAT 전용 AMI ID"
  type        = string
  default     = null  # TODO: NAT AMI 확정 후 입력
}

# --- 인스턴스 사양 (빈 항목 — 사용자 확정 필요) ---
variable "fe_instance_type" {
  description = "FE (Next.js) ASG 인스턴스 타입"
  type        = string
  default     = "" # TODO: 사양 확정
}

variable "fe_volume_size" {
  description = "FE 루트 볼륨 (GB)"
  type        = number
  default     = 0 # TODO: 확정
}

variable "fe_min_size" {
  description = "FE ASG 최소 인스턴스 수"
  type        = number
  default     = 0 # TODO: 확정
}

variable "fe_max_size" {
  description = "FE ASG 최대 인스턴스 수"
  type        = number
  default     = 0 # TODO: 확정
}

variable "fe_desired_capacity" {
  description = "FE ASG 원하는 인스턴스 수"
  type        = number
  default     = 0 # TODO: 확정
}

variable "be_instance_type" {
  description = "BE (Spring Boot) ASG 인스턴스 타입"
  type        = string
  default     = "" # TODO: 사양 확정
}

variable "be_volume_size" {
  description = "BE 루트 볼륨 (GB)"
  type        = number
  default     = 0 # TODO: 확정
}

variable "be_min_size" {
  description = "BE ASG 최소 인스턴스 수"
  type        = number
  default     = 0 # TODO: 확정
}

variable "be_max_size" {
  description = "BE ASG 최대 인스턴스 수"
  type        = number
  default     = 0 # TODO: 확정
}

variable "be_desired_capacity" {
  description = "BE ASG 원하는 인스턴스 수"
  type        = number
  default     = 0 # TODO: 확정
}

variable "mysql_instance_type" {
  description = "MySQL 인스턴스 타입"
  type        = string
  default     = "" # TODO: 사양 확정
}

variable "mysql_volume_size" {
  description = "MySQL 루트 볼륨 (GB)"
  type        = number
  default     = 0 # TODO: 확정
}

variable "rabbitmq_instance_type" {
  description = "RabbitMQ 인스턴스 타입"
  type        = string
  default     = "t4g.small"
}

variable "rabbitmq_volume_size" {
  description = "RabbitMQ 루트 볼륨 (GB)"
  type        = number
  default     = 0 # TODO: 확정
}

variable "redis_instance_type" {
  description = "Redis 인스턴스 타입"
  type        = string
  default     = "" # TODO: 사양 확정
}

variable "redis_volume_size" {
  description = "Redis 루트 볼륨 (GB)"
  type        = number
  default     = 0 # TODO: 확정
}
