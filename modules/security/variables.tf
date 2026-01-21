###############################################################################
# Security Module Variables
###############################################################################

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "enable_waf" {
  description = "Enable AWS WAF"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "WAF rate limit (requests per 5 minutes)"
  type        = number
  default     = 2000
}

variable "waf_block_mode" {
  description = "Enable WAF block mode (false = count only)"
  type        = bool
  default     = true
}

variable "enable_guardduty" {
  description = "Enable AWS GuardDuty"
  type        = bool
  default     = true
}

variable "enable_security_hub" {
  description = "Enable AWS Security Hub"
  type        = bool
  default     = true
}

variable "enable_config" {
  description = "Enable AWS Config"
  type        = bool
  default     = true
}

variable "enable_trend_micro" {
  description = "Enable Trend Micro endpoint protection"
  type        = bool
  default     = true
}

variable "vpn_access_cidr_blocks" {
  description = "CIDR blocks allowed to access servers via VPN"
  type        = list(string)
  default     = []
}

variable "enable_integration_nlb" {
  description = "Enable security group rules for Integration NLB (allows public traffic on ports 80/443)"
  type        = bool
  default     = false
}
