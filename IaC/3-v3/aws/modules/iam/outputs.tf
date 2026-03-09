# ============================================================
# V3 K8S IaC — IAM Outputs
# ============================================================

output "instance_profile_name" {
  description = "K8S 노드용 IAM instance profile 이름"
  value       = aws_iam_instance_profile.k8s_node.name
}

output "role_arn" {
  description = "K8S 노드 IAM role ARN"
  value       = aws_iam_role.k8s_node.arn
}
