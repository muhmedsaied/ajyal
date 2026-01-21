###############################################################################
# DNS Module - Private Hosted Zone
# State: s3://ajyal-preprod-terraform-state-946846709937/preprod/dns/terraform.tfstate
# Depends on: 01-vpc, 04-database, 06-compute
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
    key            = "preprod/dns/terraform.tfstate"
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
      Module      = "dns"
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

data "terraform_remote_state" "compute" {
  backend = "s3"
  config = {
    bucket = "ajyal-preprod-terraform-state-946846709937"
    key    = "preprod/compute/terraform.tfstate"
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

data "aws_opensearch_domain" "main" {
  count       = try(data.terraform_remote_state.database.outputs.opensearch_domain_name, "") != "" ? 1 : 0
  domain_name = data.terraform_remote_state.database.outputs.opensearch_domain_name
}

locals {
  opensearch_endpoint = try(
    data.terraform_remote_state.database.outputs.opensearch_endpoint,
    ""
  ) != "" ? data.terraform_remote_state.database.outputs.opensearch_endpoint : try(
    data.aws_opensearch_domain.main[0].endpoint,
    ""
  )
}

#------------------------------------------------------------------------------
# DNS Module
#------------------------------------------------------------------------------

module "dns" {
  source = "../../../modules/dns"

  zone_name = var.zone_name
  vpc_id    = data.terraform_remote_state.vpc.outputs.vpc_id

  # Load Balancers
  api_alb_arn      = try(data.terraform_remote_state.compute.outputs.api_alb_arn, "")
  app_alb_arn      = try(data.terraform_remote_state.compute.outputs.app_alb_arn, "")
  botpress_alb_arn = try(data.terraform_remote_state.compute.outputs.botpress_alb_arn, "")

  # Databases
  mssql_endpoint         = try(data.terraform_remote_state.database.outputs.mssql_endpoint, "")
  aurora_endpoint        = try(data.terraform_remote_state.database.outputs.aurora_postgresql_endpoint, "")
  aurora_reader_endpoint = try(data.terraform_remote_state.database.outputs.aurora_postgresql_reader_endpoint, "")
  redis_endpoint         = try(data.terraform_remote_state.database.outputs.redis_endpoint, "")
  opensearch_endpoint    = local.opensearch_endpoint
  opensearch_domain_name = try(data.terraform_remote_state.database.outputs.opensearch_domain_name, "")

  # Services
  rabbitmq_private_ip = try(data.terraform_remote_state.compute.outputs.rabbitmq_private_ip, "")
}

output "zone_id" {
  value = module.dns.zone_id
}

output "zone_name" {
  value = module.dns.zone_name
}

output "alb_record_fqdns" {
  value = module.dns.alb_record_fqdns
}

output "db_record_fqdns" {
  value = module.dns.db_record_fqdns
}

output "rabbitmq_fqdn" {
  value = module.dns.rabbitmq_fqdn
}

#------------------------------------------------------------------------------
# Internal DNS Names for Service Configuration
#------------------------------------------------------------------------------

output "api_dns_name" {
  description = "Internal DNS name for API ALB (api.lms.internal)"
  value       = module.dns.api_dns_name
}

output "app_dns_name" {
  description = "Internal DNS name for App ALB (app.lms.internal)"
  value       = module.dns.app_dns_name
}

output "botpress_dns_name" {
  description = "Internal DNS name for Botpress ALB (botpress.lms.internal)"
  value       = module.dns.botpress_dns_name
}

output "mssql_dns_name" {
  description = "Internal DNS name for MSSQL (mssql.lms.internal)"
  value       = module.dns.mssql_dns_name
}

output "aurora_dns_name" {
  description = "Internal DNS name for Aurora PostgreSQL writer (aurora.lms.internal)"
  value       = module.dns.aurora_dns_name
}

output "aurora_reader_dns_name" {
  description = "Internal DNS name for Aurora PostgreSQL reader (aurora_ro.lms.internal)"
  value       = module.dns.aurora_reader_dns_name
}

output "redis_dns_name" {
  description = "Internal DNS name for Redis (redis.lms.internal)"
  value       = module.dns.redis_dns_name
}

output "opensearch_dns_name" {
  description = "Internal DNS name for OpenSearch (opensearch.lms.internal)"
  value       = module.dns.opensearch_dns_name
}

output "rabbitmq_dns_name" {
  description = "Internal DNS name for RabbitMQ (rabbitmq.lms.internal)"
  value       = module.dns.rabbitmq_dns_name
}
