variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "image-processor"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "vpc_id" {
  description = "VPC ID where worker security group will be created"
  type        = string
}

variable "private_subnet_id" {
  description = "Private Subnet ID where the worker EC2 ASG will run"
  type        = string
}

variable "raw_bucket_name" {
  description = "Name of the raw ingestion S3 bucket"
  type        = string
}

variable "raw_bucket_arn" {
  description = "ARN of the raw ingestion S3 bucket"
  type        = string
}

variable "processed_bucket_name" {
  description = "Name of the processed output S3 bucket"
  type        = string
}

variable "processed_bucket_arn" {
  description = "ARN of the processed output S3 bucket"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (Free Tier eligible: t3.micro)"
  type        = string
  default     = "t3.micro"
}
