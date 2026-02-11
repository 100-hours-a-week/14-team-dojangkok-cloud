output "security_group_ids" {
  description = "보안 그룹 ID 맵"
  value       = { for k, v in aws_security_group.this : k => v.id }
}

output "s3_endpoint_id" {
  description = "S3 VPC Endpoint ID"
  value       = var.enable_s3_endpoint ? aws_vpc_endpoint.s3[0].id : null
}
