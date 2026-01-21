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

variable "enable_codedeploy_per_service" {
  description = "Use per-service CodeDeploy apps for Windows API/Integration"
  type        = bool
  default     = false
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

variable "integration_asg_name" {
  description = "Integration Auto Scaling Group name for CodeDeploy integration"
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

#------------------------------------------------------------------------------
# CodeDeploy Bundler (S3 -> CodeDeploy-ready packages)
#------------------------------------------------------------------------------

variable "enable_codedeploy_bundler" {
  description = "Enable S3-triggered CodeDeploy bundle creation for Windows apps"
  type        = bool
  default     = false
}

variable "codedeploy_bundler_auto_deploy" {
  description = "Automatically trigger CodeDeploy after bundling"
  type        = bool
  default     = true
}

variable "codedeploy_bundler_ssm_kms_key_id" {
  description = "Optional KMS key ID for SSM SecureString parameters"
  type        = string
  default     = ""
}

variable "codedeploy_bundler_api_prefix" {
  description = "S3 prefix for raw API uploads"
  type        = string
  default     = "windows/api/"
}

variable "codedeploy_bundler_integration_prefix" {
  description = "S3 prefix for raw Integration uploads"
  type        = string
  default     = "windows/integration/"
}

variable "codedeploy_bundler_app_prefix" {
  description = "S3 prefix for raw App uploads"
  type        = string
  default     = "windows/app/"
}

variable "codedeploy_bundler_api_output_prefix" {
  description = "S3 prefix for CodeDeploy-ready API bundles"
  type        = string
  default     = "codedeploy/windows/api/"
}

variable "codedeploy_bundler_integration_output_prefix" {
  description = "S3 prefix for CodeDeploy-ready Integration bundles"
  type        = string
  default     = "codedeploy/windows/integration/"
}

variable "codedeploy_bundler_app_output_prefix" {
  description = "S3 prefix for CodeDeploy-ready App bundles"
  type        = string
  default     = "codedeploy/windows/app/"
}

variable "codedeploy_bundler_api_allowed_names" {
  description = "Optional allowed base filename patterns (glob) for API uploads"
  type        = list(string)
  default     = []
}

variable "codedeploy_bundler_integration_allowed_names" {
  description = "Optional allowed base filename patterns (glob) for Integration uploads"
  type        = list(string)
  default     = []
}

variable "codedeploy_bundler_app_allowed_names" {
  description = "Optional allowed base filename patterns (glob) for App uploads"
  type        = list(string)
  default     = []
}

variable "codedeploy_bundler_lambda_timeout" {
  description = "Lambda timeout (seconds) for bundling"
  type        = number
  default     = 300
}

variable "codedeploy_bundler_lambda_memory" {
  description = "Lambda memory size (MB) for bundling"
  type        = number
  default     = 512
}

variable "codedeploy_bundler_lambda_storage" {
  description = "Lambda /tmp storage size (MB) for bundling"
  type        = number
  default     = 2048
}

variable "codedeploy_bundler_log_retention_days" {
  description = "CloudWatch log retention for bundler Lambda"
  type        = number
  default     = 14
}
