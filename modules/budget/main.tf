###############################################################################
# Budget Module
# AWS Budget Alerts for Cost Management
###############################################################################

locals {
  name_prefix = "${var.environment}-ajyal"
}

#------------------------------------------------------------------------------
# SNS Topic for Budget Alerts
#------------------------------------------------------------------------------

resource "aws_sns_topic" "budget_alerts" {
  name = "${local.name_prefix}-budget-alerts"

  tags = {
    Name = "${local.name_prefix}-budget-alerts"
  }
}

resource "aws_sns_topic_subscription" "budget_email" {
  count     = length(var.alert_emails)
  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_emails[count.index]
}

#------------------------------------------------------------------------------
# Monthly Budget with Alert Thresholds
#------------------------------------------------------------------------------

resource "aws_budgets_budget" "monthly" {
  name         = "${local.name_prefix}-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Alert at 50% of budget
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.alert_emails
  }

  # Alert at 80% of budget
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.alert_emails
  }

  # Alert at 100% of budget
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.alert_emails
  }

  # Forecasted alert at 100%
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.alert_emails
  }

  # Filter by linked account if specified
  dynamic "cost_filter" {
    for_each = var.linked_account_id != "" ? [1] : []
    content {
      name   = "LinkedAccount"
      values = [var.linked_account_id]
    }
  }

  tags = {
    Name        = "${local.name_prefix}-monthly-budget"
    Environment = var.environment
  }
}

#------------------------------------------------------------------------------
# CloudWatch Alarm for Billing (us-east-1 only)
# Note: Billing metrics are only available in us-east-1
#------------------------------------------------------------------------------

# This requires the budget to be deployed in us-east-1 for billing metrics
# If you want billing CloudWatch alarms, deploy a separate stack in us-east-1
