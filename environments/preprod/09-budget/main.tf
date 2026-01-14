###############################################################################
# Budget Module - Standalone Deployment
# State: s3://ajyal-preprod-terraform-state-946846709937/preprod/budget/terraform.tfstate
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
    key            = "preprod/budget/terraform.tfstate"
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
      Module      = "budget"
    }
  }
}

#------------------------------------------------------------------------------
# Budget Module
#------------------------------------------------------------------------------

module "budget" {
  source = "../../../modules/budget"

  environment   = var.environment
  budget_limit  = var.budget_limit
  alert_emails  = var.alert_emails
}

#------------------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------------------

output "budget_name" {
  description = "Budget name"
  value       = module.budget.budget_name
}

output "budget_limit" {
  description = "Budget limit"
  value       = module.budget.budget_limit
}
