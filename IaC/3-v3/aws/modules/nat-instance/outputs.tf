# ============================================================
# V3 K8S IaC — NAT Instance Outputs
# ============================================================

output "security_group_id" {
  value = aws_security_group.nat.id
}
