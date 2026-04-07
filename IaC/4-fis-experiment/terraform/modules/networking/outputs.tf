output "subnet_ids" {
  value = { for k, v in aws_subnet.k8s : k => v.id }
}

output "subnet_ids_list" {
  description = "ALB용 서브넷 ID 목록"
  value       = [for v in aws_subnet.k8s : v.id]
}
