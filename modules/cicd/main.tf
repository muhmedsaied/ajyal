###############################################################################
# CI/CD Module
# CodeDeploy for FAST ZERO-DOWNTIME deployments on Windows and Linux
# CodePipeline for CI/CD automation
#
# DEPLOYMENT STRATEGIES:
# 1. AllAtOnce - Deploy to ALL instances simultaneously (fastest, brief downtime)
# 2. HalfAtATime - Deploy to 50% at a time (zero downtime)
# 3. OneAtATime - Deploy one instance at a time (zero downtime, slowest)
# 4. Blue/Green with ALB - Full zero downtime with instant rollback
###############################################################################

locals {
  name_prefix = "${var.environment}-ajyal"
}

#------------------------------------------------------------------------------
# IAM Role for EC2 Instances (CodeDeploy Agent + SSM)
#------------------------------------------------------------------------------

resource "aws_iam_role" "ec2_instance" {
  name = "${local.name_prefix}-ec2-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-ec2-instance-role"
  }
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-instance-profile"
  role = aws_iam_role.ec2_instance.name

  tags = {
    Name = "${local.name_prefix}-ec2-instance-profile"
  }
}

# SSM Managed Instance Core (for patching and management)
resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch Agent
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Secrets Manager - Read database credentials and application secrets
resource "aws_iam_role_policy" "secrets_manager" {
  name = "${local.name_prefix}-secrets-manager-policy"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${data.aws_region.current.name}:*:secret:${var.environment}-ajyal/*"
        ]
      }
    ]
  })
}

# S3 Read for CodeDeploy artifacts
resource "aws_iam_role_policy" "codedeploy_s3" {
  count = var.enable_codedeploy ? 1 : 0
  name  = "${local.name_prefix}-codedeploy-s3-policy"
  role  = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:Get*",
          "s3:List*"
        ]
        Resource = [
          "arn:aws:s3:::${var.artifact_bucket_name}",
          "arn:aws:s3:::${var.artifact_bucket_name}/*",
          "arn:aws:s3:::aws-codedeploy-${data.aws_region.current.name}/*"
        ]
      }
    ]
  })
}

#------------------------------------------------------------------------------
# CodeDeploy IAM Role
#------------------------------------------------------------------------------

resource "aws_iam_role" "codedeploy" {
  count = var.enable_codedeploy ? 1 : 0
  name  = "${local.name_prefix}-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-codedeploy-role"
  }
}

resource "aws_iam_role_policy_attachment" "codedeploy" {
  count      = var.enable_codedeploy ? 1 : 0
  role       = aws_iam_role.codedeploy[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

#------------------------------------------------------------------------------
# CodeDeploy Application - Windows
#------------------------------------------------------------------------------

resource "aws_codedeploy_app" "windows" {
  count            = var.enable_codedeploy ? 1 : 0
  name             = var.codedeploy_windows_app_name
  compute_platform = "Server"

  tags = {
    Name     = var.codedeploy_windows_app_name
    Platform = "Windows"
  }
}

#------------------------------------------------------------------------------
# Windows Deployment Groups with ZERO-DOWNTIME support
#------------------------------------------------------------------------------

# App Servers - with ALB integration for zero-downtime
resource "aws_codedeploy_deployment_group" "windows_app" {
  count                  = var.enable_codedeploy ? 1 : 0
  app_name               = aws_codedeploy_app.windows[0].name
  deployment_group_name  = "${local.name_prefix}-windows-app-dg"
  service_role_arn       = aws_iam_role.codedeploy[0].arn
  deployment_config_name = var.deployment_config_name

  # Target instances by tag
  ec2_tag_set {
    ec2_tag_filter {
      key   = "DeploymentGroup"
      type  = "KEY_AND_VALUE"
      value = "windows-app"
    }
  }

  # Auto Scaling Group integration
  autoscaling_groups = var.app_asg_name != "" ? [var.app_asg_name] : []

  # Load Balancer for zero-downtime (removes from ALB during deploy)
  dynamic "load_balancer_info" {
    for_each = var.app_target_group_name != "" ? [1] : []
    content {
      target_group_info {
        name = var.app_target_group_name
      }
    }
  }

  # Deployment settings for zero-downtime
  deployment_style {
    deployment_option = var.app_target_group_name != "" ? "WITH_TRAFFIC_CONTROL" : "WITHOUT_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  # Auto rollback on failure
  auto_rollback_configuration {
    enabled = var.enable_auto_rollback
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  tags = {
    Name = "${local.name_prefix}-windows-app-dg"
  }
}

# API Servers - with ALB integration for zero-downtime
resource "aws_codedeploy_deployment_group" "windows_api" {
  count                  = var.enable_codedeploy ? 1 : 0
  app_name               = aws_codedeploy_app.windows[0].name
  deployment_group_name  = "${local.name_prefix}-windows-api-dg"
  service_role_arn       = aws_iam_role.codedeploy[0].arn
  deployment_config_name = var.deployment_config_name

  ec2_tag_set {
    ec2_tag_filter {
      key   = "DeploymentGroup"
      type  = "KEY_AND_VALUE"
      value = "windows-api"
    }
  }

  autoscaling_groups = var.api_asg_name != "" ? [var.api_asg_name] : []

  dynamic "load_balancer_info" {
    for_each = var.api_target_group_name != "" ? [1] : []
    content {
      target_group_info {
        name = var.api_target_group_name
      }
    }
  }

  deployment_style {
    deployment_option = var.api_target_group_name != "" ? "WITH_TRAFFIC_CONTROL" : "WITHOUT_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  auto_rollback_configuration {
    enabled = var.enable_auto_rollback
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  tags = {
    Name = "${local.name_prefix}-windows-api-dg"
  }
}

# Integration Servers
resource "aws_codedeploy_deployment_group" "windows_integration" {
  count                  = var.enable_codedeploy ? 1 : 0
  app_name               = aws_codedeploy_app.windows[0].name
  deployment_group_name  = "${local.name_prefix}-windows-integration-dg"
  service_role_arn       = aws_iam_role.codedeploy[0].arn
  deployment_config_name = var.deployment_config_name

  ec2_tag_set {
    ec2_tag_filter {
      key   = "DeploymentGroup"
      type  = "KEY_AND_VALUE"
      value = "windows-integration"
    }
  }

  deployment_style {
    deployment_option = "WITHOUT_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  auto_rollback_configuration {
    enabled = var.enable_auto_rollback
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  tags = {
    Name = "${local.name_prefix}-windows-integration-dg"
  }
}

# Logging Servers
resource "aws_codedeploy_deployment_group" "windows_logging" {
  count                  = var.enable_codedeploy ? 1 : 0
  app_name               = aws_codedeploy_app.windows[0].name
  deployment_group_name  = "${local.name_prefix}-windows-logging-dg"
  service_role_arn       = aws_iam_role.codedeploy[0].arn
  deployment_config_name = var.deployment_config_name

  ec2_tag_set {
    ec2_tag_filter {
      key   = "DeploymentGroup"
      type  = "KEY_AND_VALUE"
      value = "windows-logging"
    }
  }

  deployment_style {
    deployment_option = "WITHOUT_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  auto_rollback_configuration {
    enabled = var.enable_auto_rollback
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  tags = {
    Name = "${local.name_prefix}-windows-logging-dg"
  }
}

#------------------------------------------------------------------------------
# CodeDeploy Application - Linux
#------------------------------------------------------------------------------

resource "aws_codedeploy_app" "linux" {
  count            = var.enable_codedeploy ? 1 : 0
  name             = var.codedeploy_linux_app_name
  compute_platform = "Server"

  tags = {
    Name     = var.codedeploy_linux_app_name
    Platform = "Linux"
  }
}

#------------------------------------------------------------------------------
# Linux Deployment Groups
#------------------------------------------------------------------------------

# RabbitMQ - No CodeDeploy (single instance service, managed separately)

resource "aws_codedeploy_deployment_group" "linux_botpress" {
  count                  = var.enable_codedeploy ? 1 : 0
  app_name               = aws_codedeploy_app.linux[0].name
  deployment_group_name  = "${local.name_prefix}-linux-botpress-dg"
  service_role_arn       = aws_iam_role.codedeploy[0].arn
  deployment_config_name = var.deployment_config_name

  ec2_tag_set {
    ec2_tag_filter {
      key   = "DeploymentGroup"
      type  = "KEY_AND_VALUE"
      value = "linux-botpress"
    }
  }

  autoscaling_groups = var.botpress_asg_name != "" ? [var.botpress_asg_name] : []

  dynamic "load_balancer_info" {
    for_each = var.botpress_target_group_name != "" ? [1] : []
    content {
      target_group_info {
        name = var.botpress_target_group_name
      }
    }
  }

  deployment_style {
    deployment_option = var.botpress_target_group_name != "" ? "WITH_TRAFFIC_CONTROL" : "WITHOUT_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  auto_rollback_configuration {
    enabled = var.enable_auto_rollback
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  tags = {
    Name = "${local.name_prefix}-linux-botpress-dg"
  }
}

resource "aws_codedeploy_deployment_group" "linux_ml" {
  count                  = var.enable_codedeploy ? 1 : 0
  app_name               = aws_codedeploy_app.linux[0].name
  deployment_group_name  = "${local.name_prefix}-linux-ml-dg"
  service_role_arn       = aws_iam_role.codedeploy[0].arn
  deployment_config_name = var.deployment_config_name

  ec2_tag_set {
    ec2_tag_filter {
      key   = "DeploymentGroup"
      type  = "KEY_AND_VALUE"
      value = "linux-ml"
    }
  }

  deployment_style {
    deployment_option = "WITHOUT_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  auto_rollback_configuration {
    enabled = var.enable_auto_rollback
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  tags = {
    Name = "${local.name_prefix}-linux-ml-dg"
  }
}

resource "aws_codedeploy_deployment_group" "linux_content" {
  count                  = var.enable_codedeploy ? 1 : 0
  app_name               = aws_codedeploy_app.linux[0].name
  deployment_group_name  = "${local.name_prefix}-linux-content-dg"
  service_role_arn       = aws_iam_role.codedeploy[0].arn
  deployment_config_name = var.deployment_config_name

  ec2_tag_set {
    ec2_tag_filter {
      key   = "DeploymentGroup"
      type  = "KEY_AND_VALUE"
      value = "linux-content"
    }
  }

  deployment_style {
    deployment_option = "WITHOUT_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  auto_rollback_configuration {
    enabled = var.enable_auto_rollback
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  tags = {
    Name = "${local.name_prefix}-linux-content-dg"
  }
}

#------------------------------------------------------------------------------
# CodePipeline IAM Role
#------------------------------------------------------------------------------

resource "aws_iam_role" "codepipeline" {
  count = var.enable_codepipeline ? 1 : 0
  name  = "${local.name_prefix}-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-codepipeline-role"
  }
}

resource "aws_iam_role_policy" "codepipeline" {
  count = var.enable_codepipeline ? 1 : 0
  name  = "${local.name_prefix}-codepipeline-policy"
  role  = aws_iam_role.codepipeline[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.artifact_bucket_name}",
          "arn:aws:s3:::${var.artifact_bucket_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetApplication",
          "codedeploy:GetApplicationRevision",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:RegisterApplicationRevision"
        ]
        Resource = "*"
      }
    ]
  })
}

#------------------------------------------------------------------------------
# Client Deployment User (for external uploads to S3)
#------------------------------------------------------------------------------

resource "aws_iam_user" "client_deploy" {
  count = var.enable_client_deploy_user ? 1 : 0
  name  = "${local.name_prefix}-client-deploy"
  path  = "/deployment/"

  tags = {
    Name        = "${local.name_prefix}-client-deploy"
    Purpose     = "Client deployment uploads"
    Environment = var.environment
  }
}

resource "aws_iam_policy" "client_deploy" {
  count       = var.enable_client_deploy_user ? 1 : 0
  name        = "${local.name_prefix}-client-deploy-policy"
  description = "Policy for client to upload deployment artifacts to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListDeploymentBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning"
        ]
        Resource = "arn:aws:s3:::${var.artifact_bucket_name}"
      },
      {
        Sid    = "UploadDeploymentArtifacts"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:DeleteObject",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload"
        ]
        Resource = "arn:aws:s3:::${var.artifact_bucket_name}/*"
      },
      {
        Sid    = "KMSEncryptionForS3"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = var.kms_key_arn != "" ? var.kms_key_arn : "*"
        Condition = {
          StringLike = {
            "kms:ViaService" = "s3.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-client-deploy-policy"
  }
}

resource "aws_iam_user_policy_attachment" "client_deploy" {
  count      = var.enable_client_deploy_user ? 1 : 0
  user       = aws_iam_user.client_deploy[0].name
  policy_arn = aws_iam_policy.client_deploy[0].arn
}

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

data "aws_region" "current" {}
