variable "project_name" {
  description = "리소스 이름에 사용할 프로젝트 접두사"
  type        = string
}

variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "vpc_id" {
  description = "기존 VPC ID"
  type        = string
}

variable "secondary_cidr" {
  description = "추가할 Secondary CIDR 블록 (null이면 추가하지 않음)"
  type        = string
  default     = null
}

variable "public_subnets" {
  description = "퍼블릭 서브넷 맵 (name => {cidr, az})"
  type = map(object({
    cidr = string
    az   = string
  }))
}

variable "private_subnets" {
  description = "프라이빗 서브넷 맵 (name => {cidr, az})"
  type = map(object({
    cidr = string
    az   = string
  }))
  default = {}
}

variable "enable_nat" {
  description = "NAT Instance 생성 여부"
  type        = bool
  default     = false
}

variable "nat_instance_type" {
  description = "NAT 인스턴스 타입"
  type        = string
  default     = "t4g.nano"
}

variable "nat_ami_id" {
  description = "NAT 인스턴스 AMI ID (null이면 Ubuntu ARM64 자동 선택)"
  type        = string
  default     = null
}

variable "nat_ingress_cidrs" {
  description = "NAT SG에 허용할 CIDR 목록 (환경 CIDR)"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

