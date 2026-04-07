# --- K8S Nodes ---

output "control_plane" {
  value = module.k8s_nodes.control_plane
}

output "workers" {
  value = module.k8s_nodes.workers
}

# --- ALB ---

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "target_group_arn" {
  value = module.alb.target_group_arn
}

# --- Networking ---

output "subnet_ids" {
  value = module.networking.subnet_ids
}

# --- SG ---

output "security_group_ids" {
  value = module.security_groups.sg_ids
}
