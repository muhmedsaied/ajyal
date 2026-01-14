###############################################################################
# Monitoring Module - Standalone Deployment (CloudWatch, CloudTrail)
# State: s3://ajyal-preprod-terraform-state-946846709937-{ACCOUNT}/preprod/monitoring/terraform.tfstate
# Depends on: 03-storage
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
    key            = "preprod/monitoring/terraform.tfstate"
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
      Module      = "monitoring"
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

data "terraform_remote_state" "database" {
  backend = "s3"
  config = {
    bucket = "ajyal-preprod-terraform-state-946846709937"
    key    = "preprod/database/terraform.tfstate"
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

#------------------------------------------------------------------------------
# Monitoring Module
#------------------------------------------------------------------------------

module "monitoring" {
  source = "../../../modules/monitoring"

  environment = var.environment

  # CloudWatch
  enable_cloudwatch_alarms     = var.enable_cloudwatch_alarms
  enable_cloudwatch_dashboards = var.enable_cloudwatch_dashboards

  # CloudTrail
  enable_cloudtrail      = var.enable_cloudtrail
  cloudtrail_bucket_name = data.terraform_remote_state.storage.outputs.logs_bucket_name

  # Log retention
  log_retention_days = var.log_retention_days

  # Alarms
  alarm_emails     = var.alarm_emails
  cpu_threshold    = var.cpu_threshold
  memory_threshold = var.memory_threshold
  disk_threshold   = var.disk_threshold

  # SIEM
  enable_siem_integration = var.enable_siem_integration
  siem_sqs_queue_name     = var.siem_sqs_queue_name

  #----------------------------------------------------------------------------
  # Per-Resource Monitoring (from remote state)
  #----------------------------------------------------------------------------

  # ASG Names
  app_asg_name = try(data.terraform_remote_state.compute.outputs.app_asg_name, "")
  api_asg_name = try(data.terraform_remote_state.compute.outputs.api_asg_name, "")

  # ALB ARN Suffixes
  app_alb_arn_suffix = try(data.terraform_remote_state.compute.outputs.app_alb_arn_suffix, "")
  api_alb_arn_suffix = try(data.terraform_remote_state.compute.outputs.api_alb_arn_suffix, "")

  # Target Group ARN Suffixes
  app_target_group_arn_suffix = try(data.terraform_remote_state.compute.outputs.app_target_group_arn_suffix, "")
  api_target_group_arn_suffix = try(data.terraform_remote_state.compute.outputs.api_target_group_arn_suffix, "")

  # Database Identifiers
  aurora_cluster_id      = try(data.terraform_remote_state.database.outputs.aurora_cluster_id, "")
  mssql_instance_id      = try(data.terraform_remote_state.database.outputs.mssql_instance_id, "")
  opensearch_domain_name = try(data.terraform_remote_state.database.outputs.opensearch_domain_name, "")

  # ElastiCache
  redis_cluster_id = try(data.terraform_remote_state.database.outputs.redis_cluster_id, "")

  # EFS
  efs_file_system_id = try(data.terraform_remote_state.storage.outputs.content_efs_id, "")

  # Thresholds
  db_connections_threshold      = var.db_connections_threshold
  aurora_max_capacity_threshold = var.aurora_max_capacity_threshold
}

#------------------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------------------

output "alarm_sns_topic_arn" {
  value = module.monitoring.alarm_sns_topic_arn
}

output "application_log_group" {
  value = module.monitoring.application_log_group
}

output "windows_log_group" {
  value = module.monitoring.windows_log_group
}

output "linux_log_group" {
  value = module.monitoring.linux_log_group
}

output "dashboard_name" {
  value = module.monitoring.dashboard_name
}

output "cloudtrail_arn" {
  value = module.monitoring.cloudtrail_arn
}
