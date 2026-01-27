variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "preprod"
}

variable "enable_schedule" {
  description = "Enable/disable the scheduled stop/start rules"
  type        = bool
  default     = true
}

variable "stop_cron_expression" {
  description = "Cron expression for stop schedule (UTC). Default: 10 PM Jordan time = 19:00 UTC"
  type        = string
  # Jordan time is UTC+3
  # 10 PM Jordan = 22:00 - 3 = 19:00 UTC
  # Daily = every day
  default = "cron(0 19 * * ? *)"
}

variable "start_cron_expression" {
  description = "Cron expression for start schedule (UTC). Default: 7 AM Jordan time = 04:00 UTC"
  type        = string
  # Jordan time is UTC+3
  # 7 AM Jordan = 07:00 - 3 = 04:00 UTC
  # Daily = every day
  default = "cron(0 4 * * ? *)"
}
