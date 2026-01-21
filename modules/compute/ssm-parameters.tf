#------------------------------------------------------------------------------
# SSM Parameter Store - CloudWatch Agent Configurations
# These parameters can be updated without redeploying instances
# Instances fetch config using: amazon-cloudwatch-agent-ctl -a fetch-config -c ssm:<parameter-name>
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# API Server CloudWatch Config
#------------------------------------------------------------------------------
resource "aws_ssm_parameter" "cloudwatch_api_server" {
  count = var.enable_api_servers ? 1 : 0
  name  = "/${local.name_prefix}/cloudwatch/windows-api-server"
  type  = "String"
  value = jsonencode({
    agent = {
      metrics_collection_interval = 60
      run_as_user                 = "cwagent"
    }
    metrics = {
      namespace = "${var.environment}-ajyal"
      append_dimensions = {
        InstanceId           = "$${aws:InstanceId}"
        AutoScalingGroupName = "$${aws:AutoScalingGroupName}"
      }
      metrics_collected = {
        Memory = {
          measurement                 = ["% Committed Bytes In Use", "Available MBytes"]
          metrics_collection_interval = 60
        }
        LogicalDisk = {
          measurement                 = ["% Free Space", "Free Megabytes"]
          metrics_collection_interval = 60
          resources                   = ["*"]
        }
        Processor = {
          measurement                 = ["% Processor Time", "% Idle Time"]
          metrics_collection_interval = 60
          resources                   = ["_Total"]
        }
      }
    }
    logs = {
      logs_collected = {
        windows_events = {
          collect_list = [
            {
              event_name      = "Application"
              event_levels    = ["ERROR", "WARNING"]
              log_group_name  = "/${local.name_prefix}/windows/api-server/application"
              log_stream_name = "{instance_id}"
            },
            {
              event_name      = "System"
              event_levels    = ["ERROR", "WARNING"]
              log_group_name  = "/${local.name_prefix}/windows/api-server/system"
              log_stream_name = "{instance_id}"
            }
          ]
        }
        files = {
          collect_list = [
            {
              file_path       = "C:\\inetpub\\logs\\LogFiles\\W3SVC*\\*.log"
              log_group_name  = "/${local.name_prefix}/windows/api-server/iis"
              log_stream_name = "{instance_id}"
              timezone        = "UTC"
            },
            {
              file_path       = "C:\\AjyalAPI\\logs\\*.log"
              log_group_name  = "/${local.name_prefix}/windows/api-server/api-logs"
              log_stream_name = "{instance_id}"
              timezone        = "UTC"
            },
            {
              file_path       = "C:\\inetpub\\wwwroot\\AjyalAPI\\**\\logs\\*.log"
              log_group_name  = "/${local.name_prefix}/windows/api-server/app-logs"
              log_stream_name = "{instance_id}"
              timezone        = "UTC"
            }
          ]
        }
      }
    }
  })

  tags = {
    Name        = "${local.name_prefix}-cloudwatch-api-server"
    Environment = var.environment
    Project     = "Ajyal-LMS"
    ManagedBy   = "Terraform"
    Team        = "Slashtec-DevOps"
    Module      = "compute"
  }
}

#------------------------------------------------------------------------------
# Integration Server CloudWatch Config
#------------------------------------------------------------------------------
resource "aws_ssm_parameter" "cloudwatch_integration_server" {
  count = var.enable_integration_servers ? 1 : 0
  name  = "/${local.name_prefix}/cloudwatch/windows-integration-server"
  type  = "String"
  value = jsonencode({
    agent = {
      metrics_collection_interval = 60
      run_as_user                 = "cwagent"
    }
    metrics = {
      namespace = "${var.environment}-ajyal"
      append_dimensions = {
        InstanceId           = "$${aws:InstanceId}"
        AutoScalingGroupName = "$${aws:AutoScalingGroupName}"
      }
      metrics_collected = {
        Memory = {
          measurement                 = ["% Committed Bytes In Use", "Available MBytes"]
          metrics_collection_interval = 60
        }
        LogicalDisk = {
          measurement                 = ["% Free Space", "Free Megabytes"]
          metrics_collection_interval = 60
          resources                   = ["*"]
        }
        Processor = {
          measurement                 = ["% Processor Time", "% Idle Time"]
          metrics_collection_interval = 60
          resources                   = ["_Total"]
        }
      }
    }
    logs = {
      logs_collected = {
        windows_events = {
          collect_list = [
            {
              event_name      = "Application"
              event_levels    = ["ERROR", "WARNING"]
              log_group_name  = "/${local.name_prefix}/windows/integration-server/application"
              log_stream_name = "{instance_id}"
            },
            {
              event_name      = "System"
              event_levels    = ["ERROR", "WARNING"]
              log_group_name  = "/${local.name_prefix}/windows/integration-server/system"
              log_stream_name = "{instance_id}"
            }
          ]
        }
        files = {
          collect_list = [
            {
              file_path       = "C:\\inetpub\\logs\\LogFiles\\W3SVC*\\*.log"
              log_group_name  = "/${local.name_prefix}/windows/integration-server/iis"
              log_stream_name = "{instance_id}"
              timezone        = "UTC"
            },
            {
              file_path       = "C:\\AjyalIntegration\\logs\\*.log"
              log_group_name  = "/${local.name_prefix}/windows/integration-server/integration-logs"
              log_stream_name = "{instance_id}"
              timezone        = "UTC"
            },
            {
              file_path       = "C:\\inetpub\\wwwroot\\AjyalIntegration\\**\\logs\\*.log"
              log_group_name  = "/${local.name_prefix}/windows/integration-server/app-logs"
              log_stream_name = "{instance_id}"
              timezone        = "UTC"
            }
          ]
        }
      }
    }
  })

  tags = {
    Name        = "${local.name_prefix}-cloudwatch-integration-server"
    Environment = var.environment
    Project     = "Ajyal-LMS"
    ManagedBy   = "Terraform"
    Team        = "Slashtec-DevOps"
    Module      = "compute"
  }
}

