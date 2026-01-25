# 1. 일반 데이터 저장용 버킷
resource "aws_s3_bucket" "main" {
  bucket = "${var.project_name}-bucket"
  
  tags = {
    Name = "${var.project_name}-bucket"
  }
}

# ACL 비활성화 (권장 설정: BucketOwnerEnforced)
resource "aws_s3_bucket_ownership_controls" "main" {
  bucket = aws_s3_bucket.main.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 2. 배포 아티팩트 저장용 버킷
resource "aws_s3_bucket" "deploy" {
  bucket = "${var.project_name}-deploy"

  tags = {
    Name = "${var.project_name}-deploy"
  }
}

resource "aws_s3_bucket_ownership_controls" "deploy" {
  bucket = aws_s3_bucket.deploy.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "deploy" {
  bucket = aws_s3_bucket.deploy.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 3. MySQL 백업 파일 저장용 버킷
resource "aws_s3_bucket" "backup" {
  bucket = "${var.project_name}-mysql-backup"

  tags = {
    Name = "${var.project_name}-mysql-backup"
  }
}

resource "aws_s3_bucket_ownership_controls" "backup" {
  bucket = aws_s3_bucket.backup.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
