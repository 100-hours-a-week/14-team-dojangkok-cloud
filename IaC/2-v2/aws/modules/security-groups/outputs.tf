output "security_group_ids" {
  value = { for k, v in aws_security_group.this : k => v.id }
}

output "s3_endpoint_id" {
  value = var.enable_s3_endpoint ? aws_vpc_endpoint.s3[0].id : null
}
