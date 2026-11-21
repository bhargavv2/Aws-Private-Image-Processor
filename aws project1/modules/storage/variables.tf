variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "image-processor"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, prod)"
  type        = string
  default     = "dev"
}

variable "force_destroy" {
  description = "Whether to allow bucket deletion even if non-empty (useful for clean tear down in dev/testing)"
  type        = bool
  default     = true
}

variable "glacier_transition_days" {
  description = "Days after which processed files transition to S3 Glacier"
  type        = number
  default     = 30
}

variable "expiration_days" {
  description = "Days after which processed files are permanently deleted"
  type        = number
  default     = 90
}
