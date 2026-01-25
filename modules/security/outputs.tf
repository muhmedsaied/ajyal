###############################################################################
# Security Module Outputs
###############################################################################

output "kms_key_arn" {
  description = "KMS key ARN"
  value       = aws_kms_key.main.arn
}

output "kms_key_id" {
  description = "KMS key ID"
  value       = aws_kms_key.main.key_id
}

output "waf_acl_arn" {
  description = "WAF Web ACL ARN"
  value       = var.enable_waf ? aws_wafv2_web_acl.main[0].arn : null
}

output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "windows_server_security_group_id" {
  description = "Windows server security group ID"
  value       = aws_security_group.windows_server.id
}

output "linux_server_security_group_id" {
  description = "Linux server security group ID"
  value       = aws_security_group.linux_server.id
}

output "integration_server_security_group_id" {
  description = "Integration server security group ID (separate from Windows SG for DB access control)"
  value       = aws_security_group.integration_server.id
}

output "database_security_group_id" {
  description = "Database security group ID"
  value       = aws_security_group.database.id
}

output "efs_security_group_id" {
  description = "EFS security group ID"
  value       = aws_security_group.efs.id
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = var.enable_guardduty ? aws_guardduty_detector.main[0].id : null
}
