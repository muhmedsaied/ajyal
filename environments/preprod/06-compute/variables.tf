###############################################################################
# Compute Module Variables - Cost Optimized for PreProd
###############################################################################

variable "environment" {
  default = "preprod"
}

variable "aws_region" {
  default = "eu-west-1"
}

variable "enable_codedeploy" {
  default = true
}

#------------------------------------------------------------------------------
# Windows Servers - Cost Optimized (t3 instead of c5)
#------------------------------------------------------------------------------

variable "enable_app_servers" {
  default = true
}

variable "app_server_instance_type" {
  default = "t3.medium" # Cost optimized
}

variable "app_server_min_size" {
  default = 1
}

variable "app_server_max_size" {
  default = 1
}

variable "app_server_desired_size" {
  default = 1
}

variable "enable_api_servers" {
  default = true
}

variable "api_server_instance_type" {
  default = "t3.medium"
}

variable "api_server_min_size" {
  default = 2
}

variable "api_server_max_size" {
  default = 2
}

variable "enable_integration_servers" {
  default = true
}

variable "integration_server_instance_type" {
  default = "t3.small"
}

variable "integration_server_min_size" {
  default = 2
}

variable "integration_server_max_size" {
  default = 2
}

variable "enable_integration_nlb" {
  description = "Enable Network Load Balancer with static IPs for Integration Servers"
  default     = true
}

variable "enable_logging_servers" {
  default = true
}

variable "logging_server_instance_type" {
  default = "t3.small"
}

variable "logging_server_min_size" {
  default = 0
}

variable "logging_server_max_size" {
  default = 0
}

#------------------------------------------------------------------------------
# Custom AMI Support (Golden Image)
#------------------------------------------------------------------------------

variable "use_custom_windows_ami" {
  default = true
}

variable "custom_windows_ami_id" {
  default = "ami-09b0bf2ddf943f4d6"  # Golden AMI with IIS, ASP.NET 4.5, URL Rewrite, WebSockets (2026-01-21)
}

variable "windows_key_name" {
  default = "preprod-ajyal-rdp"
}

variable "windows_admin_password_secret_id" {
  default = "preprod-ajyal/windows/admin-password"
}

variable "install_prerequisites_on_launch" {
  default = false
}

variable "prerequisites_s3_bucket" {
  default = ""
}

#------------------------------------------------------------------------------
# Linux Servers - Cost Optimized (t3 instead of c5)
#------------------------------------------------------------------------------

# RabbitMQ - Single Instance (No ASG, No CodeDeploy)
variable "enable_rabbitmq_servers" {
  default = true
}

variable "rabbitmq_instance_type" {
  default = "t3.small" # Single instance for preprod
}

variable "enable_botpress_servers" {
  default = true
}

variable "botpress_instance_type" {
  default = "t3.small"
}

variable "botpress_min_size" {
  default = 0
}

variable "botpress_max_size" {
  default = 0
}

variable "enable_ml_servers" {
  default = true
}

variable "ml_server_instance_type" {
  default = "t3.medium"
}

variable "ml_server_min_size" {
  default = 0
}

variable "ml_server_max_size" {
  default = 0
}

variable "enable_content_servers" {
  default = true
}

variable "content_server_instance_type" {
  default = "t3.medium"
}

variable "content_server_min_size" {
  default = 0
}

variable "content_server_max_size" {
  default = 0
}

#------------------------------------------------------------------------------
# CloudFront CDN
#------------------------------------------------------------------------------

variable "enable_cloudfront" {
  default = true
}

variable "cloudfront_price_class" {
  default = "PriceClass_100" # North America and Europe only (cost optimized)
}

variable "cloudfront_domain_aliases" {
  description = "Custom domain aliases for CloudFront"
  default     = ["ajyallmsstg.moe.gov.jo"]
}

variable "cloudfront_acm_certificate_arn" {
  description = "ACM certificate ARN for CloudFront (must be in us-east-1)"
  default     = "arn:aws:acm:us-east-1:946846709937:certificate/8a35fe44-2a12-4f8b-bdbf-cfda844f79ea"
}

variable "integration_nlb_acm_certificate_arn" {
  description = "ACM certificate ARN for Integration NLB HTTPS (in eu-west-1)"
  default     = "arn:aws:acm:eu-west-1:946846709937:certificate/bfc773e7-8a47-4939-816e-71ec02c31a58"
}