#------------------------------------------------------------------------------
# App Server CloudWatch Config
#------------------------------------------------------------------------------
resource "aws_ssm_parameter" "cloudwatch_app_server" {
  count = var.enable_app_servers ? 1 : 0
  name  = "/${local.name_prefix}/cloudwatch/windows-app-server"
  type  = "String"
  value = jsonencode({
    agent = {
      metrics_collection_interval = 60
      run_as_user                 = "cwagent"
    }
    metrics = {
      namespace = "${var.environment}-ajyal"
      append_dimensions = {
        InstanceId           = "$${aws:InstanceId}"
        AutoScalingGroupName = "$${aws:AutoScalingGroupName}"
      }
      metrics_collected = {
        Memory = {
          measurement                 = ["% Committed Bytes In Use", "Available MBytes"]
          metrics_collection_interval = 60
        }
        "Paging File" = {
          measurement                 = ["% Usage"]
          metrics_collection_interval = 60
          resources                   = ["*"]
        }
        LogicalDisk = {
          measurement                 = ["% Free Space", "Free Megabytes"]
          metrics_collection_interval = 60
          resources                   = ["*"]
        }
        Processor = {
          measurement                 = ["% Processor Time", "% Idle Time"]
          metrics_collection_interval = 60
          resources                   = ["_Total"]
        }
      }
    }
    logs = {
      logs_collected = {
        windows_events = {
          collect_list = [
            {
              event_name      = "Application"
              event_levels    = ["ERROR", "WARNING"]
              log_group_name  = "/${local.name_prefix}/windows/app-server/application"
              log_stream_name = "{instance_id}"
            },
            {
              event_name      = "System"
              event_levels    = ["ERROR", "WARNING"]
              log_group_name  = "/${local.name_prefix}/windows/app-server/system"
              log_stream_name = "{instance_id}"
            }
          ]
        }
        files = {
          collect_list = [
            {
              file_path       = "C:\\inetpub\\logs\\LogFiles\\W3SVC*\\*.log"
              log_group_name  = "/${local.name_prefix}/windows/app-server/iis"
              log_stream_name = "{instance_id}"
              timezone        = "UTC"
            },
            {
              file_path       = "C:\\AjyalApp\\logs\\*.log"
              log_group_name  = "/${local.name_prefix}/windows/app-server/application-logs"
              log_stream_name = "{instance_id}"
              timezone        = "UTC"
            }
          ]
        }
      }
    }
  })

  tags = {
    Name        = "${local.name_prefix}-cloudwatch-app-server"
    Environment = var.environment
    Project     = "Ajyal-LMS"
    ManagedBy   = "Terraform"
    Team        = "Slashtec-DevOps"
    Module      = "compute"
  }
}

