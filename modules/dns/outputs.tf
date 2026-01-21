output "zone_id" {
  description = "Private hosted zone ID"
  value       = aws_route53_zone.internal.zone_id
}

output "zone_name" {
  description = "Private hosted zone name"
  value       = aws_route53_zone.internal.name
}

output "alb_record_fqdns" {
  description = "FQDNs for ALB records"
  value       = [for name in keys(aws_route53_record.alb) : aws_route53_record.alb[name].fqdn]
}

output "db_record_fqdns" {
  description = "FQDNs for DB records"
  value       = [for name in keys(aws_route53_record.db) : aws_route53_record.db[name].fqdn]
}

output "rabbitmq_fqdn" {
  description = "FQDN for RabbitMQ record"
  value       = var.rabbitmq_private_ip != "" ? aws_route53_record.rabbitmq[0].fqdn : null
}

#------------------------------------------------------------------------------
# Individual DNS Names for SSM Parameters
#------------------------------------------------------------------------------

output "api_dns_name" {
  description = "Internal DNS name for API ALB"
  value       = var.api_alb_arn != "" ? "api.${var.zone_name}" : null
}

output "app_dns_name" {
  description = "Internal DNS name for App ALB"
  value       = var.app_alb_arn != "" ? "app.${var.zone_name}" : null
}

output "botpress_dns_name" {
  description = "Internal DNS name for Botpress ALB"
  value       = var.botpress_alb_arn != "" ? "botpress.${var.zone_name}" : null
}

output "mssql_dns_name" {
  description = "Internal DNS name for MSSQL"
  value       = var.mssql_endpoint != "" ? "mssql.${var.zone_name}" : null
}

output "aurora_dns_name" {
  description = "Internal DNS name for Aurora PostgreSQL writer"
  value       = var.aurora_endpoint != "" ? "aurora.${var.zone_name}" : null
}

output "aurora_reader_dns_name" {
  description = "Internal DNS name for Aurora PostgreSQL reader"
  value       = var.aurora_reader_endpoint != "" ? "aurora_ro.${var.zone_name}" : null
}

output "redis_dns_name" {
  description = "Internal DNS name for Redis"
  value       = var.redis_endpoint != "" ? "redis.${var.zone_name}" : null
}

output "opensearch_dns_name" {
  description = "Internal DNS name for OpenSearch"
  value       = local.resolved_opensearch_endpoint != "" ? "opensearch.${var.zone_name}" : null
}

output "rabbitmq_dns_name" {
  description = "Internal DNS name for RabbitMQ"
  value       = var.rabbitmq_private_ip != "" ? "rabbitmq.${var.zone_name}" : null
}
