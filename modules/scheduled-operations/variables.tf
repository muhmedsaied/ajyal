variable "environment" {
  description = "Environment name (e.g., preprod, prod)"
  type        = string
}

variable "enable_schedule" {
  description = "Enable/disable the scheduled stop/start rules"
  type        = bool
  default     = true
}

variable "stop_cron_expression" {
  description = "Cron expression for stop schedule (UTC). Default: 10 PM Jordan time = 19:00 UTC"
  type        = string
  default     = "cron(0 19 * * ? *)"  # Daily at 19:00 UTC (10 PM Jordan)
}

variable "start_cron_expression" {
  description = "Cron expression for start schedule (UTC). Default: 7 AM Jordan time = 04:00 UTC"
  type        = string
  default     = "cron(0 4 * * ? *)"  # Daily at 04:00 UTC (7 AM Jordan)
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
