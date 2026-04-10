variable "project_name" {
  type = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
}

variable "etcd_backup_bucket" {
  type    = string
  default = "fis-exp-etcd-backup"
}

variable "ansible_ssm_bucket" {
  type    = string
  default = "fis-exp-ansible-ssm"
}