#------------------------------------------------------------------------------
# Logging Server CloudWatch Config
#------------------------------------------------------------------------------
resource "aws_ssm_parameter" "cloudwatch_logging_server" {
  count = var.enable_logging_servers ? 1 : 0
  name  = "/${local.name_prefix}/cloudwatch/windows-logging-server"
  type  = "String"
  value = jsonencode({
    agent = {
      metrics_collection_interval = 60
      run_as_user                 = "cwagent"
    }
    metrics = {
      namespace = "${var.environment}-ajyal"
      append_dimensions = {
        InstanceId           = "$${aws:InstanceId}"
        AutoScalingGroupName = "$${aws:AutoScalingGroupName}"
      }
      metrics_collected = {
        Memory = {
          measurement                 = ["% Committed Bytes In Use", "Available MBytes"]
          metrics_collection_interval = 60
        }
        LogicalDisk = {
          measurement                 = ["% Free Space", "Free Megabytes"]
          metrics_collection_interval = 60
          resources                   = ["*"]
        }
        Processor = {
          measurement                 = ["% Processor Time"]
          metrics_collection_interval = 60
          resources                   = ["_Total"]
        }
      }
    }
    logs = {
      logs_collected = {
        windows_events = {
          collect_list = [
            {
              event_name      = "Application"
              event_levels    = ["ERROR", "WARNING", "INFORMATION"]
              log_group_name  = "/${local.name_prefix}/windows/logging-server/application"
              log_stream_name = "{instance_id}"
            },
            {
              event_name      = "System"
              event_levels    = ["ERROR", "WARNING"]
              log_group_name  = "/${local.name_prefix}/windows/logging-server/system"
              log_stream_name = "{instance_id}"
            },
            {
              event_name      = "Security"
              event_levels    = ["ERROR", "WARNING", "INFORMATION"]
              log_group_name  = "/${local.name_prefix}/windows/logging-server/security"
              log_stream_name = "{instance_id}"
            }
          ]
        }
        files = {
          collect_list = [
            {
              file_path       = "C:\\Logs\\**\\*.log"
              log_group_name  = "/${local.name_prefix}/windows/logging-server/centralized-logs"
              log_stream_name = "{instance_id}"
              timezone        = "UTC"
            }
          ]
        }
      }
    }
  })

  tags = {
    Name        = "${local.name_prefix}-cloudwatch-logging-server"
    Environment = var.environment
    Project     = "Ajyal-LMS"
    ManagedBy   = "Terraform"
    Team        = "Slashtec-DevOps"
    Module      = "compute"
  }
}

#------------------------------------------------------------------------------
# Default Windows CloudWatch Config (fallback)
#------------------------------------------------------------------------------
resource "aws_ssm_parameter" "cloudwatch_windows_default" {
  name = "/${local.name_prefix}/cloudwatch/windows-default"
  type = "String"
  value = jsonencode({
    agent = {
      metrics_collection_interval = 60
      run_as_user                 = "cwagent"
    }
    metrics = {
      namespace = "${var.environment}-ajyal"
      append_dimensions = {
        InstanceId = "$${aws:InstanceId}"
      }
      metrics_collected = {
        Memory = {
          measurement                 = ["% Committed Bytes In Use", "Available MBytes"]
          metrics_collection_interval = 60
        }
        LogicalDisk = {
          measurement                 = ["% Free Space"]
          metrics_collection_interval = 60
          resources                   = ["*"]
        }
        Processor = {
          measurement                 = ["% Processor Time"]
          metrics_collection_interval = 60
          resources                   = ["_Total"]
        }
      }
    }
    logs = {
      logs_collected = {
        windows_events = {
          collect_list = [
            {
              event_name      = "Application"
              event_levels    = ["ERROR", "WARNING"]
              log_group_name  = "/${local.name_prefix}/windows/default/application"
              log_stream_name = "{instance_id}"
            },
            {
              event_name      = "System"
              event_levels    = ["ERROR", "WARNING"]
              log_group_name  = "/${local.name_prefix}/windows/default/system"
              log_stream_name = "{instance_id}"
            }
          ]
        }
      }
    }
  })

  tags = {
    Name        = "${local.name_prefix}-cloudwatch-windows-default"
    Environment = var.environment
    Project     = "Ajyal-LMS"
    ManagedBy   = "Terraform"
    Team        = "Slashtec-DevOps"
    Module      = "compute"
  }
}

#------------------------------------------------------------------------------
# Application Secrets Parameters (DB connections, API keys)
# NOTE: SecureString parameters should be created manually or via CI/CD
# with actual secret values. These are placeholders for documentation.
#------------------------------------------------------------------------------
# Secrets are stored at:
#   /${local.name_prefix}/secrets/api-server/appsettings         (SecureString)
#   /${local.name_prefix}/secrets/integration-server/appsettings (SecureString)
#
# Expected format for secrets:
# {
#   "ConnectionStrings": {
#     "DefaultConnection": "Server=xxx;Database=xxx;User Id=xxx;Password=xxx;"
#   },
#   "ITGSettings": {
#     "ClientID": "xxx",
#     "ClientSecret": "xxx"
#   }
# }
#
# Create via AWS CLI:
# aws ssm put-parameter --name "/preprod-ajyal/secrets/api-server/appsettings" \
#   --type "SecureString" --value '{"ConnectionStrings":{"DefaultConnection":"..."}}' \
#   --region eu-west-1
#------------------------------------------------------------------------------
