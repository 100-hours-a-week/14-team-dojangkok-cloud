# ==============================================
# S3 Module (import 지원)
# Bucket + ownership controls + public access block
# ==============================================

resource "aws_s3_bucket" "this" {
  for_each = var.buckets

  bucket = each.value.name

  tags = {
    Name = each.value.name
  }
}

resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id

  block_public_acls       = lookup(each.value, "block_public_acls", true)
  block_public_policy     = lookup(each.value, "block_public_policy", true)
  ignore_public_acls      = lookup(each.value, "ignore_public_acls", true)
  restrict_public_buckets = lookup(each.value, "restrict_public_buckets", true)
}

# Versioning (optional)
resource "aws_s3_bucket_versioning" "this" {
  for_each = { for k, v in var.buckets : k => v if lookup(v, "versioning", false) }

  bucket = aws_s3_bucket.this[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}
