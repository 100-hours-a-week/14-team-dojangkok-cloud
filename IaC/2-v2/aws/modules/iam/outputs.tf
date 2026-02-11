output "ec2_role_name" {
  description = "EC2 IAM Role 이름"
  value       = aws_iam_role.ec2.name
}

output "ec2_role_arn" {
  description = "EC2 IAM Role ARN"
  value       = aws_iam_role.ec2.arn
}

output "ec2_instance_profile_name" {
  description = "EC2 Instance Profile 이름"
  value       = aws_iam_instance_profile.ec2.name
}

output "codedeploy_role_arn" {
  description = "CodeDeploy IAM Role ARN"
  value       = var.codedeploy_role_name != null ? aws_iam_role.codedeploy[0].arn : null
}
