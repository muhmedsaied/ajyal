###############################################################################
# VPC Module Variables
###############################################################################

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "availability_zone" {
  description = "Availability zone for single-AZ deployment"
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
}

variable "private_web_cidr" {
  description = "CIDR block for private web tier subnet"
  type        = string
}

variable "private_app_cidr" {
  description = "CIDR block for private app tier subnet"
  type        = string
}

variable "private_data_cidr" {
  description = "CIDR block for private data tier subnet (AZ1)"
  type        = string
}

variable "private_data_cidr_az2" {
  description = "CIDR block for private data tier subnet (AZ2) - required for RDS"
  type        = string
}

variable "public_subnet_cidr_az2" {
  description = "CIDR block for public subnet AZ2 - required for ALBs"
  type        = string
  default     = ""
}

variable "private_app_cidr_az2" {
  description = "CIDR block for private app tier subnet AZ2 - required for internal ALBs"
  type        = string
  default     = ""
}

variable "availability_zone_2" {
  description = "Second availability zone for multi-AZ resources (RDS, ALB)"
  type        = string
  default     = ""
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway"
  type        = bool
  default     = true
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = true
}
