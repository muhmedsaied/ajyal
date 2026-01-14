###############################################################################
# VPC Module Variables
# Segregated /20 Subnets (4,091 usable IPs each)
###############################################################################

variable "environment" {
  default = "preprod"
}

variable "aws_region" {
  default = "eu-west-1"
}

#------------------------------------------------------------------------------
# VPC CIDR: /16 = 65,536 IPs
# Supports 4 x /20 subnets with room for future expansion
#------------------------------------------------------------------------------

variable "vpc_cidr" {
  default = "10.40.0.0/16"
}

#------------------------------------------------------------------------------
# SUBNET SEGREGATION (/20 = 4,096 IPs each, 4,091 usable)
#
# ┌─────────────────────────────────────────────────────────────────────┐
# │ Tier        │ CIDR Block      │ IP Range                 │ Purpose  │
# ├─────────────────────────────────────────────────────────────────────┤
# │ PUBLIC      │ 10.40.0.0/20    │ 10.40.0.1 - 10.40.15.254 │ ALB, NAT │
# │ WEB         │ 10.40.16.0/20   │ 10.40.16.1 - 10.40.31.254│ Frontend │
# │ APP         │ 10.40.32.0/20   │ 10.40.32.1 - 10.40.47.254│ Backend  │
# │ DATA        │ 10.40.48.0/20   │ 10.40.48.1 - 10.40.63.254│ RDS,Redis│
# └─────────────────────────────────────────────────────────────────────┘
#
# Remaining: 10.40.64.0/18 (16,384 IPs) reserved for future use
#------------------------------------------------------------------------------

variable "public_subnet_cidr" {
  description = "Public subnet - ALB, NAT Gateway, Bastion"
  default     = "10.40.0.0/20"
}

variable "private_web_cidr" {
  description = "Web tier - Windows App servers, Botpress"
  default     = "10.40.16.0/20"
}

variable "private_app_cidr" {
  description = "App tier - Windows API, Integration, RabbitMQ"
  default     = "10.40.32.0/20"
}

variable "private_data_cidr" {
  description = "Data tier - RDS, PostgreSQL, Redis, OpenSearch (AZ1)"
  default     = "10.40.48.0/20"
}

variable "private_data_cidr_az2" {
  description = "Data tier (AZ2) - Required for RDS Multi-AZ (from reserved space)"
  default     = "10.40.64.0/20"
}

variable "public_subnet_cidr_az2" {
  description = "Public subnet (AZ2) - Required for ALBs"
  default     = "10.40.80.0/20"
}

variable "private_app_cidr_az2" {
  description = "App tier (AZ2) - Required for internal ALBs"
  default     = "10.40.96.0/20"
}

variable "availability_zone_2" {
  default = "eu-west-1b"
}

variable "enable_nat_gateway" {
  default = true
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs (disabled for preprod to save costs)"
  default     = false
}
