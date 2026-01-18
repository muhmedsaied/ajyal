###############################################################################
# CI/CD Module Variables - Fast Deployment Configuration
###############################################################################

variable "environment" {
  default = "preprod"
}

variable "aws_region" {
  default = "eu-west-1"
}

variable "enable_codedeploy" {
  default = true
}

variable "enable_codepipeline" {
  default = true
}

# FAST DEPLOYMENT OPTIONS:
# - CodeDeployDefault.AllAtOnce     = Deploy to ALL instances simultaneously (FASTEST)
# - CodeDeployDefault.HalfAtATime   = Deploy to 50% at a time
# - CodeDeployDefault.OneAtATime    = Deploy one instance at a time (slowest but safest)
variable "deployment_config_name" {
  description = "CodeDeploy deployment configuration - AllAtOnce is fastest"
  default     = "CodeDeployDefault.AllAtOnce"
}

variable "enable_auto_rollback" {
  default = true
}

variable "source_repository" {
  default = ""
}

variable "source_branch" {
  default = "preprod"
}

#------------------------------------------------------------------------------
# ZERO-DOWNTIME DEPLOYMENT - ALB Target Group Integration
#
# After deploying 06-compute, update these values with the actual names:
#   terraform apply -var="app_target_group_name=preprod-ajyal-windows-app-tg"
#
# This enables CodeDeploy to remove instances from ALB during deployment
#------------------------------------------------------------------------------

variable "app_target_group_name" {
  description = "Windows App target group name (from compute module)"
  default     = "" # Set after compute deployment for zero-downtime
}

variable "api_target_group_name" {
  description = "Windows API target group name (from compute module)"
  default     = "" # Set after compute deployment for zero-downtime
}

variable "botpress_target_group_name" {
  description = "Linux Botpress target group name (from compute module)"
  default     = "" # Set after compute deployment for zero-downtime
}

#------------------------------------------------------------------------------
# ASG Integration for CodeDeploy
#
# When ASG is configured, CodeDeploy automatically:
# 1. Deploys to new instances launched by ASG
# 2. Waits for instances to pass health checks
# 3. Handles scale-in/scale-out during deployments
#------------------------------------------------------------------------------

variable "app_asg_name" {
  description = "Windows App Auto Scaling Group name"
  default     = "" # Set after compute deployment
}

variable "api_asg_name" {
  description = "Windows API Auto Scaling Group name"
  default     = "" # Set after compute deployment
}

variable "botpress_asg_name" {
  description = "Linux Botpress Auto Scaling Group name"
  default     = "" # Set after compute deployment
}

#------------------------------------------------------------------------------
# Client Deployment User
#------------------------------------------------------------------------------

variable "enable_client_deploy_user" {
  description = "Create IAM user for client to upload deployment artifacts"
  default     = true
}
