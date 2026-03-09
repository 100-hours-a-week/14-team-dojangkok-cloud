# ==============================================
# Outputs
# ==============================================

output "instance_id" {
  description = "Monitor EC2 instance ID"
  value       = aws_instance.monitor.id
}

output "monitor_eip" {
  description = "Monitor server public IP (EIP)"
  value       = aws_eip.monitor.public_ip
}

output "security_group_id" {
  description = "Monitor SG ID"
  value       = aws_security_group.monitor.id
}

output "private_ip" {
  description = "Monitor server private IP"
  value       = aws_instance.monitor.private_ip
}
