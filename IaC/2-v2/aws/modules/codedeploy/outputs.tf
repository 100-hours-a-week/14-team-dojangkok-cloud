output "app_names" {
  value = { for k, v in aws_codedeploy_app.this : k => v.name }
}

output "deployment_group_names" {
  value = { for k, v in aws_codedeploy_deployment_group.this : k => v.deployment_group_name }
}
