###############################################################################
# Storage Module - Standalone Deployment
# State: s3://ajyal-preprod-terraform-state-946846709937-{ACCOUNT}/preprod/storage/terraform.tfstate
# Depends on: 01-vpc, 02-security
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "ajyal-preprod-terraform-state-946846709937"
    key            = "preprod/storage/terraform.tfstate"
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
      Module      = "storage"
    }
  }
}

#------------------------------------------------------------------------------
# Remote State - Dependencies
#------------------------------------------------------------------------------

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "ajyal-preprod-terraform-state-946846709937"
    key    = "preprod/vpc/terraform.tfstate"
    region = "eu-west-1"
  }
}

data "terraform_remote_state" "security" {
  backend = "s3"
  config = {
    bucket = "ajyal-preprod-terraform-state-946846709937"
    key    = "preprod/security/terraform.tfstate"
    region = "eu-west-1"
  }
}

#------------------------------------------------------------------------------
# Storage Module
#------------------------------------------------------------------------------

module "storage" {
  source = "../../../modules/storage"

  environment       = var.environment
  vpc_id            = data.terraform_remote_state.vpc.outputs.vpc_id
  private_subnet_id = data.terraform_remote_state.vpc.outputs.private_data_subnet_id

  enable_content_efs  = var.enable_content_efs
  enable_ml_efs       = var.enable_ml_efs
  content_efs_size_gb = var.content_efs_size_gb
  ml_efs_size_gb      = var.ml_efs_size_gb
  efs_throughput_mode = var.efs_throughput_mode

  enable_backup_bucket     = var.enable_backup_bucket
  enable_logs_bucket       = var.enable_logs_bucket
  enable_deployment_bucket = var.enable_deployment_bucket
  s3_versioning_enabled    = var.s3_versioning_enabled

  kms_key_arn        = data.terraform_remote_state.security.outputs.kms_key_arn
  security_group_ids = [data.terraform_remote_state.security.outputs.efs_security_group_id]
}

#------------------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------------------

output "content_efs_id" {
  value = module.storage.content_efs_id
}

output "content_efs_dns_name" {
  value = module.storage.content_efs_dns_name
}

output "ml_efs_id" {
  value = module.storage.ml_efs_id
}

output "ml_efs_dns_name" {
  value = module.storage.ml_efs_dns_name
}

output "backup_bucket_name" {
  value = module.storage.backup_bucket_name
}

output "backup_bucket_arn" {
  value = module.storage.backup_bucket_arn
}

output "logs_bucket_name" {
  value = module.storage.logs_bucket_name
}

output "artifact_bucket_name" {
  value = module.storage.artifact_bucket_name
}

output "deployment_bucket_name" {
  description = "CodeDeploy deployment bucket name"
  value       = module.storage.deployment_bucket_name
}

output "deployment_bucket_arn" {
  description = "CodeDeploy deployment bucket ARN"
  value       = module.storage.deployment_bucket_arn
}
