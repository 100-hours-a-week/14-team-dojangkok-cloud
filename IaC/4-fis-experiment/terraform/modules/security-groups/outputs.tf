output "sg_ids" {
  value = { for k, v in aws_security_group.this : k => v.id }
}
