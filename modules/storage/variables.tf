###############################################################################
# Storage Module Variables
###############################################################################

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_id" {
  description = "Private subnet ID for EFS mount targets"
  type        = string
}

variable "security_group_ids" {
  description = "Security group IDs for EFS"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
}

# Content EFS
variable "enable_content_efs" {
  description = "Enable Content EFS"
  type        = bool
  default     = true
}

variable "content_efs_size_gb" {
  description = "Content EFS size in GB"
  type        = number
  default     = 30720
}

# ML EFS
variable "enable_ml_efs" {
  description = "Enable ML EFS"
  type        = bool
  default     = true
}

variable "ml_efs_size_gb" {
  description = "ML EFS size in GB"
  type        = number
  default     = 150
}

variable "efs_throughput_mode" {
  description = "EFS throughput mode"
  type        = string
  default     = "bursting"
}

# S3 Buckets
variable "enable_backup_bucket" {
  description = "Enable backup S3 bucket"
  type        = bool
  default     = true
}

variable "enable_logs_bucket" {
  description = "Enable logs S3 bucket"
  type        = bool
  default     = true
}

variable "s3_versioning_enabled" {
  description = "Enable S3 versioning"
  type        = bool
  default     = true
}

variable "enable_deployment_bucket" {
  description = "Enable S3 bucket for CodeDeploy artifacts"
  type        = bool
  default     = true
}
