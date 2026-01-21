resource "aws_route53_zone" "internal" {
  name = var.zone_name

  vpc {
    vpc_id = var.vpc_id
  }

  comment       = "Private zone for Ajyal internal services"
  force_destroy = false
}

data "aws_lb" "api" {
  count = var.api_alb_arn != "" ? 1 : 0
  arn   = var.api_alb_arn
}

data "aws_lb" "app" {
  count = var.app_alb_arn != "" ? 1 : 0
  arn   = var.app_alb_arn
}

data "aws_lb" "botpress" {
  count = var.botpress_alb_arn != "" ? 1 : 0
  arn   = var.botpress_alb_arn
}

data "aws_opensearch_domain" "main" {
  count       = var.opensearch_domain_name != "" ? 1 : 0
  domain_name = var.opensearch_domain_name
}

locals {
  alb_records = {
    api = try({
      dns_name = data.aws_lb.api[0].dns_name
      zone_id  = data.aws_lb.api[0].zone_id
    }, null)
    app = try({
      dns_name = data.aws_lb.app[0].dns_name
      zone_id  = data.aws_lb.app[0].zone_id
    }, null)
    botpress = try({
      dns_name = data.aws_lb.botpress[0].dns_name
      zone_id  = data.aws_lb.botpress[0].zone_id
    }, null)
  }

  alb_records_filtered = {
    for name, record in local.alb_records : name => record if record != null
  }

  resolved_opensearch_endpoint = var.opensearch_endpoint != "" ? var.opensearch_endpoint : try(
    data.aws_opensearch_domain.main[0].endpoint,
    ""
  )

  db_records = {
    mssql      = var.mssql_endpoint
    aurora     = var.aurora_endpoint
    aurora_ro  = var.aurora_reader_endpoint
    redis      = var.redis_endpoint
    opensearch = local.resolved_opensearch_endpoint
  }

  db_records_filtered = {
    for name, record in local.db_records : name => record if record != "" && record != null
  }
}

resource "aws_route53_record" "alb" {
  for_each = local.alb_records_filtered

  zone_id = aws_route53_zone.internal.zone_id
  name    = "${each.key}.${var.zone_name}"
  type    = "A"

  alias {
    name                   = each.value.dns_name
    zone_id                = each.value.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "db" {
  for_each = local.db_records_filtered

  zone_id = aws_route53_zone.internal.zone_id
  name    = "${each.key}.${var.zone_name}"
  type    = "CNAME"
  ttl     = 60
  records = [each.value]
}

# RabbitMQ A record (uses IP address, not CNAME)
resource "aws_route53_record" "rabbitmq" {
  count = var.rabbitmq_private_ip != "" ? 1 : 0

  zone_id = aws_route53_zone.internal.zone_id
  name    = "rabbitmq.${var.zone_name}"
  type    = "A"
  ttl     = 60
  records = [var.rabbitmq_private_ip]
}
