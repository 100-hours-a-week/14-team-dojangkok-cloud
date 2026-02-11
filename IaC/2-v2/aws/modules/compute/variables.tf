variable "project_name" {
  description = "리소스 이름에 사용할 프로젝트 접두사"
  type        = string
}

variable "instances" {
  description = "EC2 인스턴스 맵 (name => config)"
  type = map(object({
    instance_type        = string
    subnet_id            = string
    security_group_ids   = list(string)
    ami                  = optional(string)
    volume_size          = optional(number, 20)
    volume_type          = optional(string, "gp3")
    iam_instance_profile = optional(string)
    user_data            = optional(string)
    assign_eip           = optional(bool, false)
  }))
}

variable "tags" {
  description = "추가 태그"
  type        = map(string)
  default     = {}
}
