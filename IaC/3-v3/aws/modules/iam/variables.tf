# ============================================================
# V3 K8S IaC — IAM Variables
# ============================================================

variable "project_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "aws_account_id" {
  type = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
