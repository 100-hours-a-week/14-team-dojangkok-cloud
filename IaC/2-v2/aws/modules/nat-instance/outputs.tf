output "instance_ids" {
  value = { for k, v in aws_instance.nat : k => v.id }
}

output "eip_public_ips" {
  value = { for k, v in aws_eip.nat : k => v.public_ip }
}

output "security_group_id" {
  value = aws_security_group.nat.id
}
