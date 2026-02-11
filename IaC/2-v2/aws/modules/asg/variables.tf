variable "project_name" {
  description = "리소스 이름에 사용할 프로젝트 접두사"
  type        = string
}

variable "service_name" {
  description = "서비스 이름 (fe, be 등)"
  type        = string
}

variable "instance_type" {
  description = "EC2 인스턴스 타입"
  type        = string
}

variable "ami_id" {
  description = "AMI ID (null이면 최신 Ubuntu ARM64)"
  type        = string
  default     = null
}

variable "min_size" {
  description = "ASG 최소 인스턴스 수"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "ASG 최대 인스턴스 수"
  type        = number
  default     = 2
}

variable "desired_capacity" {
  description = "ASG 원하는 인스턴스 수"
  type        = number
  default     = 1
}

variable "subnet_ids" {
  description = "ASG에 사용할 서브넷 ID 목록"
  type        = list(string)
}

variable "security_group_ids" {
  description = "인스턴스에 연결할 보안 그룹 ID 목록"
  type        = list(string)
}

variable "target_group_arns" {
  description = "ALB Target Group ARN 목록"
  type        = list(string)
  default     = []
}

variable "iam_instance_profile" {
  description = "IAM 인스턴스 프로필 이름"
  type        = string
  default     = null
}

variable "volume_size" {
  description = "루트 볼륨 크기 (GB)"
  type        = number
  default     = 20
}

variable "user_data" {
  description = "EC2 User Data 스크립트"
  type        = string
  default     = null
}

variable "enable_cpu_scaling" {
  description = "CPU 기반 오토 스케일링 활성화"
  type        = bool
  default     = true
}

variable "cpu_target_value" {
  description = "CPU 타겟 트래킹 목표값 (%)"
  type        = number
  default     = 70
}
