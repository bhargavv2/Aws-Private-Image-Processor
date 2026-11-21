variable "aws_region" {
  description = "AWS Region to deploy resources into (e.g. us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Base name for all project resources"
  type        = string
  default     = "image-processor"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the custom VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the isolated private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "instance_type" {
  description = "EC2 instance type (Free Tier eligible: t3.micro or t2.micro)"
  type        = string
  default     = "t3.micro"
}

variable "glacier_transition_days" {
  description = "Days before transitioning processed files to S3 Glacier"
  type        = number
  default     = 30
}

variable "expiration_days" {
  description = "Days before permanently deleting expired processed files"
  type        = number
  default     = 90
}
