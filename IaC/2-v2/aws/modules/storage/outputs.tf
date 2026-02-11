output "s3_bucket_ids" {
  description = "S3 버킷 ID 맵"
  value       = { for k, v in aws_s3_bucket.this : k => v.id }
}

output "s3_bucket_arns" {
  description = "S3 버킷 ARN 맵"
  value       = { for k, v in aws_s3_bucket.this : k => v.arn }
}

output "ecr_repository_urls" {
  description = "ECR 리포지토리 URL 맵"
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "ecr_repository_arns" {
  description = "ECR 리포지토리 ARN 맵"
  value       = { for k, v in aws_ecr_repository.this : k => v.arn }
}
