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
  bundler_kms_key_arns = distinct(compact([
    var.kms_key_arn,
    var.codedeploy_bundler_ssm_kms_key_id
  ]))
  bundler_api_config = {
    template               = "api-server"
    output_prefix          = var.codedeploy_bundler_api_output_prefix
    deployment_group       = var.enable_codedeploy_per_service ? "" : try(aws_codedeploy_deployment_group.windows_api[0].deployment_group_name, "")
    allowed_names          = var.codedeploy_bundler_api_allowed_names
    bundle_all             = var.enable_codedeploy_per_service ? false : true
    app_name_prefix        = var.enable_codedeploy_per_service ? "${local.name_prefix}-api" : ""
    asg_name               = var.enable_codedeploy_per_service ? var.api_asg_name : ""
    target_group_name      = var.enable_codedeploy_per_service ? var.api_target_group_name : ""
    deployment_config_name = var.enable_codedeploy_per_service ? var.deployment_config_name : ""
    auto_rollback          = var.enable_codedeploy_per_service ? var.enable_auto_rollback : false
    ssm_base_path          = var.enable_codedeploy_per_service ? "/${local.name_prefix}/secrets/api-services" : ""
    ssm_files              = []
    seed_ssm               = var.enable_codedeploy_per_service ? true : false
  }
  bundler_integration_config = {
    template               = "integration-server"
    output_prefix          = var.codedeploy_bundler_integration_output_prefix
    deployment_group       = var.enable_codedeploy_per_service ? "" : try(aws_codedeploy_deployment_group.windows_integration[0].deployment_group_name, "")
    allowed_names          = var.codedeploy_bundler_integration_allowed_names
    bundle_all             = var.enable_codedeploy_per_service ? false : true
    app_name_prefix        = var.enable_codedeploy_per_service ? "${local.name_prefix}-integration" : ""
    asg_name               = var.enable_codedeploy_per_service ? var.integration_asg_name : ""
    target_group_name      = ""
    deployment_config_name = var.enable_codedeploy_per_service ? var.deployment_config_name : ""
    auto_rollback          = var.enable_codedeploy_per_service ? var.enable_auto_rollback : false
    ssm_base_path          = var.enable_codedeploy_per_service ? "/${local.name_prefix}/secrets/integration-services" : ""
    ssm_files              = []
    seed_ssm               = var.enable_codedeploy_per_service ? true : false
  }
  bundler_app_config = {
    template               = "app-server"
    output_prefix          = var.codedeploy_bundler_app_output_prefix
    deployment_group       = var.enable_codedeploy_per_service ? "" : try(aws_codedeploy_deployment_group.windows_app[0].deployment_group_name, "")
    allowed_names          = var.codedeploy_bundler_app_allowed_names
    bundle_all             = var.enable_codedeploy_per_service ? false : true
    app_name_prefix        = var.enable_codedeploy_per_service ? "${local.name_prefix}-app" : ""
    asg_name               = var.enable_codedeploy_per_service ? var.app_asg_name : ""
    target_group_name      = var.enable_codedeploy_per_service ? var.app_target_group_name : ""
    deployment_config_name = var.enable_codedeploy_per_service ? var.deployment_config_name : ""
    auto_rollback          = var.enable_codedeploy_per_service ? var.enable_auto_rollback : false
    ssm_base_path          = var.enable_codedeploy_per_service ? "/${local.name_prefix}/secrets/app-server" : ""
    ssm_files              = var.enable_codedeploy_per_service ? ["web.config", "SystemSettings.xml", "App_GlobalResources/Configuration.resx", "PublishedServices.json"] : []
    seed_ssm               = false
  }
  bundler_prefix_config = var.enable_codedeploy_bundler ? tomap({
    "${var.codedeploy_bundler_api_prefix}"         = local.bundler_api_config
    "${var.codedeploy_bundler_integration_prefix}" = local.bundler_integration_config
    "${var.codedeploy_bundler_app_prefix}"         = local.bundler_app_config
  }) : tomap({})
  bundler_kms_statement = length(local.bundler_kms_key_arns) > 0 ? [
    for key_arn in local.bundler_kms_key_arns : {
      Effect = "Allow"
      Action = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ]
      Resource = key_arn
    }
  ] : []
  codedeploy_kms_statement = var.kms_key_arn != "" ? [
    {
      Effect = "Allow"
      Action = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ]
      Resource = var.kms_key_arn
      Condition = {
        StringLike = {
          "kms:ViaService" = "s3.${data.aws_region.current.name}.amazonaws.com"
        }
      }
    }
  ] : []
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
    Statement = concat(
      [
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
      ],
      local.codedeploy_kms_statement
    )
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
  count            = var.enable_codedeploy && !var.enable_codedeploy_per_service ? 1 : 0
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
  count                  = var.enable_codedeploy && !var.enable_codedeploy_per_service ? 1 : 0
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
  count                  = var.enable_codedeploy && !var.enable_codedeploy_per_service ? 1 : 0
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
  count                  = var.enable_codedeploy && !var.enable_codedeploy_per_service ? 1 : 0
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

  autoscaling_groups = var.integration_asg_name != "" ? [var.integration_asg_name] : []

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
  count                  = var.enable_codedeploy && !var.enable_codedeploy_per_service ? 1 : 0
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
  count            = var.enable_codedeploy && !var.enable_codedeploy_per_service ? 1 : 0
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
  count                  = var.enable_codedeploy && !var.enable_codedeploy_per_service ? 1 : 0
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
  count                  = var.enable_codedeploy && !var.enable_codedeploy_per_service ? 1 : 0
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
  count                  = var.enable_codedeploy && !var.enable_codedeploy_per_service ? 1 : 0
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
# CodeDeploy Bundle Builder (S3-triggered Lambda)
#------------------------------------------------------------------------------

