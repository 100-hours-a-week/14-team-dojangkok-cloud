# ============================================================
# V3 K8S IaC — Security Groups Outputs
# ============================================================

output "security_group_ids" {
  description = "SG ID 맵 (이름 → ID)"
  value       = { for k, v in aws_security_group.this : k => v.id }
}
