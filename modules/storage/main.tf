###############################################################################
# Storage Module
# EFS (Content & ML Storage) and S3 (Backups & Logs)
###############################################################################

locals {
  name_prefix = "${var.environment}-ajyal"
}

#------------------------------------------------------------------------------
# Content EFS (30TB)
#------------------------------------------------------------------------------

resource "aws_efs_file_system" "content" {
  count          = var.enable_content_efs ? 1 : 0
  creation_token = "${local.name_prefix}-content-efs"
  encrypted      = true
  kms_key_id     = var.kms_key_arn

  throughput_mode = var.efs_throughput_mode

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = {
    Name = "${local.name_prefix}-content-efs"
  }
}

resource "aws_efs_mount_target" "content" {
  count           = var.enable_content_efs ? 1 : 0
  file_system_id  = aws_efs_file_system.content[0].id
  subnet_id       = var.private_subnet_id
  security_groups = var.security_group_ids
}

resource "aws_efs_backup_policy" "content" {
  count          = var.enable_content_efs ? 1 : 0
  file_system_id = aws_efs_file_system.content[0].id

  backup_policy {
    status = "ENABLED"
  }
}

resource "aws_efs_access_point" "content" {
  count          = var.enable_content_efs ? 1 : 0
  file_system_id = aws_efs_file_system.content[0].id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/content"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = {
    Name = "${local.name_prefix}-content-efs-ap"
  }
}

#------------------------------------------------------------------------------
# ML EFS (150GB)
#------------------------------------------------------------------------------

resource "aws_efs_file_system" "ml" {
  count          = var.enable_ml_efs ? 1 : 0
  creation_token = "${local.name_prefix}-ml-efs"
  encrypted      = true
  kms_key_id     = var.kms_key_arn

  throughput_mode = var.efs_throughput_mode

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "${local.name_prefix}-ml-efs"
  }
}

resource "aws_efs_mount_target" "ml" {
  count           = var.enable_ml_efs ? 1 : 0
  file_system_id  = aws_efs_file_system.ml[0].id
  subnet_id       = var.private_subnet_id
  security_groups = var.security_group_ids
}

resource "aws_efs_backup_policy" "ml" {
  count          = var.enable_ml_efs ? 1 : 0
  file_system_id = aws_efs_file_system.ml[0].id

  backup_policy {
    status = "ENABLED"
  }
}

resource "aws_efs_access_point" "ml" {
  count          = var.enable_ml_efs ? 1 : 0
  file_system_id = aws_efs_file_system.ml[0].id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/ml"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = {
    Name = "${local.name_prefix}-ml-efs-ap"
  }
}

#------------------------------------------------------------------------------
# S3 Bucket for Backups and Artifacts
#------------------------------------------------------------------------------

resource "aws_s3_bucket" "backup" {
  count  = var.enable_backup_bucket ? 1 : 0
  bucket = "${local.name_prefix}-backup-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${local.name_prefix}-backup"
  }
}

resource "aws_s3_bucket_versioning" "backup" {
  count  = var.enable_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.backup[0].id

  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  count  = var.enable_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.backup[0].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  count  = var.enable_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.backup[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  count  = var.enable_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.backup[0].id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

#------------------------------------------------------------------------------
# S3 Bucket for CodeDeploy Artifacts
#------------------------------------------------------------------------------

resource "aws_s3_bucket" "deployment" {
  count  = var.enable_deployment_bucket ? 1 : 0
  bucket = "${local.name_prefix}-deployments-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${local.name_prefix}-deployments"
  }
}

resource "aws_s3_bucket_versioning" "deployment" {
  count  = var.enable_deployment_bucket ? 1 : 0
  bucket = aws_s3_bucket.deployment[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "deployment" {
  count  = var.enable_deployment_bucket ? 1 : 0
  bucket = aws_s3_bucket.deployment[0].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "deployment" {
  count  = var.enable_deployment_bucket ? 1 : 0
  bucket = aws_s3_bucket.deployment[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy for deployment artifacts - keep only recent versions
resource "aws_s3_bucket_lifecycle_configuration" "deployment" {
  count  = var.enable_deployment_bucket ? 1 : 0
  bucket = aws_s3_bucket.deployment[0].id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    expiration {
      expired_object_delete_marker = true
    }
  }
}

#------------------------------------------------------------------------------
# S3 Bucket for Logs
#------------------------------------------------------------------------------

resource "aws_s3_bucket" "logs" {
  count  = var.enable_logs_bucket ? 1 : 0
  bucket = "${local.name_prefix}-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${local.name_prefix}-logs"
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  count  = var.enable_logs_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count  = var.enable_logs_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  count  = var.enable_logs_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  count  = var.enable_logs_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    id     = "log-retention"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# Policy for CloudTrail and ALB logs
resource "aws_s3_bucket_policy" "logs" {
  count  = var.enable_logs_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.logs[0].arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.logs[0].arn
      },
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
