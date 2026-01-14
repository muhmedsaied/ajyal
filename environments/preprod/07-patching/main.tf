###############################################################################
# Patching Module - Standalone Deployment (SSM Patch Manager)
# State: s3://ajyal-preprod-terraform-state-946846709937-{ACCOUNT}/preprod/patching/terraform.tfstate
# Depends on: None (uses tags to identify instances)
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
    key            = "preprod/patching/terraform.tfstate"
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
      Module      = "patching"
    }
  }
}

#------------------------------------------------------------------------------
# Patching Module
#------------------------------------------------------------------------------

module "patching" {
  source = "../../../modules/patching"

  environment = var.environment

  # Master toggle
  enable_patching = var.enable_patching

  # Windows patching
  enable_windows_patching             = var.enable_windows_patching
  windows_patch_schedule              = var.windows_patch_schedule
  windows_patch_baseline              = var.windows_patch_baseline
  windows_maintenance_window_duration = var.windows_maintenance_window_duration

  # Linux patching
  enable_linux_patching             = var.enable_linux_patching
  linux_patch_schedule              = var.linux_patch_schedule
  linux_patch_baseline              = var.linux_patch_baseline
  linux_maintenance_window_duration = var.linux_maintenance_window_duration

  # Compliance
  enable_patch_compliance = var.enable_patch_compliance
  compliance_severity     = var.compliance_severity
  auto_approve_after_days = var.auto_approve_after_days

  # Notifications
  enable_patch_notifications = var.enable_patch_notifications
  notification_email         = var.notification_email
}

#------------------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------------------

output "windows_patch_baseline_id" {
  value = module.patching.windows_patch_baseline_id
}

output "linux_patch_baseline_id" {
  value = module.patching.linux_patch_baseline_id
}

output "windows_patch_group" {
  value = module.patching.windows_patch_group
}

output "linux_patch_group" {
  value = module.patching.linux_patch_group
}

output "windows_maintenance_window_id" {
  value = module.patching.windows_maintenance_window_id
}

output "linux_maintenance_window_id" {
  value = module.patching.linux_maintenance_window_id
}
