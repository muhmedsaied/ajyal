#######################################
# Scheduled Operations Module
# Manages automatic stop/start of ASGs, EC2, and RDS
#######################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  function_name = "${var.environment}-ajyal-scheduled-operations"
  lambda_zip    = "${path.module}/lambda.zip"
}

#######################################
# IAM Role for Lambda
#######################################

resource "aws_iam_role" "lambda_role" {
  name = "${var.environment}-ajyal-scheduled-ops-lambda-role"

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

  tags = var.tags
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.environment}-ajyal-scheduled-ops-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.function_name}:*"
      },
      {
        Sid    = "AutoScaling"
        Effect = "Allow"
        Action = [
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:DescribeAutoScalingGroups"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "autoscaling:ResourceTag/Environment" = var.environment
          }
        }
      },
      {
        Sid    = "AutoScalingDescribe"
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2"
        Effect = "Allow"
        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/Environment" = var.environment
          }
        }
      },
      {
        Sid    = "EC2Describe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Sid    = "RDS"
        Effect = "Allow"
        Action = [
          "rds:StartDBInstance",
          "rds:StopDBInstance",
          "rds:StartDBCluster",
          "rds:StopDBCluster",
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters"
        ]
        Resource = [
          "arn:aws:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:db:${var.environment}-ajyal-*",
          "arn:aws:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster:${var.environment}-ajyal-*"
        ]
      },
      {
        Sid    = "RDSDescribe"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters"
        ]
        Resource = "*"
      }
    ]
  })
}

#######################################
# Lambda Function
#######################################

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = local.lambda_zip
}

resource "aws_lambda_function" "scheduled_ops" {
  function_name    = local.function_name
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_role.arn
  timeout          = 300
  memory_size      = 256

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 30
  tags              = var.tags
}

#######################################
# EventBridge Scheduler Rules
#######################################

# Stop Rule - 10 PM Jordan Time (19:00 UTC)
resource "aws_cloudwatch_event_rule" "stop_schedule" {
  count               = var.enable_schedule ? 1 : 0
  name                = "${var.environment}-ajyal-stop-schedule"
  description         = "Stop Ajyal services at 10 PM Jordan time (19:00 UTC)"
  schedule_expression = var.stop_cron_expression

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "stop_target" {
  count     = var.enable_schedule ? 1 : 0
  rule      = aws_cloudwatch_event_rule.stop_schedule[0].name
  target_id = "StopLambda"
  arn       = aws_lambda_function.scheduled_ops.arn

  input = jsonencode({
    action = "stop"
  })
}

resource "aws_lambda_permission" "allow_eventbridge_stop" {
  count         = var.enable_schedule ? 1 : 0
  statement_id  = "AllowEventBridgeStop"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scheduled_ops.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_schedule[0].arn
}

# Start Rule - 7 AM Jordan Time (04:00 UTC)
resource "aws_cloudwatch_event_rule" "start_schedule" {
  count               = var.enable_schedule ? 1 : 0
  name                = "${var.environment}-ajyal-start-schedule"
  description         = "Start Ajyal services at 7 AM Jordan time (04:00 UTC)"
  schedule_expression = var.start_cron_expression

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "start_target" {
  count     = var.enable_schedule ? 1 : 0
  rule      = aws_cloudwatch_event_rule.start_schedule[0].name
  target_id = "StartLambda"
  arn       = aws_lambda_function.scheduled_ops.arn

  input = jsonencode({
    action = "start"
  })
}

resource "aws_lambda_permission" "allow_eventbridge_start" {
  count         = var.enable_schedule ? 1 : 0
  statement_id  = "AllowEventBridgeStart"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scheduled_ops.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start_schedule[0].arn
}
