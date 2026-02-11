output "instance_ids" {
  description = "EC2 인스턴스 ID 맵"
  value       = { for k, v in aws_instance.this : k => v.id }
}

output "private_ips" {
  description = "EC2 인스턴스 프라이빗 IP 맵"
  value       = { for k, v in aws_instance.this : k => v.private_ip }
}

output "public_ips" {
  description = "EIP가 할당된 인스턴스의 퍼블릭 IP 맵"
  value       = { for k, v in aws_eip.this : k => v.public_ip }
}
