variable "environment" {
  default = "preprod"
}

variable "aws_region" {
  default = "eu-west-1"
}

variable "zone_name" {
  description = "Private DNS zone name"
  default     = "lms.internal"
}
