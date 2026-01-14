###############################################################################
# Storage Module Variables
###############################################################################

variable "environment" {
  default = "preprod"
}

variable "aws_region" {
  default = "eu-west-1"
}

variable "enable_content_efs" {
  default = true
}

variable "enable_ml_efs" {
  default = true
}

variable "content_efs_size_gb" {
  default = 1024 # 1TB for preprod
}

variable "ml_efs_size_gb" {
  default = 50
}

variable "efs_throughput_mode" {
  default = "bursting"
}

variable "enable_backup_bucket" {
  default = true
}

variable "enable_logs_bucket" {
  default = true
}

variable "s3_versioning_enabled" {
  default = true
}

variable "enable_deployment_bucket" {
  description = "Enable S3 bucket for CodeDeploy artifacts"
  default     = true
}
