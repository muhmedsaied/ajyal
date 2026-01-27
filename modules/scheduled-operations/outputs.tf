output "lambda_function_arn" {
  description = "ARN of the scheduled operations Lambda function"
  value       = aws_lambda_function.scheduled_ops.arn
}

output "lambda_function_name" {
  description = "Name of the scheduled operations Lambda function"
  value       = aws_lambda_function.scheduled_ops.function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "stop_rule_arn" {
  description = "ARN of the stop EventBridge rule"
  value       = var.enable_schedule ? aws_cloudwatch_event_rule.stop_schedule[0].arn : null
}

output "start_rule_arn" {
  description = "ARN of the start EventBridge rule"
  value       = var.enable_schedule ? aws_cloudwatch_event_rule.start_schedule[0].arn : null
}

output "stop_schedule" {
  description = "Stop schedule cron expression"
  value       = var.stop_cron_expression
}

output "start_schedule" {
  description = "Start schedule cron expression"
  value       = var.start_cron_expression
}
