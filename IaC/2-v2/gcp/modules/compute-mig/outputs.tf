output "instance_template_id" {
  description = "Instance Template ID"
  value       = google_compute_instance_template.this.id
}

output "instance_template_self_link" {
  description = "Instance Template self_link"
  value       = google_compute_instance_template.this.self_link
}

output "mig_name" {
  description = "MIG 이름"
  value       = google_compute_instance_group_manager.this.name
}

output "mig_self_link" {
  description = "MIG self_link"
  value       = google_compute_instance_group_manager.this.self_link
}

output "mig_instance_group" {
  description = "MIG Instance Group URL"
  value       = google_compute_instance_group_manager.this.instance_group
}
