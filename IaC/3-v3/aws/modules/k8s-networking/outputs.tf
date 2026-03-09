# ============================================================
# V3 K8S IaC — Networking Outputs
# ============================================================

output "subnet_ids" {
  description = "생성된 서브넷 ID 맵"
  value       = { for k, v in aws_subnet.subnets : k => v.id }
}

output "public_subnet_ids" {
  description = "Public 서브넷 ID 목록 (ALB용)"
  value       = [for k, v in aws_subnet.subnets : v.id if var.subnets[k].tier == "public"]
}

output "private_subnet_ids" {
  description = "Private 서브넷 ID 맵 (K8S 노드용)"
  value       = { for k, v in aws_subnet.subnets : k => v.id if var.subnets[k].tier == "private" }
}

output "private_route_table_ids" {
  description = "AZ별 Private route table ID 맵 (NAT 연결용)"
  value       = { for k, v in aws_route_table.private : k => v.id }
}
