output "repository_id" {
  description = "Artifact Registry 저장소 ID"
  value       = google_artifact_registry_repository.this.repository_id
}

output "repository_url" {
  description = "Docker 이미지 push/pull URL (예: asia-northeast3-docker.pkg.dev/{project}/{repo})"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.this.repository_id}"
}
