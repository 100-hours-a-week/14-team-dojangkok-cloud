output "mig_name" {
  description = "MIG 이름"
  value       = module.ai_server.mig_name
}

output "mig_self_link" {
  description = "MIG self_link"
  value       = module.ai_server.mig_self_link
}

output "instance_template_id" {
  description = "Instance Template ID"
  value       = module.ai_server.instance_template_id
}
