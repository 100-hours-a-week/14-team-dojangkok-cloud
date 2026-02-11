output "asg_name" {
  description = "Auto Scaling Group 이름"
  value       = aws_autoscaling_group.this.name
}

output "asg_arn" {
  description = "Auto Scaling Group ARN"
  value       = aws_autoscaling_group.this.arn
}

output "launch_template_id" {
  description = "Launch Template ID"
  value       = aws_launch_template.this.id
}
