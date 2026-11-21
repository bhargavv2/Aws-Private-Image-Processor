output "raw_bucket_name" {
  description = "The globally unique name of the raw uploads S3 bucket"
  value       = aws_s3_bucket.raw.id
}

output "raw_bucket_arn" {
  description = "The ARN of the raw uploads S3 bucket"
  value       = aws_s3_bucket.raw.arn
}

output "processed_bucket_name" {
  description = "The globally unique name of the processed files S3 bucket"
  value       = aws_s3_bucket.processed.id
}

output "processed_bucket_arn" {
  description = "The ARN of the processed files S3 bucket"
  value       = aws_s3_bucket.processed.arn
}
