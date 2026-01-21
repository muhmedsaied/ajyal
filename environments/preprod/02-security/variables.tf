###############################################################################
# Security Module Variables
###############################################################################

variable "environment" {
  default = "preprod"
}

variable "aws_region" {
  default = "eu-west-1"
}

variable "enable_waf" {
  default = true
}

variable "enable_guardduty" {
  default = true
}

variable "enable_security_hub" {
  default = false # OFF for preprod cost savings
}

variable "enable_config" {
  default = false # OFF for preprod cost savings
}

variable "enable_trend_micro" {
  default = true
}

variable "vpn_access_cidr_blocks" {
  default = ["10.40.90.167/32"]
}

variable "waf_rate_limit" {
  default = 2000
}

variable "waf_block_mode" {
  default = true
}

variable "enable_integration_nlb" {
  description = "Enable security group rules for Integration NLB"
  default     = true
}
