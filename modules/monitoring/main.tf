###############################################################################
# Monitoring Module
# CloudWatch Alarms, Dashboards, CloudTrail, SIEM Integration
###############################################################################

locals {
  name_prefix = "${var.environment}-ajyal"
}

#------------------------------------------------------------------------------
# SNS Topic for Alarms
#------------------------------------------------------------------------------

resource "aws_sns_topic" "alarms" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  name  = "${local.name_prefix}-alarms"

  tags = {
    Name = "${local.name_prefix}-alarms"
  }
}

resource "aws_sns_topic_subscription" "alarm_emails" {
  for_each  = var.enable_cloudwatch_alarms ? toset(var.alarm_emails) : toset([])
  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = each.value
}

#------------------------------------------------------------------------------
# CloudWatch Log Groups
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "application" {
  name              = "/ajyal/${var.environment}/application"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.name_prefix}-application-logs"
  }
}

resource "aws_cloudwatch_log_group" "windows" {
  name              = "/ajyal/${var.environment}/windows"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.name_prefix}-windows-logs"
  }
}

resource "aws_cloudwatch_log_group" "linux" {
  name              = "/ajyal/${var.environment}/linux"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.name_prefix}-linux-logs"
  }
}

#------------------------------------------------------------------------------
# CloudWatch Alarms
#------------------------------------------------------------------------------

# High CPU Alarm
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${local.name_prefix}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_threshold
  alarm_description   = "CPU utilization above ${var.cpu_threshold}%"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  tags = {
    Name = "${local.name_prefix}-high-cpu-alarm"
  }
}

# RDS CPU Alarm
resource "aws_cloudwatch_metric_alarm" "rds_high_cpu" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${local.name_prefix}-rds-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_threshold
  alarm_description   = "RDS CPU utilization above ${var.cpu_threshold}%"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  tags = {
    Name = "${local.name_prefix}-rds-high-cpu-alarm"
  }
}

# ALB 5xx Error Alarm
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${local.name_prefix}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "ALB 5xx errors above threshold"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  tags = {
    Name = "${local.name_prefix}-alb-5xx-alarm"
  }
}

# Redis CPU Alarm
resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  count               = var.enable_cloudwatch_alarms && var.redis_cluster_id != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-redis-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_threshold
  alarm_description   = "Redis CPU utilization above ${var.cpu_threshold}%"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    CacheClusterId = var.redis_cluster_id
  }

  tags = {
    Name = "${local.name_prefix}-redis-cpu-alarm"
  }
}

# Redis Memory Alarm
resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  count               = var.enable_cloudwatch_alarms && var.redis_cluster_id != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-redis-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = var.memory_threshold
  alarm_description   = "Redis memory usage above ${var.memory_threshold}%"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    CacheClusterId = var.redis_cluster_id
  }

  tags = {
    Name = "${local.name_prefix}-redis-memory-alarm"
  }
}

# Redis Evictions Alarm
resource "aws_cloudwatch_metric_alarm" "redis_evictions" {
  count               = var.enable_cloudwatch_alarms && var.redis_cluster_id != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-redis-evictions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Evictions"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Sum"
  threshold           = 100
  alarm_description   = "Redis evictions detected - memory pressure"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    CacheClusterId = var.redis_cluster_id
  }

  tags = {
    Name = "${local.name_prefix}-redis-evictions-alarm"
  }
}

#------------------------------------------------------------------------------
# ASG Alarms - Per Auto Scaling Group
#------------------------------------------------------------------------------

# App ASG CPU Alarm
resource "aws_cloudwatch_metric_alarm" "app_asg_cpu" {
  count               = var.enable_cloudwatch_alarms && var.app_asg_name != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-app-asg-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_threshold
  alarm_description   = "App ASG CPU above ${var.cpu_threshold}%"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    AutoScalingGroupName = var.app_asg_name
  }

  tags = {
    Name = "${local.name_prefix}-app-asg-cpu-alarm"
  }
}

# API ASG CPU Alarm
resource "aws_cloudwatch_metric_alarm" "api_asg_cpu" {
  count               = var.enable_cloudwatch_alarms && var.api_asg_name != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-api-asg-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_threshold
  alarm_description   = "API ASG CPU above ${var.cpu_threshold}%"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    AutoScalingGroupName = var.api_asg_name
  }

  tags = {
    Name = "${local.name_prefix}-api-asg-cpu-alarm"
  }
}

#------------------------------------------------------------------------------
# ALB Alarms - Per Load Balancer
#------------------------------------------------------------------------------

# App ALB Target Response Time
resource "aws_cloudwatch_metric_alarm" "app_alb_response_time" {
  count               = var.enable_cloudwatch_alarms && var.app_alb_arn_suffix != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-app-alb-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 5
  alarm_description   = "App ALB response time above 5 seconds"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    LoadBalancer = var.app_alb_arn_suffix
  }

  tags = {
    Name = "${local.name_prefix}-app-alb-response-alarm"
  }
}

