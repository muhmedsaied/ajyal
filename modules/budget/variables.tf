###############################################################################
# Budget Module Variables
###############################################################################

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "budget_limit" {
  description = "Monthly budget limit in USD"
  type        = string
  default     = "3000"
}

variable "alert_emails" {
  description = "List of email addresses to receive budget alerts"
  type        = list(string)
}

variable "linked_account_id" {
  description = "AWS account ID to filter costs (optional, for organization accounts)"
  type        = string
  default     = ""
}
