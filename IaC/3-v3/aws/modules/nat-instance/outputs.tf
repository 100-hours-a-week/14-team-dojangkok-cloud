# ============================================================
# V3 K8S IaC — NAT Instance Outputs
# ============================================================

output "eip_public_ip" {
  description = "NAT EIP 퍼블릭 IP (모니터링 SG 허용 등에 사용)"
  value       = aws_eip.nat.public_ip
}

output "security_group_id" {
  value = aws_security_group.nat.id
}
