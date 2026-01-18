###############################################################################
# CI/CD Module Variables
###############################################################################

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "enable_codedeploy" {
  description = "Enable CodeDeploy"
  type        = bool
  default     = true
}

variable "codedeploy_windows_app_name" {
  description = "CodeDeploy Windows application name"
  type        = string
}

variable "codedeploy_linux_app_name" {
  description = "CodeDeploy Linux application name"
  type        = string
}

variable "deployment_config_name" {
  description = "CodeDeploy deployment configuration"
  type        = string
  default     = "CodeDeployDefault.AllAtOnce"
}

variable "enable_auto_rollback" {
  description = "Enable automatic rollback on deployment failure"
  type        = bool
  default     = true
}

variable "enable_codepipeline" {
  description = "Enable CodePipeline"
  type        = bool
  default     = true
}

variable "source_repository" {
  description = "Source code repository URL"
  type        = string
  default     = ""
}

variable "source_branch" {
  description = "Source branch for deployments"
  type        = string
  default     = "main"
}

variable "artifact_bucket_name" {
  description = "S3 bucket name for artifacts"
  type        = string
  default     = ""
}

variable "app_target_group_name" {
  description = "App target group name for zero-downtime deployment"
  type        = string
  default     = ""
}

variable "api_target_group_name" {
  description = "API target group name for zero-downtime deployment"
  type        = string
  default     = ""
}

variable "botpress_target_group_name" {
  description = "Botpress target group name for zero-downtime deployment"
  type        = string
  default     = ""
}

#------------------------------------------------------------------------------
# ASG Integration for CodeDeploy
#------------------------------------------------------------------------------

variable "app_asg_name" {
  description = "App Auto Scaling Group name for CodeDeploy integration"
  type        = string
  default     = ""
}

variable "api_asg_name" {
  description = "API Auto Scaling Group name for CodeDeploy integration"
  type        = string
  default     = ""
}

variable "botpress_asg_name" {
  description = "Botpress Auto Scaling Group name for CodeDeploy integration"
  type        = string
  default     = ""
}

#------------------------------------------------------------------------------
# Client Deployment User
#------------------------------------------------------------------------------

variable "enable_client_deploy_user" {
  description = "Create IAM user for client deployment uploads"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "KMS key ARN for S3 encryption"
  type        = string
  default     = ""
}
