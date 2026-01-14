###############################################################################
# Storage Module Outputs
###############################################################################

output "content_efs_id" {
  description = "Content EFS file system ID"
  value       = var.enable_content_efs ? aws_efs_file_system.content[0].id : null
}

output "content_efs_dns_name" {
  description = "Content EFS DNS name"
  value       = var.enable_content_efs ? aws_efs_file_system.content[0].dns_name : null
}

output "content_efs_access_point_id" {
  description = "Content EFS access point ID"
  value       = var.enable_content_efs ? aws_efs_access_point.content[0].id : null
}

output "ml_efs_id" {
  description = "ML EFS file system ID"
  value       = var.enable_ml_efs ? aws_efs_file_system.ml[0].id : null
}

output "ml_efs_dns_name" {
  description = "ML EFS DNS name"
  value       = var.enable_ml_efs ? aws_efs_file_system.ml[0].dns_name : null
}

output "ml_efs_access_point_id" {
  description = "ML EFS access point ID"
  value       = var.enable_ml_efs ? aws_efs_access_point.ml[0].id : null
}

output "backup_bucket_name" {
  description = "Backup S3 bucket name"
  value       = var.enable_backup_bucket ? aws_s3_bucket.backup[0].id : null
}

output "backup_bucket_arn" {
  description = "Backup S3 bucket ARN"
  value       = var.enable_backup_bucket ? aws_s3_bucket.backup[0].arn : null
}

output "logs_bucket_name" {
  description = "Logs S3 bucket name"
  value       = var.enable_logs_bucket ? aws_s3_bucket.logs[0].id : null
}

output "logs_bucket_arn" {
  description = "Logs S3 bucket ARN"
  value       = var.enable_logs_bucket ? aws_s3_bucket.logs[0].arn : null
}

output "artifact_bucket_name" {
  description = "Artifact bucket name (same as backup bucket)"
  value       = var.enable_backup_bucket ? aws_s3_bucket.backup[0].id : null
}

output "deployment_bucket_name" {
  description = "Deployment S3 bucket name for CodeDeploy"
  value       = var.enable_deployment_bucket ? aws_s3_bucket.deployment[0].id : null
}

output "deployment_bucket_arn" {
  description = "Deployment S3 bucket ARN"
  value       = var.enable_deployment_bucket ? aws_s3_bucket.deployment[0].arn : null
}
