###############################################################################
# Security Module - Standalone Deployment
# State: s3://ajyal-preprod-terraform-state-946846709937-{ACCOUNT}/preprod/security/terraform.tfstate
# Depends on: 01-vpc
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
    key            = "preprod/security/terraform.tfstate"
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
      Module      = "security"
    }
  }
}

#------------------------------------------------------------------------------
# Remote State - VPC (dependency)
#------------------------------------------------------------------------------

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "ajyal-preprod-terraform-state-946846709937"
    key    = "preprod/vpc/terraform.tfstate"
    region = "eu-west-1"
  }
}

#------------------------------------------------------------------------------
# Security Module
#------------------------------------------------------------------------------

module "security" {
  source = "../../../modules/security"

  environment = var.environment
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id
  vpc_cidr    = data.terraform_remote_state.vpc.outputs.vpc_cidr

  enable_waf          = var.enable_waf
  enable_guardduty    = var.enable_guardduty
  enable_security_hub = var.enable_security_hub
  enable_config       = var.enable_config
  enable_trend_micro  = var.enable_trend_micro
  vpn_access_cidr_blocks = var.vpn_access_cidr_blocks

  waf_rate_limit = var.waf_rate_limit
  waf_block_mode = var.waf_block_mode

  # Integration NLB - allows public traffic on ports 80/443
  enable_integration_nlb = var.enable_integration_nlb
}

#------------------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------------------

output "kms_key_arn" {
  value = module.security.kms_key_arn
}

output "kms_key_id" {
  value = module.security.kms_key_id
}

output "waf_acl_arn" {
  value = module.security.waf_acl_arn
}

output "alb_security_group_id" {
  value = module.security.alb_security_group_id
}

output "windows_server_security_group_id" {
  value = module.security.windows_server_security_group_id
}

output "linux_server_security_group_id" {
  value = module.security.linux_server_security_group_id
}

output "integration_server_security_group_id" {
  description = "Integration server security group ID"
  value       = module.security.integration_server_security_group_id
}

output "database_security_group_id" {
  value = module.security.database_security_group_id
}

output "efs_security_group_id" {
  value = module.security.efs_security_group_id
}
