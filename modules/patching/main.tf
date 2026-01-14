###############################################################################
# Patching Module
# SSM Patch Manager with configurable on/off toggles for Windows and Linux
###############################################################################

locals {
  name_prefix = "${var.environment}-ajyal"
}

#------------------------------------------------------------------------------
# SNS Topic for Patch Notifications
#------------------------------------------------------------------------------

resource "aws_sns_topic" "patch_notifications" {
  count = var.enable_patching && var.enable_patch_notifications ? 1 : 0
  name  = "${local.name_prefix}-patch-notifications"

  tags = {
    Name = "${local.name_prefix}-patch-notifications"
  }
}

resource "aws_sns_topic_subscription" "patch_email" {
  count     = var.enable_patching && var.enable_patch_notifications && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.patch_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

#------------------------------------------------------------------------------
# IAM Role for Maintenance Window Tasks
#------------------------------------------------------------------------------

resource "aws_iam_role" "maintenance_window" {
  count = var.enable_patching ? 1 : 0
  name  = "${local.name_prefix}-maintenance-window-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-maintenance-window-role"
  }
}

resource "aws_iam_role_policy_attachment" "maintenance_window" {
  count      = var.enable_patching ? 1 : 0
  role       = aws_iam_role.maintenance_window[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonSSMMaintenanceWindowRole"
}

resource "aws_iam_role_policy" "maintenance_window_sns" {
  count = var.enable_patching && var.enable_patch_notifications ? 1 : 0
  name  = "${local.name_prefix}-maintenance-window-sns-policy"
  role  = aws_iam_role.maintenance_window[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.patch_notifications[0].arn
      }
    ]
  })
}

#------------------------------------------------------------------------------
# Windows Patch Baseline (Custom)
#------------------------------------------------------------------------------

resource "aws_ssm_patch_baseline" "windows" {
  count            = var.enable_patching && var.enable_windows_patching ? 1 : 0
  name             = "${local.name_prefix}-windows-patch-baseline"
  description      = "Custom Windows patch baseline for ${local.name_prefix}"
  operating_system = "WINDOWS"

  approval_rule {
    approve_after_days = var.auto_approve_after_days
    compliance_level   = var.compliance_severity

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["CriticalUpdates", "SecurityUpdates"]
    }

    patch_filter {
      key    = "MSRC_SEVERITY"
      values = ["Critical", "Important"]
    }
  }

  # Auto-approve critical patches immediately
  approval_rule {
    approve_after_days = 0
    compliance_level   = "CRITICAL"

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["CriticalUpdates"]
    }

    patch_filter {
      key    = "MSRC_SEVERITY"
      values = ["Critical"]
    }
  }

  tags = {
    Name = "${local.name_prefix}-windows-patch-baseline"
  }
}

#------------------------------------------------------------------------------
# Linux Patch Baseline (Custom)
#------------------------------------------------------------------------------

resource "aws_ssm_patch_baseline" "linux" {
  count            = var.enable_patching && var.enable_linux_patching ? 1 : 0
  name             = "${local.name_prefix}-linux-patch-baseline"
  description      = "Custom Linux patch baseline for ${local.name_prefix}"
  operating_system = "AMAZON_LINUX_2"

  approval_rule {
    approve_after_days = var.auto_approve_after_days
    compliance_level   = var.compliance_severity

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Bugfix"]
    }

    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important"]
    }
  }

  # Auto-approve critical patches immediately
  approval_rule {
    approve_after_days = 0
    compliance_level   = "CRITICAL"

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security"]
    }

    patch_filter {
      key    = "SEVERITY"
      values = ["Critical"]
    }
  }

  tags = {
    Name = "${local.name_prefix}-linux-patch-baseline"
  }
}

#------------------------------------------------------------------------------
# Patch Groups
#------------------------------------------------------------------------------

resource "aws_ssm_patch_group" "windows" {
  count       = var.enable_patching && var.enable_windows_patching ? 1 : 0
  baseline_id = aws_ssm_patch_baseline.windows[0].id
  patch_group = "${local.name_prefix}-windows"
}

resource "aws_ssm_patch_group" "linux" {
  count       = var.enable_patching && var.enable_linux_patching ? 1 : 0
  baseline_id = aws_ssm_patch_baseline.linux[0].id
  patch_group = "${local.name_prefix}-linux"
}

#------------------------------------------------------------------------------
# Windows Maintenance Window
#------------------------------------------------------------------------------

resource "aws_ssm_maintenance_window" "windows" {
  count                      = var.enable_patching && var.enable_windows_patching ? 1 : 0
  name                       = "${local.name_prefix}-windows-maintenance-window"
  schedule                   = var.windows_patch_schedule
  duration                   = var.windows_maintenance_window_duration
  cutoff                     = 1
  allow_unassociated_targets = false

  tags = {
    Name = "${local.name_prefix}-windows-maintenance-window"
  }
}