data "archive_file" "codedeploy_bundler" {
  count       = var.enable_codedeploy_bundler ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/lambda/deploy-bundler"
  output_path = "${path.root}/.terraform/codedeploy-bundler.zip"
}

resource "aws_iam_role" "codedeploy_bundler" {
  count = var.enable_codedeploy_bundler ? 1 : 0
  name  = "${local.name_prefix}-codedeploy-bundler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-codedeploy-bundler-role"
  }
}

resource "aws_iam_role_policy" "codedeploy_bundler" {
  count = var.enable_codedeploy_bundler ? 1 : 0
  name  = "${local.name_prefix}-codedeploy-bundler-policy"
  role  = aws_iam_role.codedeploy_bundler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Resource = "arn:aws:logs:${data.aws_region.current.name}:*:log-group:/aws/lambda/${local.name_prefix}-codedeploy-bundler*:*"
        },
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:GetObjectVersion",
            "s3:PutObject",
            "s3:ListBucket"
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
            "codedeploy:CreateApplication",
            "codedeploy:CreateDeploymentGroup",
            "codedeploy:GetApplicationRevision",
            "codedeploy:RegisterApplicationRevision",
            "codedeploy:GetApplication",
            "codedeploy:GetDeployment",
            "codedeploy:GetDeploymentConfig",
            "codedeploy:GetDeploymentGroup",
            "codedeploy:UpdateDeploymentGroup"
          ]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "ssm:PutParameter"
          ]
          Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${local.name_prefix}/secrets/*"
        },
        {
          Effect = "Allow"
          Action = [
            "iam:PassRole"
          ]
          Resource = try(aws_iam_role.codedeploy[0].arn, "*")
        }
      ],
      local.bundler_kms_statement
    )
  })
}

resource "aws_cloudwatch_log_group" "codedeploy_bundler" {
  count             = var.enable_codedeploy_bundler ? 1 : 0
  name              = "/aws/lambda/${local.name_prefix}-codedeploy-bundler"
  retention_in_days = var.codedeploy_bundler_log_retention_days
}

resource "aws_lambda_function" "codedeploy_bundler" {
  count         = var.enable_codedeploy_bundler ? 1 : 0
  function_name = "${local.name_prefix}-codedeploy-bundler"
  role          = aws_iam_role.codedeploy_bundler[0].arn
  handler       = "handler.handler"
  runtime       = "python3.11"
  timeout       = var.codedeploy_bundler_lambda_timeout
  memory_size   = var.codedeploy_bundler_lambda_memory
  ephemeral_storage {
    size = var.codedeploy_bundler_lambda_storage
  }

  filename         = data.archive_file.codedeploy_bundler[0].output_path
  source_code_hash = data.archive_file.codedeploy_bundler[0].output_base64sha256

  environment {
    variables = {
      PREFIX_CONFIG              = jsonencode(local.bundler_prefix_config)
      AUTO_DEPLOY                = var.codedeploy_bundler_auto_deploy ? "true" : "false"
      CODEDEPLOY_APP_NAME        = var.codedeploy_windows_app_name
      CODEDEPLOY_SERVICE_ROLE_ARN = try(aws_iam_role.codedeploy[0].arn, "")
      DEFAULT_DEPLOYMENT_CONFIG  = var.deployment_config_name
      DEFAULT_AUTO_ROLLBACK      = var.enable_auto_rollback ? "true" : "false"
      SSM_KMS_KEY_ID             = var.codedeploy_bundler_ssm_kms_key_id
      KMS_KEY_ARN                = var.kms_key_arn
      LOG_LEVEL                  = "INFO"
    }
  }

  depends_on = [aws_cloudwatch_log_group.codedeploy_bundler]
}

resource "aws_lambda_permission" "codedeploy_bundler_s3" {
  count         = var.enable_codedeploy_bundler ? 1 : 0
  statement_id  = "AllowS3InvokeCodeDeployBundler"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.codedeploy_bundler[0].arn
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${var.artifact_bucket_name}"
}

resource "aws_s3_bucket_notification" "codedeploy_bundler" {
  count  = var.enable_codedeploy_bundler ? 1 : 0
  bucket = var.artifact_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.codedeploy_bundler[0].arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.codedeploy_bundler_api_prefix
    filter_suffix       = ".zip"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.codedeploy_bundler[0].arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.codedeploy_bundler_integration_prefix
    filter_suffix       = ".zip"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.codedeploy_bundler[0].arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.codedeploy_bundler_app_prefix
    filter_suffix       = ".zip"
  }

  depends_on = [aws_lambda_permission.codedeploy_bundler_s3]
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

data "aws_caller_identity" "current" {}
