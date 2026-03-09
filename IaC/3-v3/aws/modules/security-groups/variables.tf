# ============================================================
# V3 K8S IaC — Security Groups Variables
# ============================================================

variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "security_groups" {
  description = "SG 정의 맵 (이름 → 규칙)"
  type = map(object({
    description   = string
    ingress_rules = list(any)
  }))
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
