###############################################################################
# CI/CD Module - Standalone Deployment (CodeDeploy, CodePipeline)
# State: s3://ajyal-preprod-terraform-state-946846709937-{ACCOUNT}/preprod/cicd/terraform.tfstate
# Depends on: 03-storage
#
# FAST DEPLOYMENT: CodeDeploy pulls artifacts from S3 in same region
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket         = "ajyal-preprod-terraform-state-946846709937"
    key            = "preprod/cicd/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "preprod-ajyal-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "Ajyal-LMS"
      ManagedBy   = "Terraform"
      Team        = "Slashtec-DevOps"
      Module      = "cicd"
    }
  }
}

#------------------------------------------------------------------------------
# Remote State - Dependencies
#------------------------------------------------------------------------------

data "terraform_remote_state" "storage" {
  backend = "s3"
  config = {
    bucket = "ajyal-preprod-terraform-state-946846709937"
    key    = "preprod/storage/terraform.tfstate"
    region = "eu-west-1"
  }
}

#------------------------------------------------------------------------------
# CI/CD Module
#------------------------------------------------------------------------------

data "terraform_remote_state" "security" {
  backend = "s3"
  config = {
    bucket = "ajyal-preprod-terraform-state-946846709937"
    key    = "preprod/security/terraform.tfstate"
    region = "eu-west-1"
  }
}

data "terraform_remote_state" "compute" {
  backend = "s3"
  config = {
    bucket = "ajyal-preprod-terraform-state-946846709937"
    key    = "preprod/compute/terraform.tfstate"
    region = "eu-west-1"
  }
}

module "cicd" {
  source = "../../../modules/cicd"

  environment = var.environment

  # CodeDeploy
  enable_codedeploy             = var.enable_codedeploy
  enable_codedeploy_per_service = var.enable_codedeploy_per_service
  codedeploy_windows_app_name   = "${var.environment}-windows-app"
  codedeploy_linux_app_name     = "${var.environment}-linux-app"

  # FAST DEPLOYMENT CONFIG
  deployment_config_name = var.deployment_config_name # AllAtOnce = fastest
  enable_auto_rollback   = var.enable_auto_rollback

  # CodePipeline
  enable_codepipeline = var.enable_codepipeline
  source_repository   = var.source_repository
  source_branch       = var.source_branch

  # S3 Deployment Bucket (same region for fast access)
  artifact_bucket_name = data.terraform_remote_state.storage.outputs.deployment_bucket_name

  # KMS Key for encryption
  kms_key_arn = data.terraform_remote_state.security.outputs.kms_key_arn

  # Zero-Downtime Deployment - ALB Target Groups
  # (Set these after deploying compute module for zero-downtime deployments)
  app_target_group_name      = var.app_target_group_name != "" ? var.app_target_group_name : try(data.terraform_remote_state.compute.outputs.app_target_group_name, "")
  api_target_group_name      = var.api_target_group_name != "" ? var.api_target_group_name : try(data.terraform_remote_state.compute.outputs.api_target_group_name, "")
  botpress_target_group_name = var.botpress_target_group_name

  # ASG Integration for CodeDeploy
  app_asg_name         = var.app_asg_name != "" ? var.app_asg_name : data.terraform_remote_state.compute.outputs.app_asg_name
  api_asg_name         = var.api_asg_name != "" ? var.api_asg_name : data.terraform_remote_state.compute.outputs.api_asg_name
  integration_asg_name = var.integration_asg_name != "" ? var.integration_asg_name : data.terraform_remote_state.compute.outputs.integration_asg_name
  botpress_asg_name    = var.botpress_asg_name != "" ? var.botpress_asg_name : data.terraform_remote_state.compute.outputs.botpress_asg_name

  # Client Deployment User
  enable_client_deploy_user = var.enable_client_deploy_user

  # CodeDeploy Bundler (S3 -> CodeDeploy-ready packages)
  enable_codedeploy_bundler              = var.enable_codedeploy_bundler
  codedeploy_bundler_auto_deploy          = var.codedeploy_bundler_auto_deploy
  codedeploy_bundler_lambda_storage       = var.codedeploy_bundler_lambda_storage
  codedeploy_bundler_api_allowed_names    = var.codedeploy_bundler_api_allowed_names
  codedeploy_bundler_integration_allowed_names = var.codedeploy_bundler_integration_allowed_names
  codedeploy_bundler_app_allowed_names    = var.codedeploy_bundler_app_allowed_names
  codedeploy_bundler_ssm_kms_key_id        = var.codedeploy_bundler_ssm_kms_key_id
}

#------------------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------------------

output "instance_profile_name" {
  value = module.cicd.instance_profile_name
}

output "instance_profile_arn" {
  value = module.cicd.instance_profile_arn
}

output "ec2_role_arn" {
  value = module.cicd.ec2_role_arn
}

output "codedeploy_windows_app_name" {
  value = module.cicd.codedeploy_windows_app_name
}

output "codedeploy_linux_app_name" {
  value = module.cicd.codedeploy_linux_app_name
}

output "codedeploy_role_arn" {
  value = module.cicd.codedeploy_role_arn
}

#------------------------------------------------------------------------------
# Client Deployment Outputs
#------------------------------------------------------------------------------

output "deployment_bucket_name" {
  description = "S3 bucket for deployment artifacts"
  value       = data.terraform_remote_state.storage.outputs.deployment_bucket_name
}

output "client_deploy_user_name" {
  description = "Client deployment IAM user name"
  value       = module.cicd.client_deploy_user_name
}

output "client_deploy_user_arn" {
  description = "Client deployment IAM user ARN"
  value       = module.cicd.client_deploy_user_arn
}

output "client_deploy_policy_arn" {
  description = "Client deployment IAM policy ARN"
  value       = module.cicd.client_deploy_policy_arn
}
