###############################################################################
# Compute Module - Standalone Deployment (EC2, ASG, ALB)
# State: s3://ajyal-preprod-terraform-state-946846709937-{ACCOUNT}/preprod/compute/terraform.tfstate
# Depends on: 01-vpc, 02-security, 03-storage, 05-cicd
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
    key            = "preprod/compute/terraform.tfstate"
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
      Module      = "compute"
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

data "terraform_remote_state" "storage" {
  backend = "s3"
  config = {
    bucket = "ajyal-preprod-terraform-state-946846709937"
    key    = "preprod/storage/terraform.tfstate"
    region = "eu-west-1"
  }
}

data "terraform_remote_state" "cicd" {
  backend = "s3"
  config = {
    bucket = "ajyal-preprod-terraform-state-946846709937"
    key    = "preprod/cicd/terraform.tfstate"
    region = "eu-west-1"
  }
}

#------------------------------------------------------------------------------
# Compute Module
#------------------------------------------------------------------------------

module "compute" {
  source = "../../../modules/compute"

  environment = var.environment
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  # Subnets
  public_subnet_id       = data.terraform_remote_state.vpc.outputs.public_subnet_id
  public_subnet_ids      = data.terraform_remote_state.vpc.outputs.public_subnet_ids
  private_web_subnet_id  = data.terraform_remote_state.vpc.outputs.private_web_subnet_id
  private_app_subnet_id  = data.terraform_remote_state.vpc.outputs.private_app_subnet_id
  private_app_subnet_ids = data.terraform_remote_state.vpc.outputs.private_app_subnet_ids

  # Security Groups
  windows_security_group_id = data.terraform_remote_state.security.outputs.windows_server_security_group_id
  linux_security_group_id   = data.terraform_remote_state.security.outputs.linux_server_security_group_id
  alb_security_group_id     = data.terraform_remote_state.security.outputs.alb_security_group_id

  # IAM
  instance_profile_name = data.terraform_remote_state.cicd.outputs.instance_profile_name

  # Encryption
  kms_key_arn = data.terraform_remote_state.security.outputs.kms_key_arn

  # EFS
  content_efs_id = var.enable_content_servers ? data.terraform_remote_state.storage.outputs.content_efs_id : ""
  ml_efs_id      = var.enable_ml_servers ? data.terraform_remote_state.storage.outputs.ml_efs_id : ""

  # CodeDeploy
  enable_codedeploy = var.enable_codedeploy

  # Windows Servers
  enable_app_servers       = var.enable_app_servers
  app_server_instance_type = var.app_server_instance_type
  app_server_min_size      = var.app_server_min_size
  app_server_max_size      = var.app_server_max_size
  app_server_desired_size  = var.app_server_desired_size

  enable_api_servers       = var.enable_api_servers
  api_server_instance_type = var.api_server_instance_type
  api_server_min_size      = var.api_server_min_size
  api_server_max_size      = var.api_server_max_size

  enable_integration_servers       = var.enable_integration_servers
  integration_server_instance_type = var.integration_server_instance_type
  integration_server_min_size      = var.integration_server_min_size
  integration_server_max_size      = var.integration_server_max_size

  enable_logging_servers       = var.enable_logging_servers
  logging_server_instance_type = var.logging_server_instance_type
  logging_server_min_size      = var.logging_server_min_size
  logging_server_max_size      = var.logging_server_max_size

  # Linux Servers
  # RabbitMQ - Single instance (no ASG, no CodeDeploy)
  enable_rabbitmq_servers = var.enable_rabbitmq_servers
  rabbitmq_instance_type  = var.rabbitmq_instance_type

  enable_botpress_servers = var.enable_botpress_servers
  botpress_instance_type  = var.botpress_instance_type
  botpress_min_size       = var.botpress_min_size
  botpress_max_size       = var.botpress_max_size

  enable_ml_servers       = var.enable_ml_servers
  ml_server_instance_type = var.ml_server_instance_type
  ml_server_min_size      = var.ml_server_min_size
  ml_server_max_size      = var.ml_server_max_size

  enable_content_servers       = var.enable_content_servers
  content_server_instance_type = var.content_server_instance_type
  content_server_min_size      = var.content_server_min_size
  content_server_max_size      = var.content_server_max_size

  # CloudFront CDN
  enable_cloudfront      = var.enable_cloudfront
  cloudfront_price_class = var.cloudfront_price_class
  waf_web_acl_arn        = "" # WAF is regional, CloudFront needs global WAF
}

#------------------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------------------

output "app_alb_dns_name" {
  value = module.compute.app_alb_dns_name
}

output "api_alb_dns_name" {
  value = module.compute.api_alb_dns_name
}

output "botpress_alb_dns_name" {
  value = module.compute.botpress_alb_dns_name
}

output "app_asg_name" {
  value = module.compute.app_asg_name
}

output "api_asg_name" {
  value = module.compute.api_asg_name
}

output "integration_asg_name" {
  description = "Integration ASG name"
  value       = module.compute.integration_asg_name
}

output "logging_asg_name" {
  description = "Logging ASG name"
  value       = module.compute.logging_asg_name
}

output "botpress_asg_name" {
  description = "Botpress ASG name"
  value       = module.compute.botpress_asg_name
}

output "ml_asg_name" {
  description = "ML ASG name"
  value       = module.compute.ml_asg_name
}

output "content_asg_name" {
  description = "Content ASG name"
  value       = module.compute.content_asg_name
}

output "rabbitmq_private_ip" {
  description = "RabbitMQ server private IP"
  value       = module.compute.rabbitmq_private_ip
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name (single distribution for all origins)"
  value       = module.compute.cloudfront_domain_name
}

# Legacy outputs for backward compatibility
output "app_cloudfront_domain_name" {
  description = "CloudFront distribution domain name (legacy)"
  value       = module.compute.cloudfront_domain_name
}

output "botpress_cloudfront_domain_name" {
  description = "CloudFront distribution domain name (legacy)"
  value       = module.compute.cloudfront_domain_name
}

#------------------------------------------------------------------------------
# Outputs for Monitoring
#------------------------------------------------------------------------------

output "app_alb_arn_suffix" {
  description = "App ALB ARN suffix for CloudWatch"
  value       = module.compute.app_alb_arn_suffix
}

output "api_alb_arn_suffix" {
  description = "API ALB ARN suffix for CloudWatch"
  value       = module.compute.api_alb_arn_suffix
}

output "app_target_group_arn_suffix" {
  description = "App target group ARN suffix for CloudWatch"
  value       = module.compute.app_target_group_arn_suffix
}

output "api_target_group_arn_suffix" {
  description = "API target group ARN suffix for CloudWatch"
  value       = module.compute.api_target_group_arn_suffix
}