# App ALB Unhealthy Hosts
resource "aws_cloudwatch_metric_alarm" "app_alb_unhealthy" {
  count               = var.enable_cloudwatch_alarms && var.app_target_group_arn_suffix != "" && var.app_alb_arn_suffix != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-app-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "App ALB has unhealthy hosts"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    TargetGroup  = var.app_target_group_arn_suffix
    LoadBalancer = var.app_alb_arn_suffix
  }

  tags = {
    Name = "${local.name_prefix}-app-alb-unhealthy-alarm"
  }
}

# API ALB Target Response Time
resource "aws_cloudwatch_metric_alarm" "api_alb_response_time" {
  count               = var.enable_cloudwatch_alarms && var.api_alb_arn_suffix != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-api-alb-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 3
  alarm_description   = "API ALB response time above 3 seconds"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    LoadBalancer = var.api_alb_arn_suffix
  }

  tags = {
    Name = "${local.name_prefix}-api-alb-response-alarm"
  }
}

# API ALB Unhealthy Hosts
resource "aws_cloudwatch_metric_alarm" "api_alb_unhealthy" {
  count               = var.enable_cloudwatch_alarms && var.api_target_group_arn_suffix != "" && var.api_alb_arn_suffix != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-api-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "API ALB has unhealthy hosts"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    TargetGroup  = var.api_target_group_arn_suffix
    LoadBalancer = var.api_alb_arn_suffix
  }

  tags = {
    Name = "${local.name_prefix}-api-alb-unhealthy-alarm"
  }
}

#------------------------------------------------------------------------------
# Aurora PostgreSQL Alarms
#------------------------------------------------------------------------------

# Aurora CPU Alarm
resource "aws_cloudwatch_metric_alarm" "aurora_cpu" {
  count               = var.enable_cloudwatch_alarms && var.aurora_cluster_id != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-aurora-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_threshold
  alarm_description   = "Aurora CPU above ${var.cpu_threshold}%"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    DBClusterIdentifier = var.aurora_cluster_id
  }

  tags = {
    Name = "${local.name_prefix}-aurora-cpu-alarm"
  }
}

# Aurora Connections Alarm
resource "aws_cloudwatch_metric_alarm" "aurora_connections" {
  count               = var.enable_cloudwatch_alarms && var.aurora_cluster_id != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-aurora-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.db_connections_threshold
  alarm_description   = "Aurora connections above ${var.db_connections_threshold}"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    DBClusterIdentifier = var.aurora_cluster_id
  }

  tags = {
    Name = "${local.name_prefix}-aurora-connections-alarm"
  }
}

# Aurora Serverless Capacity Alarm
resource "aws_cloudwatch_metric_alarm" "aurora_capacity" {
  count               = var.enable_cloudwatch_alarms && var.aurora_cluster_id != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-aurora-high-capacity"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "ServerlessDatabaseCapacity"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.aurora_max_capacity_threshold
  alarm_description   = "Aurora at max capacity - may need to increase limits"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    DBClusterIdentifier = var.aurora_cluster_id
  }

  tags = {
    Name = "${local.name_prefix}-aurora-capacity-alarm"
  }
}

# Aurora Free Storage Alarm
resource "aws_cloudwatch_metric_alarm" "aurora_storage" {
  count               = var.enable_cloudwatch_alarms && var.aurora_cluster_id != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-aurora-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeLocalStorage"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 10737418240 # 10 GB in bytes
  alarm_description   = "Aurora free storage below 10GB"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    DBClusterIdentifier = var.aurora_cluster_id
  }

  tags = {
    Name = "${local.name_prefix}-aurora-storage-alarm"
  }
}

#------------------------------------------------------------------------------
# MSSQL RDS Alarms
#------------------------------------------------------------------------------

# MSSQL CPU Alarm
resource "aws_cloudwatch_metric_alarm" "mssql_cpu" {
  count               = var.enable_cloudwatch_alarms && var.mssql_instance_id != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-mssql-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_threshold
  alarm_description   = "MSSQL CPU above ${var.cpu_threshold}%"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    DBInstanceIdentifier = var.mssql_instance_id
  }

  tags = {
    Name = "${local.name_prefix}-mssql-cpu-alarm"
  }
}

# MSSQL Free Storage Alarm
resource "aws_cloudwatch_metric_alarm" "mssql_storage" {
  count               = var.enable_cloudwatch_alarms && var.mssql_instance_id != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-mssql-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 21474836480 # 20 GB in bytes
  alarm_description   = "MSSQL free storage below 20GB"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    DBInstanceIdentifier = var.mssql_instance_id
  }

  tags = {
    Name = "${local.name_prefix}-mssql-storage-alarm"
  }
}

# MSSQL Connections Alarm
resource "aws_cloudwatch_metric_alarm" "mssql_connections" {
  count               = var.enable_cloudwatch_alarms && var.mssql_instance_id != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-mssql-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.db_connections_threshold
  alarm_description   = "MSSQL connections above ${var.db_connections_threshold}"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    DBInstanceIdentifier = var.mssql_instance_id
  }

  tags = {
    Name = "${local.name_prefix}-mssql-connections-alarm"
  }
}

