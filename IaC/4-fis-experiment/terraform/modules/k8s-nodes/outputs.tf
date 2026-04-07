output "control_plane" {
  value = {
    id         = aws_instance.control_plane.id
    private_ip = aws_instance.control_plane.private_ip
    public_ip  = aws_instance.control_plane.public_ip
  }
}

output "workers" {
  value = {
    for k, v in aws_instance.workers : k => {
      id         = v.id
      private_ip = v.private_ip
      public_ip  = v.public_ip
      az         = local.worker_instances[k].az
    }
  }
}

output "worker_instance_ids" {
  value = { for k, v in aws_instance.workers : k => v.id }
}
