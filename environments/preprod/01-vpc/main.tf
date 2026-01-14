###############################################################################
# VPC Module - Standalone Deployment
# State: s3://ajyal-preprod-terraform-state-946846709937-{ACCOUNT}/preprod/vpc/terraform.tfstate
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
    key            = "preprod/vpc/terraform.tfstate"
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
      Module      = "vpc"
    }
  }
}

#------------------------------------------------------------------------------
# VPC Module
#------------------------------------------------------------------------------

module "vpc" {
  source = "../../../modules/vpc"

  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  availability_zone   = "${var.aws_region}a"
  availability_zone_2 = var.availability_zone_2

  public_subnet_cidr     = var.public_subnet_cidr
  public_subnet_cidr_az2 = var.public_subnet_cidr_az2
  private_web_cidr       = var.private_web_cidr
  private_app_cidr       = var.private_app_cidr
  private_app_cidr_az2   = var.private_app_cidr_az2
  private_data_cidr      = var.private_data_cidr
  private_data_cidr_az2  = var.private_data_cidr_az2

  enable_nat_gateway   = var.enable_nat_gateway
  enable_vpc_flow_logs = var.enable_vpc_flow_logs
}

#------------------------------------------------------------------------------
# Outputs (stored in tfstate, used by other modules)
#------------------------------------------------------------------------------

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr" {
  value = module.vpc.vpc_cidr
}

output "public_subnet_id" {
  value = module.vpc.public_subnet_id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs for ALBs"
  value       = module.vpc.public_subnet_ids
}

output "private_web_subnet_id" {
  value = module.vpc.private_web_subnet_id
}

output "private_app_subnet_id" {
  value = module.vpc.private_app_subnet_id
}

output "private_app_subnet_ids" {
  description = "List of private app subnet IDs for internal ALBs"
  value       = module.vpc.private_app_subnet_ids
}

output "private_data_subnet_id" {
  value = module.vpc.private_data_subnet_id
}

output "private_data_subnet_id_az2" {
  value = module.vpc.private_data_subnet_id_az2
}

output "private_data_subnet_ids" {
  value = module.vpc.private_data_subnet_ids
}

output "availability_zone" {
  value = module.vpc.availability_zone
}
