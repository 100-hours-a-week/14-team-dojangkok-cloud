# Networking
output "vpc_id" {
  value = module.networking.vpc_id
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.networking.private_subnet_ids
}

# NAT
output "nat_eip_public_ips" {
  value = module.nat_instance.eip_public_ips
}

# Compute
output "mysql_private_ip" {
  value = module.compute.private_ips["mysql"]
}

output "redis_private_ip" {
  value = module.compute.private_ips["redis"]
}

output "mq_private_ip" {
  value = module.compute.private_ips["mq"]
}

# ALB
output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

# NLB
output "nlb_dns_name" {
  value = module.nlb.nlb_dns_name
}

# ASG
output "fe_asg_name" {
  value = module.fe_asg.asg_name
}

output "be_asg_name" {
  value = module.be_asg.asg_name
}
