###############################################################################
# Database Module - Standalone Deployment (RDS, OpenSearch, Redis)
# State: s3://ajyal-preprod-terraform-state-946846709937-{ACCOUNT}/preprod/database/terraform.tfstate
# Depends on: 01-vpc, 02-security
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket         = "ajyal-preprod-terraform-state-946846709937"
    key            = "preprod/database/terraform.tfstate"
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
      Module      = "database"
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
# Database Module
#------------------------------------------------------------------------------

module "database" {
  source = "../../../modules/database"

  environment        = var.environment
  vpc_id             = data.terraform_remote_state.vpc.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.vpc.outputs.private_data_subnet_ids

  # MS SQL Server
  enable_mssql                = var.enable_mssql
  mssql_instance_class        = var.mssql_instance_class
  mssql_allocated_storage     = var.mssql_allocated_storage
  mssql_max_allocated_storage = var.mssql_max_allocated_storage # Auto-scales to 200GB
  mssql_multi_az              = false

  # Aurora PostgreSQL (Serverless v2)
  enable_postgresql   = var.enable_postgresql
  aurora_min_capacity = var.aurora_min_capacity
  aurora_max_capacity = var.aurora_max_capacity

  # OpenSearch
  enable_opensearch         = var.enable_opensearch
  opensearch_instance_type  = var.opensearch_instance_type
  opensearch_instance_count = var.opensearch_instance_count
  opensearch_volume_size    = var.opensearch_volume_size

  # Redis
  enable_redis          = var.enable_redis
  redis_node_type       = var.redis_node_type
  redis_num_cache_nodes = var.redis_num_cache_nodes

  # Security
  kms_key_arn          = data.terraform_remote_state.security.outputs.kms_key_arn
  db_security_group_id = data.terraform_remote_state.security.outputs.database_security_group_id

  backup_retention_period    = var.backup_retention_period
  enable_deletion_protection = var.enable_deletion_protection
}

#------------------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------------------

output "mssql_endpoint" {
  value     = module.database.mssql_endpoint
  sensitive = true
}

output "mssql_secret_arn" {
  value = module.database.mssql_secret_arn
}

output "aurora_postgresql_endpoint" {
  value     = module.database.aurora_postgresql_endpoint
  sensitive = true
}

output "aurora_postgresql_reader_endpoint" {
  value     = module.database.aurora_postgresql_reader_endpoint
  sensitive = true
}

output "aurora_postgresql_secret_arn" {
  value = module.database.aurora_postgresql_secret_arn
}

output "opensearch_endpoint" {
  value     = module.database.opensearch_endpoint
  sensitive = true
}

output "redis_endpoint" {
  value     = module.database.redis_endpoint
  sensitive = true
}

output "redis_secret_arn" {
  value = module.database.redis_secret_arn
}

#------------------------------------------------------------------------------
# Outputs for Monitoring
#------------------------------------------------------------------------------

output "aurora_cluster_id" {
  description = "Aurora PostgreSQL cluster identifier for monitoring"
  value       = module.database.aurora_cluster_id
}

output "mssql_instance_id" {
  description = "MSSQL RDS instance identifier for monitoring"
  value       = module.database.mssql_instance_id
}

output "opensearch_domain_name" {
  description = "OpenSearch domain name for monitoring"
  value       = module.database.opensearch_domain_name
}

output "redis_cluster_id" {
  description = "Redis cluster ID for monitoring"
  value       = module.database.redis_cluster_id
}
