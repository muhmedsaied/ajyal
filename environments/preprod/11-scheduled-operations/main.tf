###############################################################################
# Scheduled Operations Module - Standalone Deployment
# State: s3://ajyal-preprod-terraform-state-946846709937/preprod/scheduled-operations/terraform.tfstate
#
# This module manages automatic stop/start of infrastructure to save costs:
# - Stop: 10 PM Jordan time (19:00 UTC) daily
# - Start: 7 AM Jordan time (04:00 UTC) daily
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
    key            = "preprod/scheduled-operations/terraform.tfstate"
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
      Module      = "scheduled-operations"
    }
  }
}

#------------------------------------------------------------------------------
# Scheduled Operations Module
#------------------------------------------------------------------------------

module "scheduled_operations" {
  source = "../../../modules/scheduled-operations"

  environment           = var.environment
  enable_schedule       = var.enable_schedule
  stop_cron_expression  = var.stop_cron_expression
  start_cron_expression = var.start_cron_expression

  tags = {
    Environment = var.environment
    Project     = "Ajyal-LMS"
    ManagedBy   = "Terraform"
    Team        = "Slashtec-DevOps"
    Module      = "scheduled-operations"
  }
}

#------------------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------------------

output "lambda_function_name" {
  description = "Name of the scheduled operations Lambda function"
  value       = module.scheduled_operations.lambda_function_name
}

output "lambda_function_arn" {
  description = "ARN of the scheduled operations Lambda function"
  value       = module.scheduled_operations.lambda_function_arn
}

output "stop_schedule" {
  description = "Stop schedule (UTC)"
  value       = module.scheduled_operations.stop_schedule
}

output "start_schedule" {
  description = "Start schedule (UTC)"
  value       = module.scheduled_operations.start_schedule
}
