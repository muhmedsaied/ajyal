###############################################################################
# Budget Variables
###############################################################################

variable "environment" {
  description = "Environment name"
  default     = "preprod"
}

variable "aws_region" {
  description = "AWS region"
  default     = "eu-west-1"
}

variable "budget_limit" {
  description = "Monthly budget limit in USD"
  default     = "3000"
}

variable "alert_emails" {
  description = "Email addresses to receive budget alerts"
  type        = list(string)
  default     = ["your-email@example.com"]  # UPDATE THIS with your email
}
