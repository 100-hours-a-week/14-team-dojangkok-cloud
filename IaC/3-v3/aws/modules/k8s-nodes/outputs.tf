# ============================================================
# V3 K8S IaC — K8S Nodes Outputs
# ============================================================

output "control_plane" {
  description = "CP 인스턴스 정보"
  value = {
    id         = aws_instance.control_plane.id
    private_ip = aws_instance.control_plane.private_ip
  }
}

output "workers" {
  description = "Worker 인스턴스 맵 (이름 → {id, private_ip, az})"
  value = {
    for k, v in aws_instance.workers : k => {
      id         = v.id
      private_ip = v.private_ip
      az         = local.worker_instances[k].az
    }
  }
}

output "worker_instance_ids" {
  description = "Worker 인스턴스 ID 목록 (ALB TG 등록용)"
  value       = [for v in aws_instance.workers : v.id]
}

output "all_instance_ids" {
  description = "전체 노드(CP + Worker) ID 목록"
  value       = concat([aws_instance.control_plane.id], [for v in aws_instance.workers : v.id])
}
