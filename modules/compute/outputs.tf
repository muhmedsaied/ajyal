###############################################################################
# Compute Module Outputs
###############################################################################

output "app_alb_dns_name" {
  description = "App ALB DNS name"
  value       = var.enable_app_servers ? aws_lb.app[0].dns_name : null
}

output "app_alb_arn" {
  description = "App ALB ARN"
  value       = var.enable_app_servers ? aws_lb.app[0].arn : null
}

output "app_target_group_name" {
  description = "App target group name"
  value       = var.enable_app_servers ? aws_lb_target_group.app[0].name : null
}

output "app_target_group_arn" {
  description = "App target group ARN"
  value       = var.enable_app_servers ? aws_lb_target_group.app[0].arn : null
}

output "api_alb_dns_name" {
  description = "API ALB DNS name"
  value       = var.enable_api_servers ? aws_lb.api[0].dns_name : null
}

output "api_alb_arn" {
  description = "API ALB ARN"
  value       = var.enable_api_servers ? aws_lb.api[0].arn : null
}

output "api_target_group_name" {
  description = "API target group name"
  value       = var.enable_api_servers ? aws_lb_target_group.api[0].name : null
}

output "api_target_group_arn" {
  description = "API target group ARN"
  value       = var.enable_api_servers ? aws_lb_target_group.api[0].arn : null
}

output "botpress_alb_dns_name" {
  description = "Botpress ALB DNS name"
  value       = var.enable_botpress_servers ? aws_lb.botpress[0].dns_name : null
}

output "botpress_alb_arn" {
  description = "Botpress ALB ARN"
  value       = var.enable_botpress_servers ? aws_lb.botpress[0].arn : null
}

output "app_asg_name" {
  description = "App ASG name"
  value       = var.enable_app_servers ? aws_autoscaling_group.app[0].name : null
}

output "api_asg_name" {
  description = "API ASG name"
  value       = var.enable_api_servers ? aws_autoscaling_group.api[0].name : null
}

output "botpress_asg_name" {
  description = "Botpress ASG name"
  value       = var.enable_botpress_servers ? aws_autoscaling_group.botpress[0].name : null
}

output "rabbitmq_instance_id" {
  description = "RabbitMQ instance ID"
  value       = var.enable_rabbitmq_servers ? aws_instance.rabbitmq[0].id : null
}

output "rabbitmq_private_ip" {
  description = "RabbitMQ private IP address"
  value       = var.enable_rabbitmq_servers ? aws_instance.rabbitmq[0].private_ip : null
}

output "ml_asg_name" {
  description = "ML ASG name"
  value       = var.enable_ml_servers ? aws_autoscaling_group.ml[0].name : null
}

output "content_asg_name" {
  description = "Content ASG name"
  value       = var.enable_content_servers ? aws_autoscaling_group.content[0].name : null
}

output "integration_asg_name" {
  description = "Integration ASG name"
  value       = var.enable_integration_servers ? aws_autoscaling_group.integration[0].name : null
}

output "logging_asg_name" {
  description = "Logging ASG name"
  value       = var.enable_logging_servers ? aws_autoscaling_group.logging[0].name : null
}

#------------------------------------------------------------------------------
# CloudFront Outputs (Single Distribution)
#------------------------------------------------------------------------------

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.main[0].domain_name : null
}

output "cloudfront_id" {
  description = "CloudFront distribution ID"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.main[0].id : null
}

# Legacy outputs for backward compatibility
output "app_cloudfront_domain_name" {
  description = "CloudFront distribution domain name (legacy - use cloudfront_domain_name)"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.main[0].domain_name : null
}

output "botpress_cloudfront_domain_name" {
  description = "CloudFront distribution domain name (legacy - use cloudfront_domain_name)"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.main[0].domain_name : null
}

#------------------------------------------------------------------------------
# Outputs for Monitoring (ARN Suffixes)
#------------------------------------------------------------------------------

output "app_alb_arn_suffix" {
  description = "App ALB ARN suffix for CloudWatch"
  value       = var.enable_app_servers ? aws_lb.app[0].arn_suffix : null
}

output "api_alb_arn_suffix" {
  description = "API ALB ARN suffix for CloudWatch"
  value       = var.enable_api_servers ? aws_lb.api[0].arn_suffix : null
}

output "app_target_group_arn_suffix" {
  description = "App target group ARN suffix for CloudWatch"
  value       = var.enable_app_servers ? aws_lb_target_group.app[0].arn_suffix : null
}

output "api_target_group_arn_suffix" {
  description = "API target group ARN suffix for CloudWatch"
  value       = var.enable_api_servers ? aws_lb_target_group.api[0].arn_suffix : null
}
