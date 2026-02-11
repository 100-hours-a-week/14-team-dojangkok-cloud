output "vpc_id" {
  description = "VPC ID"
  value       = data.aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC Primary CIDR 블록"
  value       = data.aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 맵"
  value       = { for k, v in aws_subnet.public : k => v.id }
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 맵"
  value       = { for k, v in aws_subnet.private : k => v.id }
}

output "public_route_table_id" {
  description = "퍼블릭 라우트 테이블 ID"
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "프라이빗 라우트 테이블 ID"
  value       = aws_route_table.private.id
}

output "nat_instance_id" {
  description = "NAT 인스턴스 ID"
  value       = var.enable_nat ? aws_instance.nat[0].id : null
}

output "nat_public_ip" {
  description = "NAT 인스턴스 퍼블릭 IP"
  value       = var.enable_nat ? aws_eip.nat[0].public_ip : null
}

output "igw_id" {
  description = "Internet Gateway ID"
  value       = data.aws_internet_gateway.this.id
}
