# ------------------------------------------------------------------------------
# S3 Storage Module (Free Tier Compliant)
# Dual Bucket Architecture: Raw Ingestion & Processed Storage
# ------------------------------------------------------------------------------

resource "random_string" "bucket_suffix" {
  length  = 6
  special = false
  upper   = false
}

# 1. Raw Uploads Bucket (Input)
resource "aws_s3_bucket" "raw" {
  bucket        = "${var.project_name}-raw-${var.environment}-${random_string.bucket_suffix.result}"
  force_destroy = var.force_destroy

  tags = {
    Name        = "${var.project_name}-raw-uploads"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "Raw-Ingestion"
  }
}

# 2. Processed Files Bucket (Output)
resource "aws_s3_bucket" "processed" {
  bucket        = "${var.project_name}-processed-${var.environment}-${random_string.bucket_suffix.result}"
  force_destroy = var.force_destroy

  tags = {
    Name        = "${var.project_name}-processed-files"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "Processed-Output"
  }
}

# ------------------------------------------------------------------------------
# Server-Side Encryption (SSE-S3 / AES256) - Always Free
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "raw_crypto" {
  bucket = aws_s3_bucket.raw.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed_crypto" {
  bucket = aws_s3_bucket.processed.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ------------------------------------------------------------------------------
# Block All Public Access (Zero-Public Exposure Security Standard)
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "raw_block_public" {
  bucket = aws_s3_bucket.raw.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "processed_block_public" {
  bucket = aws_s3_bucket.processed.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# Cost-Optimized Lifecycle Rule for Processed Files
# - Moves to S3 Glacier after 30 days
# - Deletes permanently after 90 days
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "processed_lifecycle" {
  bucket = aws_s3_bucket.processed.id

  rule {
    id     = "archive-and-expire-lifecycle"
    status = "Enabled"

    filter {}

    transition {
      days          = var.glacier_transition_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.expiration_days
    }
  }
}
