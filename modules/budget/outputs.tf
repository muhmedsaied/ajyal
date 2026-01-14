###############################################################################
# Budget Module Outputs
###############################################################################

output "budget_name" {
  description = "Name of the budget"
  value       = aws_budgets_budget.monthly.name
}

output "budget_limit" {
  description = "Budget limit amount"
  value       = aws_budgets_budget.monthly.limit_amount
}

output "sns_topic_arn" {
  description = "SNS topic ARN for budget alerts"
  value       = aws_sns_topic.budget_alerts.arn
}
