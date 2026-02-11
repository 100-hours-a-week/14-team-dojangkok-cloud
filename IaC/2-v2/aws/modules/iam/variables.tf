variable "ec2_role_name" {
  description = "EC2 IAM Role 이름 (기존 리소스 import 시 실제 이름 입력)"
  type        = string
}

variable "ec2_instance_profile_name" {
  description = "EC2 Instance Profile 이름 (기존 리소스 import 시 실제 이름 입력)"
  type        = string
}

variable "policy_arns" {
  description = "EC2 Role에 연결할 IAM Policy ARN 목록"
  type        = list(string)
  default     = []
}

variable "codedeploy_role_name" {
  description = "CodeDeploy Role 이름 (null이면 생성하지 않음)"
  type        = string
  default     = null
}