#------------------------------------------------------------------------------
# OpenSearch Alarms
#------------------------------------------------------------------------------

# OpenSearch Cluster Red Status
resource "aws_cloudwatch_metric_alarm" "opensearch_red" {
  count               = var.enable_cloudwatch_alarms && var.opensearch_domain_name != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-opensearch-cluster-red"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ClusterStatus.red"
  namespace           = "AWS/ES"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "OpenSearch cluster status is RED - CRITICAL"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    DomainName = var.opensearch_domain_name
    ClientId   = data.aws_caller_identity.current.account_id
  }

  tags = {
    Name = "${local.name_prefix}-opensearch-red-alarm"
  }
}

# OpenSearch Free Storage
resource "aws_cloudwatch_metric_alarm" "opensearch_storage" {
  count               = var.enable_cloudwatch_alarms && var.opensearch_domain_name != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-opensearch-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/ES"
  period              = 300
  statistic           = "Minimum"
  threshold           = 10240 # 10 GB in MB
  alarm_description   = "OpenSearch free storage below 10GB"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    DomainName = var.opensearch_domain_name
    ClientId   = data.aws_caller_identity.current.account_id
  }

  tags = {
    Name = "${local.name_prefix}-opensearch-storage-alarm"
  }
}

# OpenSearch JVM Memory Pressure
resource "aws_cloudwatch_metric_alarm" "opensearch_jvm" {
  count               = var.enable_cloudwatch_alarms && var.opensearch_domain_name != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-opensearch-jvm-pressure"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "JVMMemoryPressure"
  namespace           = "AWS/ES"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "OpenSearch JVM memory pressure above 85%"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    DomainName = var.opensearch_domain_name
    ClientId   = data.aws_caller_identity.current.account_id
  }

  tags = {
    Name = "${local.name_prefix}-opensearch-jvm-alarm"
  }
}

#------------------------------------------------------------------------------
# EFS Alarms
#------------------------------------------------------------------------------

# EFS Burst Credit Balance
resource "aws_cloudwatch_metric_alarm" "efs_burst_credits" {
  count               = var.enable_cloudwatch_alarms && var.efs_file_system_id != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-efs-low-burst-credits"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 1000000000000 # 1 TB of credits
  alarm_description   = "EFS burst credits running low"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]

  dimensions = {
    FileSystemId = var.efs_file_system_id
  }

  tags = {
    Name = "${local.name_prefix}-efs-burst-alarm"
  }
}

#------------------------------------------------------------------------------
# CloudWatch Dashboard
#------------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "main" {
  count          = var.enable_cloudwatch_dashboards ? 1 : 0
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# Ajyal LMS - ${upper(var.environment)} Dashboard"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "EC2 CPU Utilization"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/EC2", "CPUUtilization", { stat = "Average", period = 300 }]
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "RDS CPU Utilization"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/RDS", "CPUUtilization", { stat = "Average", period = 300 }]
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "ALB Request Count"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", { stat = "Sum", period = 300 }]
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "ALB HTTP Errors"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", { stat = "Sum", period = 300, color = "#d62728" }],
            ["AWS/ApplicationELB", "HTTPCode_ELB_4XX_Count", { stat = "Sum", period = 300, color = "#ff7f0e" }]
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "Redis CPU & Memory"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/ElastiCache", "CPUUtilization", { stat = "Average", period = 300 }],
            ["AWS/ElastiCache", "DatabaseMemoryUsagePercentage", { stat = "Average", period = 300 }]
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "OpenSearch Cluster Status"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/ES", "ClusterStatus.green", { stat = "Minimum", period = 300 }],
            ["AWS/ES", "ClusterStatus.yellow", { stat = "Maximum", period = 300 }],
            ["AWS/ES", "ClusterStatus.red", { stat = "Maximum", period = 300 }]
          ]
          view    = "timeSeries"
          stacked = false
        }
      }
    ]
  })
}

#------------------------------------------------------------------------------
# CloudTrail
#------------------------------------------------------------------------------

resource "aws_cloudtrail" "main" {
  count                         = var.enable_cloudtrail ? 1 : 0
  name                          = "${local.name_prefix}-cloudtrail"
  s3_bucket_name                = var.cloudtrail_bucket_name
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_logging                = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3"]
    }
  }

  tags = {
    Name = "${local.name_prefix}-cloudtrail"
  }
}

#------------------------------------------------------------------------------
# SIEM Integration (Optional)
#------------------------------------------------------------------------------

resource "aws_sqs_queue" "siem" {
  count = var.enable_siem_integration ? 1 : 0
  name  = var.siem_sqs_queue_name != "" ? var.siem_sqs_queue_name : "${local.name_prefix}-siem-queue"

  message_retention_seconds  = 86400
  visibility_timeout_seconds = 300

  tags = {
    Name = "${local.name_prefix}-siem-queue"
  }
}

resource "aws_sqs_queue_policy" "siem" {
  count     = var.enable_siem_integration ? 1 : 0
  queue_url = aws_sqs_queue.siem[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3Events"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.siem[0].arn
      }
    ]
  })
}

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
