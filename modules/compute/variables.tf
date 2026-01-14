###############################################################################
# Compute Module Variables
###############################################################################

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALBs (multi-AZ)"
  type        = list(string)
  default     = []
}

variable "private_web_subnet_id" {
  description = "Private web tier subnet ID"
  type        = string
}

variable "private_app_subnet_id" {
  description = "Private app tier subnet ID"
  type        = string
}

variable "private_app_subnet_ids" {
  description = "List of private app subnet IDs for internal ALBs (multi-AZ)"
  type        = list(string)
  default     = []
}

variable "windows_security_group_id" {
  description = "Windows server security group ID"
  type        = string
}

variable "linux_security_group_id" {
  description = "Linux server security group ID"
  type        = string
}

variable "alb_security_group_id" {
  description = "ALB security group ID"
  type        = string
}

variable "instance_profile_name" {
  description = "IAM instance profile name"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
}

variable "content_efs_id" {
  description = "Content EFS ID"
  type        = string
  default     = ""
}

variable "ml_efs_id" {
  description = "ML EFS ID"
  type        = string
  default     = ""
}

variable "enable_codedeploy" {
  description = "Enable CodeDeploy"
  type        = bool
  default     = true
}

# Windows App Servers
variable "enable_app_servers" {
  description = "Enable App Servers"
  type        = bool
  default     = true
}

variable "app_server_instance_type" {
  description = "App Server instance type"
  type        = string
  default     = "c5.2xlarge"
}

variable "app_server_min_size" {
  description = "App Server ASG minimum size"
  type        = number
  default     = 2
}

variable "app_server_max_size" {
  description = "App Server ASG maximum size"
  type        = number
  default     = 20
}

variable "app_server_desired_size" {
  description = "App Server ASG desired size"
  type        = number
  default     = 2
}

# Windows API Servers
variable "enable_api_servers" {
  description = "Enable API Servers"
  type        = bool
  default     = true
}

variable "api_server_instance_type" {
  description = "API Server instance type"
  type        = string
  default     = "t3.xlarge"
}

variable "api_server_min_size" {
  description = "API Server ASG minimum size"
  type        = number
  default     = 2
}

variable "api_server_max_size" {
  description = "API Server ASG maximum size"
  type        = number
  default     = 10
}

# Windows Integration Servers
variable "enable_integration_servers" {
  description = "Enable Integration Servers"
  type        = bool
  default     = true
}

variable "integration_server_instance_type" {
  description = "Integration Server instance type"
  type        = string
  default     = "t3.xlarge"
}

variable "integration_server_min_size" {
  description = "Integration Server ASG minimum size"
  type        = number
  default     = 2
}

variable "integration_server_max_size" {
  description = "Integration Server ASG maximum size"
  type        = number
  default     = 10
}

# Windows Logging Servers
variable "enable_logging_servers" {
  description = "Enable Logging Servers"
  type        = bool
  default     = true
}

variable "logging_server_instance_type" {
  description = "Logging Server instance type"
  type        = string
  default     = "t3.xlarge"
}

variable "logging_server_min_size" {
  description = "Logging Server ASG minimum size"
  type        = number
  default     = 2
}

variable "logging_server_max_size" {
  description = "Logging Server ASG maximum size"
  type        = number
  default     = 4
}

# Linux RabbitMQ Server (Single Instance - No ASG)
variable "enable_rabbitmq_servers" {
  description = "Enable RabbitMQ Server"
  type        = bool
  default     = true
}

variable "rabbitmq_instance_type" {
  description = "RabbitMQ instance type"
  type        = string
  default     = "t3.medium" # Single instance for preprod
}

# Linux Botpress Servers
variable "enable_botpress_servers" {
  description = "Enable Botpress Servers"
  type        = bool
  default     = true
}

variable "botpress_instance_type" {
  description = "Botpress instance type"
  type        = string
  default     = "c5.xlarge"
}

variable "botpress_min_size" {
  description = "Botpress ASG minimum size"
  type        = number
  default     = 2
}

variable "botpress_max_size" {
  description = "Botpress ASG maximum size"
  type        = number
  default     = 3
}

# Linux ML Servers
variable "enable_ml_servers" {
  description = "Enable ML Servers"
  type        = bool
  default     = true
}

variable "ml_server_instance_type" {
  description = "ML Server instance type"
  type        = string
  default     = "c5.2xlarge"
}

variable "ml_server_min_size" {
  description = "ML Server ASG minimum size"
  type        = number
  default     = 2
}

variable "ml_server_max_size" {
  description = "ML Server ASG maximum size"
  type        = number
  default     = 4
}

# Linux Content Servers
variable "enable_content_servers" {
  description = "Enable Content Servers"
  type        = bool
  default     = true
}

variable "content_server_instance_type" {
  description = "Content Server instance type"
  type        = string
  default     = "c5.2xlarge"
}

variable "content_server_min_size" {
  description = "Content Server ASG minimum size"
  type        = number
  default     = 2
}

variable "content_server_max_size" {
  description = "Content Server ASG maximum size"
  type        = number
  default     = 8
}

#------------------------------------------------------------------------------
# CloudFront CDN
#------------------------------------------------------------------------------

variable "enable_cloudfront" {
  description = "Enable CloudFront CDN"
  type        = bool
  default     = true
}

variable "cloudfront_price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100" # Use only North America and Europe
}

variable "waf_web_acl_arn" {
  description = "WAF Web ACL ARN for CloudFront (optional)"
  type        = string
  default     = ""
}

variable "cloudfront_secret_header" {
  description = "Secret header value to validate requests come from CloudFront"
  type        = string
  default     = "ajyal-cf-secret-2024"
  sensitive   = true
}
