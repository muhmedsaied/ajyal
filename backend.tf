###############################################################################
# Terraform Backend Configuration
# S3 bucket for state files with DynamoDB for locking
# Each module/environment has its own state file in subfolders
###############################################################################

# This file creates the S3 bucket and DynamoDB table for Terraform state
# Run this FIRST before other modules:
#   cd ajyal-iac && terraform init && terraform apply -target=module.backend

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = {
      Project   = "Ajyal-LMS"
      ManagedBy = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

#------------------------------------------------------------------------------
# S3 Bucket for Terraform State (with subfolders per module)
#------------------------------------------------------------------------------

resource "aws_s3_bucket" "terraform_state" {
  bucket = "ajyal-terraform-state-${data.aws_caller_identity.current.account_id}"

  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "Ajyal Terraform State"
    Description = "Stores Terraform state files for all environments and modules"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#------------------------------------------------------------------------------
# DynamoDB Table for State Locking
#------------------------------------------------------------------------------

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "ajyal-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "Ajyal Terraform Locks"
    Description = "DynamoDB table for Terraform state locking"
  }
}

#------------------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------------------

output "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "S3 bucket ARN for Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "dynamodb_table_name" {
  description = "DynamoDB table name for state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "backend_config" {
  description = "Backend configuration to use in other modules"
  value       = <<-EOT
    # Add this to your module's terraform block:
    backend "s3" {
      bucket         = "${aws_s3_bucket.terraform_state.id}"
      region         = "eu-west-1"
      encrypt        = true
      dynamodb_table = "${aws_dynamodb_table.terraform_locks.name}"

      # Use different keys for each environment/module:
      # key = "preprod/vpc/terraform.tfstate"
      # key = "preprod/compute/terraform.tfstate"
      # key = "prod/vpc/terraform.tfstate"
    }
  EOT
}