resource "aws_ssm_maintenance_window_target" "windows" {
  count         = var.enable_patching && var.enable_windows_patching ? 1 : 0
  window_id     = aws_ssm_maintenance_window.windows[0].id
  name          = "${local.name_prefix}-windows-targets"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:PatchGroup"
    values = ["${local.name_prefix}-windows"]
  }
}

resource "aws_ssm_maintenance_window_task" "windows_patch" {
  count            = var.enable_patching && var.enable_windows_patching ? 1 : 0
  window_id        = aws_ssm_maintenance_window.windows[0].id
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  service_role_arn = aws_iam_role.maintenance_window[0].arn
  max_errors       = "1"
  max_concurrency  = "2"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.windows[0].id]
  }

  task_invocation_parameters {
    run_command_parameters {
      parameter {
        name   = "Operation"
        values = ["Install"]
      }
      parameter {
        name   = "RebootOption"
        values = ["RebootIfNeeded"]
      }

      dynamic "notification_config" {
        for_each = var.enable_patch_notifications ? [1] : []
        content {
          notification_arn    = aws_sns_topic.patch_notifications[0].arn
          notification_events = ["All"]
          notification_type   = "Command"
        }
      }
    }
  }
}

#------------------------------------------------------------------------------
# Linux Maintenance Window
#------------------------------------------------------------------------------

resource "aws_ssm_maintenance_window" "linux" {
  count                      = var.enable_patching && var.enable_linux_patching ? 1 : 0
  name                       = "${local.name_prefix}-linux-maintenance-window"
  schedule                   = var.linux_patch_schedule
  duration                   = var.linux_maintenance_window_duration
  cutoff                     = 1
  allow_unassociated_targets = false

  tags = {
    Name = "${local.name_prefix}-linux-maintenance-window"
  }
}

resource "aws_ssm_maintenance_window_target" "linux" {
  count         = var.enable_patching && var.enable_linux_patching ? 1 : 0
  window_id     = aws_ssm_maintenance_window.linux[0].id
  name          = "${local.name_prefix}-linux-targets"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:PatchGroup"
    values = ["${local.name_prefix}-linux"]
  }
}

resource "aws_ssm_maintenance_window_task" "linux_patch" {
  count            = var.enable_patching && var.enable_linux_patching ? 1 : 0
  window_id        = aws_ssm_maintenance_window.linux[0].id
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  service_role_arn = aws_iam_role.maintenance_window[0].arn
  max_errors       = "1"
  max_concurrency  = "2"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.linux[0].id]
  }

  task_invocation_parameters {
    run_command_parameters {
      parameter {
        name   = "Operation"
        values = ["Install"]
      }
      parameter {
        name   = "RebootOption"
        values = ["RebootIfNeeded"]
      }

      dynamic "notification_config" {
        for_each = var.enable_patch_notifications ? [1] : []
        content {
          notification_arn    = aws_sns_topic.patch_notifications[0].arn
          notification_events = ["All"]
          notification_type   = "Command"
        }
      }
    }
  }
}

#------------------------------------------------------------------------------
# Patch Compliance Resource Data Sync
#------------------------------------------------------------------------------

resource "aws_ssm_resource_data_sync" "patch_compliance" {
  count = var.enable_patching && var.enable_patch_compliance ? 1 : 0
  name  = "${local.name_prefix}-patch-compliance-sync"

  s3_destination {
    bucket_name = aws_s3_bucket.patch_compliance[0].id
    region      = data.aws_region.current.name
  }
}

resource "aws_s3_bucket" "patch_compliance" {
  count  = var.enable_patching && var.enable_patch_compliance ? 1 : 0
  bucket = "${local.name_prefix}-patch-compliance-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${local.name_prefix}-patch-compliance"
  }
}

resource "aws_s3_bucket_versioning" "patch_compliance" {
  count  = var.enable_patching && var.enable_patch_compliance ? 1 : 0
  bucket = aws_s3_bucket.patch_compliance[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "patch_compliance" {
  count  = var.enable_patching && var.enable_patch_compliance ? 1 : 0
  bucket = aws_s3_bucket.patch_compliance[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "patch_compliance" {
  count  = var.enable_patching && var.enable_patch_compliance ? 1 : 0
  bucket = aws_s3_bucket.patch_compliance[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "patch_compliance" {
  count  = var.enable_patching && var.enable_patch_compliance ? 1 : 0
  bucket = aws_s3_bucket.patch_compliance[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.patch_compliance[0].arn
      },
      {
        Sid    = "SSMBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.patch_compliance[0].arn}/*"
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

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
