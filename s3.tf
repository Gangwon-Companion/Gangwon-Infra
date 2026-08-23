resource "aws_s3_bucket" "community" {
  bucket = "${local.name}-community-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "community" {
  bucket = aws_s3_bucket.community.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "community" {
  bucket = aws_s3_bucket.community.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "community" {
  bucket = aws_s3_bucket.community.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

