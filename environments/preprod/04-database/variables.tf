###############################################################################
# Database Module Variables - Cost Optimized for PreProd
###############################################################################

variable "environment" {
  default = "preprod"
}

variable "aws_region" {
  default = "eu-west-1"
}

# MS SQL Server
variable "enable_mssql" {
  default = true
}

variable "mssql_instance_class" {
  default = "db.t3.medium" # Reduced size for cost savings
}

variable "mssql_allocated_storage" {
  default = 100 # Initial storage
}

variable "mssql_max_allocated_storage" {
  default = 200 # Auto-scales up to 200GB
}

#------------------------------------------------------------------------------
# Aurora PostgreSQL (Serverless v2)
# Storage auto-scales automatically, capacity uses ACUs
#------------------------------------------------------------------------------

variable "enable_postgresql" {
  default = true
}

variable "aurora_min_capacity" {
  default = 0.5 # Minimum ACUs (cost savings for preprod)
}

variable "aurora_max_capacity" {
  default = 4 # Maximum ACUs (enough for preprod)
}

# OpenSearch
variable "enable_opensearch" {
  default = true
}

variable "opensearch_instance_type" {
  default = "t3.medium.search" # Cost optimized
}

variable "opensearch_instance_count" {
  default = 1 # Single node for preprod
}

variable "opensearch_volume_size" {
  default = 50
}

# Redis
variable "enable_redis" {
  default = true
}

variable "redis_node_type" {
  default = "cache.t3.medium" # Cost optimized
}

variable "redis_num_cache_nodes" {
  default = 1 # Single node for preprod
}

# Backup
variable "backup_retention_period" {
  default = 3
}

variable "enable_deletion_protection" {
  default = false
}
