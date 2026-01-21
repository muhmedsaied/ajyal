variable "zone_name" {
  description = "Private DNS zone name"
  type        = string
  default     = "lms.internal"
}

variable "vpc_id" {
  description = "VPC ID to associate with the private hosted zone"
  type        = string
}

variable "api_alb_arn" {
  description = "API ALB ARN"
  type        = string
  default     = ""
}

variable "app_alb_arn" {
  description = "App ALB ARN"
  type        = string
  default     = ""
}

variable "botpress_alb_arn" {
  description = "Botpress ALB ARN"
  type        = string
  default     = ""
}

variable "mssql_endpoint" {
  description = "MSSQL RDS endpoint"
  type        = string
  default     = ""
}

variable "aurora_endpoint" {
  description = "Aurora PostgreSQL writer endpoint"
  type        = string
  default     = ""
}

variable "aurora_reader_endpoint" {
  description = "Aurora PostgreSQL reader endpoint"
  type        = string
  default     = ""
}

variable "redis_endpoint" {
  description = "Redis primary endpoint"
  type        = string
  default     = ""
}

variable "opensearch_endpoint" {
  description = "OpenSearch endpoint (optional override)"
  type        = string
  default     = ""
}

variable "opensearch_domain_name" {
  description = "OpenSearch domain name (used to resolve VPC endpoint)"
  type        = string
  default     = ""
}

variable "rabbitmq_private_ip" {
  description = "RabbitMQ server private IP address"
  type        = string
  default     = ""
}
