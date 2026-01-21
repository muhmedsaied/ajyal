###############################################################################
# CI/CD Module Outputs
###############################################################################

output "instance_profile_name" {
  description = "EC2 instance profile name"
  value       = aws_iam_instance_profile.ec2.name
}

output "instance_profile_arn" {
  description = "EC2 instance profile ARN"
  value       = aws_iam_instance_profile.ec2.arn
}

output "ec2_role_arn" {
  description = "EC2 IAM role ARN"
  value       = aws_iam_role.ec2_instance.arn
}

output "codedeploy_windows_app_name" {
  description = "CodeDeploy Windows application name"
  value       = var.enable_codedeploy && !var.enable_codedeploy_per_service ? aws_codedeploy_app.windows[0].name : null
}

output "codedeploy_linux_app_name" {
  description = "CodeDeploy Linux application name"
  value       = var.enable_codedeploy && !var.enable_codedeploy_per_service ? aws_codedeploy_app.linux[0].name : null
}

output "codedeploy_role_arn" {
  description = "CodeDeploy IAM role ARN"
  value       = var.enable_codedeploy ? aws_iam_role.codedeploy[0].arn : null
}

output "codepipeline_role_arn" {
  description = "CodePipeline IAM role ARN"
  value       = var.enable_codepipeline ? aws_iam_role.codepipeline[0].arn : null
}

#------------------------------------------------------------------------------
# Deployment Group Outputs
#------------------------------------------------------------------------------

output "windows_app_deployment_group" {
  description = "Windows App deployment group name"
  value       = var.enable_codedeploy && !var.enable_codedeploy_per_service ? aws_codedeploy_deployment_group.windows_app[0].deployment_group_name : null
}

output "windows_api_deployment_group" {
  description = "Windows API deployment group name"
  value       = var.enable_codedeploy && !var.enable_codedeploy_per_service ? aws_codedeploy_deployment_group.windows_api[0].deployment_group_name : null
}

output "windows_integration_deployment_group" {
  description = "Windows Integration deployment group name"
  value       = var.enable_codedeploy && !var.enable_codedeploy_per_service ? aws_codedeploy_deployment_group.windows_integration[0].deployment_group_name : null
}

output "windows_logging_deployment_group" {
  description = "Windows Logging deployment group name"
  value       = var.enable_codedeploy && !var.enable_codedeploy_per_service ? aws_codedeploy_deployment_group.windows_logging[0].deployment_group_name : null
}

# RabbitMQ - No CodeDeploy (single instance service)

output "linux_botpress_deployment_group" {
  description = "Linux Botpress deployment group name"
  value       = var.enable_codedeploy && !var.enable_codedeploy_per_service ? aws_codedeploy_deployment_group.linux_botpress[0].deployment_group_name : null
}

output "linux_ml_deployment_group" {
  description = "Linux ML deployment group name"
  value       = var.enable_codedeploy && !var.enable_codedeploy_per_service ? aws_codedeploy_deployment_group.linux_ml[0].deployment_group_name : null
}

output "linux_content_deployment_group" {
  description = "Linux Content deployment group name"
  value       = var.enable_codedeploy && !var.enable_codedeploy_per_service ? aws_codedeploy_deployment_group.linux_content[0].deployment_group_name : null
}

#------------------------------------------------------------------------------
# Client Deployment User Outputs
#------------------------------------------------------------------------------

output "client_deploy_user_name" {
  description = "Client deployment IAM user name"
  value       = var.enable_client_deploy_user ? aws_iam_user.client_deploy[0].name : null
}

output "client_deploy_user_arn" {
  description = "Client deployment IAM user ARN"
  value       = var.enable_client_deploy_user ? aws_iam_user.client_deploy[0].arn : null
}

output "client_deploy_policy_arn" {
  description = "Client deployment IAM policy ARN"
  value       = var.enable_client_deploy_user ? aws_iam_policy.client_deploy[0].arn : null
}
