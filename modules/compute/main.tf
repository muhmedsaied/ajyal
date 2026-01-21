###############################################################################
# Compute Module
# EC2 Instances, Auto Scaling Groups, Application Load Balancers
# Windows and Linux servers with CodeDeploy agent pre-installed
###############################################################################

locals {
  name_prefix = "${var.environment}-ajyal"

  # Use custom AMI if provided, otherwise use the latest Windows Server AMI
  windows_ami_id = var.use_custom_windows_ami && var.custom_windows_ami_id != "" ? var.custom_windows_ami_id : data.aws_ami.windows.id

  # S3 bucket for prerequisites
  prerequisites_bucket = var.prerequisites_s3_bucket != "" ? var.prerequisites_s3_bucket : "${var.environment}-ajyal-deployments-${data.aws_caller_identity.current.account_id}"
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

#------------------------------------------------------------------------------
# Data Sources - AMIs
#------------------------------------------------------------------------------

# Windows Server 2025 AMI
data "aws_ami" "windows" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2025-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Amazon Linux 2023 AMI
data "aws_ami" "linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

#------------------------------------------------------------------------------
# Public ALB (Botpress only - App ALB removed)
#------------------------------------------------------------------------------

# Botpress ALB
resource "aws_lb" "botpress" {
  count              = var.enable_botpress_servers ? 1 : 0
  name               = "${local.name_prefix}-botpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = length(var.public_subnet_ids) > 0 ? var.public_subnet_ids : [var.public_subnet_id]

  enable_deletion_protection = false

  tags = {
    Name = "${local.name_prefix}-botpress-alb"
  }
}

resource "aws_lb_target_group" "botpress" {
  count    = var.enable_botpress_servers ? 1 : 0
  name     = "${local.name_prefix}-botpress-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${local.name_prefix}-botpress-tg"
  }
}

resource "aws_lb_listener" "botpress_http" {
  count             = var.enable_botpress_servers ? 1 : 0
  load_balancer_arn = aws_lb.botpress[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.botpress[0].arn
  }
}

#------------------------------------------------------------------------------
# Internal ALB (API)
#------------------------------------------------------------------------------

resource "aws_lb" "api" {
  count              = var.enable_api_servers ? 1 : 0
  name               = "${local.name_prefix}-api-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = length(var.private_app_subnet_ids) > 0 ? var.private_app_subnet_ids : [var.private_app_subnet_id]

  enable_deletion_protection = false

  tags = {
    Name = "${local.name_prefix}-api-alb"
  }
}

resource "aws_lb_target_group" "api" {
  count    = var.enable_api_servers ? 1 : 0
  name     = "${local.name_prefix}-api-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200-499"
    path                = "/api/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${local.name_prefix}-api-tg"
  }
}

resource "aws_lb_listener" "api_http" {
  count             = var.enable_api_servers ? 1 : 0
  load_balancer_arn = aws_lb.api[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api[0].arn
  }
}

#------------------------------------------------------------------------------
# Integration NLB with Static IPs (for client whitelisting)
#------------------------------------------------------------------------------

# Elastic IPs for Integration NLB (static IPs for whitelisting)
# PROTECTED: These IPs are shared with clients for whitelisting - do not delete!
resource "aws_eip" "integration_nlb" {
  count  = var.enable_integration_nlb ? length(var.public_subnet_ids) : 0
  domain = "vpc"

  tags = {
    Name        = "${local.name_prefix}-integration-nlb-eip-${count.index + 1}"
    Environment = var.environment
    Project     = "Ajyal-LMS"
    ManagedBy   = "Terraform"
    Team        = "Slashtec-DevOps"
    Module      = "compute"
    Protected   = "true"
  }

  # Prevent accidental deletion - these IPs are shared with clients
  lifecycle {
    prevent_destroy = true
  }
}

# Security Group for Integration NLB
resource "aws_security_group" "integration_nlb" {
  count       = var.enable_integration_nlb ? 1 : 0
  name        = "${local.name_prefix}-integration-nlb-sg"
  description = "Security group for Integration NLB - allows HTTP/HTTPS from internet"
  vpc_id      = var.vpc_id

  # HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from internet"
  }

  # HTTPS from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet"
  }

  # Egress to targets
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name        = "${local.name_prefix}-integration-nlb-sg"
    Environment = var.environment
    Project     = "Ajyal-LMS"
    ManagedBy   = "Terraform"
    Team        = "Slashtec-DevOps"
    Module      = "compute"
    Protected   = "true"
  }
}

# Network Load Balancer for Integration Server
# PROTECTED: This NLB provides static IPs for client whitelisting - do not delete!
resource "aws_lb" "integration" {
  count              = var.enable_integration_nlb ? 1 : 0
  name               = "${local.name_prefix}-integration-nlb"
  internal           = false
  load_balancer_type = "network"

  # Security group for NLB (supported since 2023)
  security_groups = [aws_security_group.integration_nlb[0].id]

  # AWS-level deletion protection
  enable_deletion_protection = true

  dynamic "subnet_mapping" {
    for_each = { for idx, subnet_id in var.public_subnet_ids : idx => subnet_id }
    content {
      subnet_id     = subnet_mapping.value
      allocation_id = aws_eip.integration_nlb[subnet_mapping.key].id
    }
  }

  tags = {
    Name        = "${local.name_prefix}-integration-nlb"
    Environment = var.environment
    Project     = "Ajyal-LMS"
    ManagedBy   = "Terraform"
    Team        = "Slashtec-DevOps"
    Module      = "compute"
    Protected   = "true"
  }

  # Terraform-level deletion protection
  lifecycle {
    prevent_destroy = true
  }
}

# Integration Target Group - HTTP (port 80)
resource "aws_lb_target_group" "integration_http" {
  count    = var.enable_integration_nlb ? 1 : 0
  name     = "${local.name_prefix}-int-http-tg"  # Shortened to meet 32 char limit
  port     = 80
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    port                = "traffic-port"
    protocol            = "TCP"
  }

  tags = {
    Name = "${local.name_prefix}-int-http-tg"
  }
}

# NLB Listener - HTTP (port 80)
resource "aws_lb_listener" "integration_http" {
  count             = var.enable_integration_nlb ? 1 : 0
  load_balancer_arn = aws_lb.integration[0].arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.integration_http[0].arn
  }
}

#------------------------------------------------------------------------------
# Windows Launch Templates
#------------------------------------------------------------------------------

# App Servers Launch Template
resource "aws_launch_template" "app_server" {
  count = var.enable_app_servers ? 1 : 0
  name  = "${local.name_prefix}-app-server-lt"

  image_id      = local.windows_ami_id
  instance_type = var.app_server_instance_type
  key_name      = var.windows_key_name != "" ? var.windows_key_name : null

  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = [var.windows_security_group_id]

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = 150
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(<<-EOF
    <powershell>
    # Install CodeDeploy Agent
    Set-ExecutionPolicy RemoteSigned -Force
    Import-Module AWSPowerShell
    $region = $null
    try {
      $token = Invoke-RestMethod -Method Put -Uri http://169.254.169.254/latest/api/token -Headers @{ "X-aws-ec2-metadata-token-ttl-seconds" = "21600" } -TimeoutSec 5 -ErrorAction Stop
      $region = Invoke-RestMethod -Uri http://169.254.169.254/latest/meta-data/placement/region -Headers @{ "X-aws-ec2-metadata-token" = $token } -TimeoutSec 5 -ErrorAction Stop
    } catch {
      Write-Host "Failed to fetch region from IMDSv2; continuing"
    }
    if (-not $region) { $region = $env:AWS_REGION }
    if (-not $region) { $region = $env:AWS_DEFAULT_REGION }
    $adminPasswordSecretId = "${var.windows_admin_password_secret_id}"
    if ($adminPasswordSecretId -ne "") {
      try {
        Write-Host "Setting local admin credentials from Secrets Manager"
        $secretString = $null
        if (Get-Command aws -ErrorAction SilentlyContinue) {
          $secretString = (aws secretsmanager get-secret-value --secret-id $adminPasswordSecretId --query 'SecretString' --output text --region $region)
        } else {
          Import-Module AWSPowerShell -ErrorAction SilentlyContinue
          if (Get-Command Get-SECSecretValue -ErrorAction SilentlyContinue) {
            $secretString = (Get-SECSecretValue -SecretId $adminPasswordSecretId -ErrorAction Stop).SecretString
          }
        }
        $adminUser = "Administrator"
        $adminPassword = $null
        if ($secretString -and $secretString -ne "None") {
          $adminPassword = $secretString
          try {
            $secretObj = $secretString | ConvertFrom-Json -ErrorAction Stop
            if ($secretObj.username) { $adminUser = $secretObj.username }
            if ($secretObj.password) { $adminPassword = $secretObj.password }
          } catch {
          }
        }
        if ($adminPassword -and $adminPassword -ne "None") {
          net user $adminUser /active:yes | Out-Null
          net user $adminUser $adminPassword | Out-Null
          Write-Host "Local admin credentials updated"
        } else {
          Write-Host "Admin password secret not found or empty"
        }
      } catch {
        Write-Host "Failed to set admin credentials from Secrets Manager: $($_.Exception.Message)"
      }
    }
    %{if !var.use_custom_windows_ami}
    $source = "https://aws-codedeploy-$region.s3.$region.amazonaws.com/latest/codedeploy-agent.msi"
    $dest = "C:\temp\codedeploy-agent.msi"
    New-Item -Path "C:\temp" -ItemType Directory -Force
    Invoke-WebRequest -Uri $source -OutFile $dest
    Start-Process msiexec.exe -ArgumentList "/i $dest /quiet" -Wait

    # Install CloudWatch Agent
    $cwSource = "https://s3.$region.amazonaws.com/amazoncloudwatch-agent-$region/windows/amd64/latest/amazon-cloudwatch-agent.msi"
    $cwDest = "C:\temp\amazon-cloudwatch-agent.msi"
    Invoke-WebRequest -Uri $cwSource -OutFile $cwDest
    Start-Process msiexec.exe -ArgumentList "/i $cwDest /quiet" -Wait
    %{endif}

    # Configure CloudWatch Agent for memory metrics and IIS logs
    $cwConfig = @'
    {
      "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
      },
      "metrics": {
        "namespace": "${var.environment}-ajyal",
        "append_dimensions": {
          "InstanceId": "$${aws:InstanceId}",
          "AutoScalingGroupName": "$${aws:AutoScalingGroupName}"
        },
        "metrics_collected": {
          "Memory": {
            "measurement": ["% Committed Bytes In Use", "Available MBytes"],
            "metrics_collection_interval": 60
          },
          "Paging File": {
            "measurement": ["% Usage"],
            "metrics_collection_interval": 60,
            "resources": ["*"]
          },
          "LogicalDisk": {
            "measurement": ["% Free Space", "Free Megabytes"],
            "metrics_collection_interval": 60,
            "resources": ["*"]
          },
          "Processor": {
            "measurement": ["% Processor Time", "% Idle Time"],
            "metrics_collection_interval": 60,
            "resources": ["_Total"]
          }
        }
      },
      "logs": {
        "logs_collected": {
          "windows_events": {
            "collect_list": [
              {
                "event_name": "Application",
                "event_levels": ["ERROR", "WARNING"],
                "log_group_name": "/${var.environment}-ajyal/windows/app-server/application",
                "log_stream_name": "{instance_id}"
              },
              {
                "event_name": "System",
                "event_levels": ["ERROR", "WARNING"],
                "log_group_name": "/${var.environment}-ajyal/windows/app-server/system",
                "log_stream_name": "{instance_id}"
              }
            ]
          },
          "files": {
            "collect_list": [
              {
                "file_path": "C:\\inetpub\\logs\\LogFiles\\W3SVC1\\*.log",
                "log_group_name": "/${var.environment}-ajyal/windows/app-server/iis",
                "log_stream_name": "{instance_id}",
                "timezone": "UTC"
              },
              {
                "file_path": "C:\\AjyalApp\\logs\\*.log",
                "log_group_name": "/${var.environment}-ajyal/windows/app-server/application-logs",
                "log_stream_name": "{instance_id}",
                "timezone": "UTC"
              }
            ]
          }
        }
      }
    }
'@
    $cwConfig | Out-File -FilePath "C:\ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json" -Encoding UTF8

    # Start CloudWatch Agent
    if (Test-Path "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1") {
      & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a fetch-config -m ec2 -c file:"C:\ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json" -s
    } else {
      Write-Host "CloudWatch Agent not found; skipping configuration"
    }

    Write-Host "CodeDeploy and CloudWatch agents installed and configured successfully"
    </powershell>
    EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name            = "${local.name_prefix}-app-server"
      DeploymentGroup = "windows-app"
      PatchGroup      = "${local.name_prefix}-windows"
      Platform        = "Windows"
    }
  }

  tags = {
    Name = "${local.name_prefix}-app-server-lt"
  }
}

# API Servers Launch Template
resource "aws_launch_template" "api_server" {
  count = var.enable_api_servers ? 1 : 0
  name  = "${local.name_prefix}-api-server-lt"

  image_id      = local.windows_ami_id
  instance_type = var.api_server_instance_type
  key_name      = var.windows_key_name != "" ? var.windows_key_name : null

  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = [var.windows_security_group_id]

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = 150  # Match Golden AMI snapshot size
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(<<-EOF
    <powershell>
    $ErrorActionPreference = "Continue"
    Set-ExecutionPolicy RemoteSigned -Force

    # Get region
    $region = $null
    try {
      $token = Invoke-RestMethod -Method Put -Uri http://169.254.169.254/latest/api/token -Headers @{ "X-aws-ec2-metadata-token-ttl-seconds" = "21600" } -TimeoutSec 5 -ErrorAction Stop
      $region = Invoke-RestMethod -Uri http://169.254.169.254/latest/meta-data/placement/region -Headers @{ "X-aws-ec2-metadata-token" = $token } -TimeoutSec 5 -ErrorAction Stop
    } catch {
      Write-Host "Failed to fetch region from IMDSv2; continuing"
    }
    if (-not $region) { $region = $env:AWS_REGION }
    if (-not $region) { $region = $env:AWS_DEFAULT_REGION }
    $adminPasswordSecretId = "${var.windows_admin_password_secret_id}"
    if ($adminPasswordSecretId -ne "") {
      try {
        Write-Host "Setting local admin credentials from Secrets Manager"
        $secretString = $null
        if (Get-Command aws -ErrorAction SilentlyContinue) {
          $secretString = (aws secretsmanager get-secret-value --secret-id $adminPasswordSecretId --query 'SecretString' --output text --region $region)
        } else {
          Import-Module AWSPowerShell -ErrorAction SilentlyContinue
          if (Get-Command Get-SECSecretValue -ErrorAction SilentlyContinue) {
            $secretString = (Get-SECSecretValue -SecretId $adminPasswordSecretId -ErrorAction Stop).SecretString
          }
        }
        $adminUser = "Administrator"
        $adminPassword = $null
        if ($secretString -and $secretString -ne "None") {
          $adminPassword = $secretString
          try {
            $secretObj = $secretString | ConvertFrom-Json -ErrorAction Stop
            if ($secretObj.username) { $adminUser = $secretObj.username }
            if ($secretObj.password) { $adminPassword = $secretObj.password }
          } catch {
          }
        }
        if ($adminPassword -and $adminPassword -ne "None") {
          net user $adminUser /active:yes | Out-Null
          net user $adminUser $adminPassword | Out-Null
          Write-Host "Local admin credentials updated"
        } else {
          Write-Host "Admin password secret not found or empty"
        }
      } catch {
        Write-Host "Failed to set admin credentials from Secrets Manager: $($_.Exception.Message)"
      }
    }

    # Create directories
    New-Item -Path "C:\temp" -ItemType Directory -Force | Out-Null
    New-Item -Path "C:\AjyalAPI\logs" -ItemType Directory -Force | Out-Null
    New-Item -Path "C:\inetpub\wwwroot\AjyalAPI" -ItemType Directory -Force | Out-Null

    %{if !var.use_custom_windows_ami}
    # Install prerequisites if not using custom AMI
    Write-Host "Installing prerequisites..."

    # Install CodeDeploy Agent
    $source = "https://aws-codedeploy-$region.s3.$region.amazonaws.com/latest/codedeploy-agent.msi"
    Invoke-WebRequest -Uri $source -OutFile "C:\temp\codedeploy-agent.msi"
    Start-Process msiexec.exe -ArgumentList "/i C:\temp\codedeploy-agent.msi /quiet" -Wait

    # Install CloudWatch Agent
    $cwSource = "https://s3.$region.amazonaws.com/amazoncloudwatch-agent-$region/windows/amd64/latest/amazon-cloudwatch-agent.msi"
    Invoke-WebRequest -Uri $cwSource -OutFile "C:\temp\amazon-cloudwatch-agent.msi"
    Start-Process msiexec.exe -ArgumentList "/i C:\temp\amazon-cloudwatch-agent.msi /quiet" -Wait

    %{if var.install_prerequisites_on_launch}
    # Run full prerequisites installation from S3
    try {
        aws s3 cp "s3://${local.prerequisites_bucket}/scripts/windows/install-prerequisites.ps1" "C:\temp\install-prerequisites.ps1" --region $region
        & "C:\temp\install-prerequisites.ps1" -S3Bucket "${local.prerequisites_bucket}"
    } catch {
        Write-Host "Prerequisites script not found, continuing with basic setup"
    }
    %{endif}
    %{endif}

    # Configure CloudWatch Agent
    %{if var.cloudwatch_config_source == "ssm"}
    # Fetch CloudWatch config from SSM Parameter Store
    Write-Host "Configuring CloudWatch Agent from SSM..."
    Start-Sleep -Seconds 10  # Wait for CloudWatch agent installation
    & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a fetch-config -m ec2 -c "ssm:/${local.name_prefix}/cloudwatch/windows-api-server" -s
    %{else}
    # Use inline CloudWatch config
    Write-Host "Configuring CloudWatch Agent with inline config..."
    $cwConfig = @'
    {
      "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
      },
      "metrics": {
        "namespace": "${var.environment}-ajyal",
        "append_dimensions": {
          "InstanceId": "$${aws:InstanceId}",
          "AutoScalingGroupName": "$${aws:AutoScalingGroupName}"
        },
        "metrics_collected": {
          "Memory": {
            "measurement": ["% Committed Bytes In Use", "Available MBytes"],
            "metrics_collection_interval": 60
          },
          "LogicalDisk": {
            "measurement": ["% Free Space", "Free Megabytes"],
            "metrics_collection_interval": 60,
            "resources": ["*"]
          },
          "Processor": {
            "measurement": ["% Processor Time"],
            "metrics_collection_interval": 60,
            "resources": ["_Total"]
          }
        }
      },
      "logs": {
        "logs_collected": {
          "windows_events": {
            "collect_list": [
              {
                "event_name": "Application",
                "event_levels": ["ERROR", "WARNING"],
                "log_group_name": "/${var.environment}-ajyal/windows/api-server/application",
                "log_stream_name": "{instance_id}"
              },
              {
                "event_name": "System",
                "event_levels": ["ERROR", "WARNING"],
                "log_group_name": "/${var.environment}-ajyal/windows/api-server/system",
                "log_stream_name": "{instance_id}"
              }
            ]
          },
          "files": {
            "collect_list": [
              {
                "file_path": "C:\\inetpub\\logs\\LogFiles\\W3SVC*\\*.log",
                "log_group_name": "/${var.environment}-ajyal/windows/api-server/iis",
                "log_stream_name": "{instance_id}",
                "timezone": "UTC"
              },
              {
                "file_path": "C:\\AjyalAPI\\logs\\*.log",
                "log_group_name": "/${var.environment}-ajyal/windows/api-server/api-logs",
                "log_stream_name": "{instance_id}",
                "timezone": "UTC"
              }
            ]
          }
        }
      }
    }
'@
    $cwConfig | Out-File -FilePath "C:\ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json" -Encoding UTF8
    & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a fetch-config -m ec2 -c file:"C:\ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json" -s
    %{endif}

    Write-Host "Bootstrap complete for API Server"
    </powershell>
    EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name            = "${local.name_prefix}-api-server"
      DeploymentGroup = "windows-api"
      PatchGroup      = "${local.name_prefix}-windows"
      Platform        = "Windows"
    }
  }

  tags = {
    Name = "${local.name_prefix}-api-server-lt"
  }

  # Ensure SSM parameter is created before launch template
  depends_on = [aws_ssm_parameter.cloudwatch_api_server]
}

# Integration Servers Launch Template
resource "aws_launch_template" "integration_server" {
  count = var.enable_integration_servers ? 1 : 0
  name  = "${local.name_prefix}-integration-server-lt"

  image_id      = local.windows_ami_id
  instance_type = var.integration_server_instance_type
  key_name      = var.windows_key_name != "" ? var.windows_key_name : null

  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = [var.windows_security_group_id]

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = 150  # Match Golden AMI snapshot size
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(<<-EOF
    <powershell>
    $ErrorActionPreference = "Continue"
    Set-ExecutionPolicy RemoteSigned -Force

    # Get region
    $region = $null
    try {
      $token = Invoke-RestMethod -Method Put -Uri http://169.254.169.254/latest/api/token -Headers @{ "X-aws-ec2-metadata-token-ttl-seconds" = "21600" } -TimeoutSec 5 -ErrorAction Stop
      $region = Invoke-RestMethod -Uri http://169.254.169.254/latest/meta-data/placement/region -Headers @{ "X-aws-ec2-metadata-token" = $token } -TimeoutSec 5 -ErrorAction Stop
    } catch {
      Write-Host "Failed to fetch region from IMDSv2; continuing"
    }
    if (-not $region) { $region = $env:AWS_REGION }
    if (-not $region) { $region = $env:AWS_DEFAULT_REGION }
    $adminPasswordSecretId = "${var.windows_admin_password_secret_id}"
    if ($adminPasswordSecretId -ne "") {
      try {
        Write-Host "Setting local admin credentials from Secrets Manager"
        $secretString = $null
        if (Get-Command aws -ErrorAction SilentlyContinue) {
          $secretString = (aws secretsmanager get-secret-value --secret-id $adminPasswordSecretId --query 'SecretString' --output text --region $region)
        } else {
          Import-Module AWSPowerShell -ErrorAction SilentlyContinue
          if (Get-Command Get-SECSecretValue -ErrorAction SilentlyContinue) {
            $secretString = (Get-SECSecretValue -SecretId $adminPasswordSecretId -ErrorAction Stop).SecretString
          }
        }
        $adminUser = "Administrator"
        $adminPassword = $null
        if ($secretString -and $secretString -ne "None") {
          $adminPassword = $secretString
          try {
            $secretObj = $secretString | ConvertFrom-Json -ErrorAction Stop
            if ($secretObj.username) { $adminUser = $secretObj.username }
            if ($secretObj.password) { $adminPassword = $secretObj.password }
          } catch {
          }
        }
        if ($adminPassword -and $adminPassword -ne "None") {
          net user $adminUser /active:yes | Out-Null
          net user $adminUser $adminPassword | Out-Null
          Write-Host "Local admin credentials updated"
        } else {
          Write-Host "Admin password secret not found or empty"
        }
      } catch {
        Write-Host "Failed to set admin credentials from Secrets Manager: $($_.Exception.Message)"
      }
    }

    # Create directories
    New-Item -Path "C:\temp" -ItemType Directory -Force | Out-Null
    New-Item -Path "C:\AjyalIntegration\logs" -ItemType Directory -Force | Out-Null
    New-Item -Path "C:\inetpub\wwwroot\AjyalIntegration" -ItemType Directory -Force | Out-Null

    %{if !var.use_custom_windows_ami}
    # Install prerequisites if not using custom AMI
    Write-Host "Installing prerequisites..."

    # Install CodeDeploy Agent
    $source = "https://aws-codedeploy-$region.s3.$region.amazonaws.com/latest/codedeploy-agent.msi"
    Invoke-WebRequest -Uri $source -OutFile "C:\temp\codedeploy-agent.msi"
    Start-Process msiexec.exe -ArgumentList "/i C:\temp\codedeploy-agent.msi /quiet" -Wait

    # Install CloudWatch Agent
    $cwSource = "https://s3.$region.amazonaws.com/amazoncloudwatch-agent-$region/windows/amd64/latest/amazon-cloudwatch-agent.msi"
    Invoke-WebRequest -Uri $cwSource -OutFile "C:\temp\amazon-cloudwatch-agent.msi"
    Start-Process msiexec.exe -ArgumentList "/i C:\temp\amazon-cloudwatch-agent.msi /quiet" -Wait

    %{if var.install_prerequisites_on_launch}
    # Run full prerequisites installation from S3
    try {
        aws s3 cp "s3://${local.prerequisites_bucket}/scripts/windows/install-prerequisites.ps1" "C:\temp\install-prerequisites.ps1" --region $region
        & "C:\temp\install-prerequisites.ps1" -S3Bucket "${local.prerequisites_bucket}"
    } catch {
        Write-Host "Prerequisites script not found, continuing with basic setup"
    }
    %{endif}
    %{endif}

    # Configure CloudWatch Agent
    %{if var.cloudwatch_config_source == "ssm"}
    # Fetch CloudWatch config from SSM Parameter Store
    Write-Host "Configuring CloudWatch Agent from SSM..."
    Start-Sleep -Seconds 10  # Wait for CloudWatch agent installation
    & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a fetch-config -m ec2 -c "ssm:/${local.name_prefix}/cloudwatch/windows-integration-server" -s
    %{else}
    # Use inline CloudWatch config
    Write-Host "Configuring CloudWatch Agent with inline config..."
    $cwConfig = @'
    {
      "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
      },
      "metrics": {
        "namespace": "${var.environment}-ajyal",
        "append_dimensions": {
          "InstanceId": "$${aws:InstanceId}",
          "AutoScalingGroupName": "$${aws:AutoScalingGroupName}"
        },
        "metrics_collected": {
          "Memory": {
            "measurement": ["% Committed Bytes In Use", "Available MBytes"],
            "metrics_collection_interval": 60
          },
          "LogicalDisk": {
            "measurement": ["% Free Space", "Free Megabytes"],
            "metrics_collection_interval": 60,
            "resources": ["*"]
          },
          "Processor": {
            "measurement": ["% Processor Time"],
            "metrics_collection_interval": 60,
            "resources": ["_Total"]
          }
        }
      },
      "logs": {
        "logs_collected": {
          "windows_events": {
            "collect_list": [
              {
                "event_name": "Application",
                "event_levels": ["ERROR", "WARNING"],
                "log_group_name": "/${var.environment}-ajyal/windows/integration-server/application",
                "log_stream_name": "{instance_id}"
              },
              {
                "event_name": "System",
                "event_levels": ["ERROR", "WARNING"],
                "log_group_name": "/${var.environment}-ajyal/windows/integration-server/system",
                "log_stream_name": "{instance_id}"
              }
            ]
          },
          "files": {
            "collect_list": [
              {
                "file_path": "C:\\inetpub\\logs\\LogFiles\\W3SVC*\\*.log",
                "log_group_name": "/${var.environment}-ajyal/windows/integration-server/iis",
                "log_stream_name": "{instance_id}",
                "timezone": "UTC"
              },
              {
                "file_path": "C:\\AjyalIntegration\\logs\\*.log",
                "log_group_name": "/${var.environment}-ajyal/windows/integration-server/integration-logs",
                "log_stream_name": "{instance_id}",
                "timezone": "UTC"
              }
            ]
          }
        }
      }
    }
'@
    $cwConfig | Out-File -FilePath "C:\ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json" -Encoding UTF8
    & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a fetch-config -m ec2 -c file:"C:\ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json" -s
    %{endif}

    Write-Host "Bootstrap complete for Integration Server"
    </powershell>
    EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name            = "${local.name_prefix}-integration-server"
      DeploymentGroup = "windows-integration"
      PatchGroup      = "${local.name_prefix}-windows"
      Platform        = "Windows"
    }
  }

  tags = {
    Name = "${local.name_prefix}-integration-server-lt"
  }

  # Ensure SSM parameter is created before launch template
  depends_on = [aws_ssm_parameter.cloudwatch_integration_server]
}

# Logging Servers Launch Template
resource "aws_launch_template" "logging_server" {
  count = var.enable_logging_servers ? 1 : 0
  name  = "${local.name_prefix}-logging-server-lt"

  image_id      = local.windows_ami_id
  instance_type = var.logging_server_instance_type
  key_name      = var.windows_key_name != "" ? var.windows_key_name : null

  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = [var.windows_security_group_id]

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = 200 # Larger for logs
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(<<-EOF
    <powershell>
    Set-ExecutionPolicy RemoteSigned -Force
    Import-Module AWSPowerShell
    $region = $null
    try {
      $token = Invoke-RestMethod -Method Put -Uri http://169.254.169.254/latest/api/token -Headers @{ "X-aws-ec2-metadata-token-ttl-seconds" = "21600" } -TimeoutSec 5 -ErrorAction Stop
      $region = Invoke-RestMethod -Uri http://169.254.169.254/latest/meta-data/placement/region -Headers @{ "X-aws-ec2-metadata-token" = $token } -TimeoutSec 5 -ErrorAction Stop
    } catch {
      Write-Host "Failed to fetch region from IMDSv2; continuing"
    }
    if (-not $region) { $region = $env:AWS_REGION }
    if (-not $region) { $region = $env:AWS_DEFAULT_REGION }
    $adminPasswordSecretId = "${var.windows_admin_password_secret_id}"
    if ($adminPasswordSecretId -ne "") {
      try {
        Write-Host "Setting local admin credentials from Secrets Manager"
        $secretString = $null
        if (Get-Command aws -ErrorAction SilentlyContinue) {
          $secretString = (aws secretsmanager get-secret-value --secret-id $adminPasswordSecretId --query 'SecretString' --output text --region $region)
        } else {
          Import-Module AWSPowerShell -ErrorAction SilentlyContinue
          if (Get-Command Get-SECSecretValue -ErrorAction SilentlyContinue) {
            $secretString = (Get-SECSecretValue -SecretId $adminPasswordSecretId -ErrorAction Stop).SecretString
          }
        }
        $adminUser = "Administrator"
        $adminPassword = $null
        if ($secretString -and $secretString -ne "None") {
          $adminPassword = $secretString
          try {
            $secretObj = $secretString | ConvertFrom-Json -ErrorAction Stop
            if ($secretObj.username) { $adminUser = $secretObj.username }
            if ($secretObj.password) { $adminPassword = $secretObj.password }
          } catch {
          }
        }
        if ($adminPassword -and $adminPassword -ne "None") {
          net user $adminUser /active:yes | Out-Null
          net user $adminUser $adminPassword | Out-Null
          Write-Host "Local admin credentials updated"
        } else {
          Write-Host "Admin password secret not found or empty"
        }
      } catch {
        Write-Host "Failed to set admin credentials from Secrets Manager: $($_.Exception.Message)"
      }
    }
    %{if !var.use_custom_windows_ami}
    $source = "https://aws-codedeploy-$region.s3.$region.amazonaws.com/latest/codedeploy-agent.msi"
    $dest = "C:\temp\codedeploy-agent.msi"
    New-Item -Path "C:\temp" -ItemType Directory -Force
    Invoke-WebRequest -Uri $source -OutFile $dest
    Start-Process msiexec.exe -ArgumentList "/i $dest /quiet" -Wait

    $cwSource = "https://s3.$region.amazonaws.com/amazoncloudwatch-agent-$region/windows/amd64/latest/amazon-cloudwatch-agent.msi"
    $cwDest = "C:\temp\amazon-cloudwatch-agent.msi"
    Invoke-WebRequest -Uri $cwSource -OutFile $cwDest
    Start-Process msiexec.exe -ArgumentList "/i $cwDest /quiet" -Wait
    %{endif}

    # Configure CloudWatch Agent for memory metrics and centralized logs
    $cwConfig = @'
    {
      "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
      },
      "metrics": {
        "namespace": "${var.environment}-ajyal",
        "append_dimensions": {
          "InstanceId": "$${aws:InstanceId}",
          "AutoScalingGroupName": "$${aws:AutoScalingGroupName}"
        },
        "metrics_collected": {
          "Memory": {
            "measurement": ["% Committed Bytes In Use", "Available MBytes"],
            "metrics_collection_interval": 60
          },
          "LogicalDisk": {
            "measurement": ["% Free Space", "Free Megabytes"],
            "metrics_collection_interval": 60,
            "resources": ["*"]
          },
          "Processor": {
            "measurement": ["% Processor Time"],
            "metrics_collection_interval": 60,
            "resources": ["_Total"]
          }
        }
      },
      "logs": {
        "logs_collected": {
          "windows_events": {
            "collect_list": [
              {
                "event_name": "Application",
                "event_levels": ["ERROR", "WARNING", "INFORMATION"],
                "log_group_name": "/${var.environment}-ajyal/windows/logging-server/application",
                "log_stream_name": "{instance_id}"
              },
              {
                "event_name": "System",
                "event_levels": ["ERROR", "WARNING"],
                "log_group_name": "/${var.environment}-ajyal/windows/logging-server/system",
                "log_stream_name": "{instance_id}"
              },
              {
                "event_name": "Security",
                "event_levels": ["ERROR", "WARNING", "INFORMATION"],
                "log_group_name": "/${var.environment}-ajyal/windows/logging-server/security",
                "log_stream_name": "{instance_id}"
              }
            ]
          },
          "files": {
            "collect_list": [
              {
                "file_path": "C:\\Logs\\**\\*.log",
                "log_group_name": "/${var.environment}-ajyal/windows/logging-server/centralized-logs",
                "log_stream_name": "{instance_id}",
                "timezone": "UTC"
              }
            ]
          }
        }
      }
    }
'@
    $cwConfig | Out-File -FilePath "C:\ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json" -Encoding UTF8
    if (Test-Path "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1") {
      & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a fetch-config -m ec2 -c file:"C:\ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json" -s
    } else {
      Write-Host "CloudWatch Agent not found; skipping configuration"
    }
    </powershell>
    EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name            = "${local.name_prefix}-logging-server"
      DeploymentGroup = "windows-logging"
      PatchGroup      = "${local.name_prefix}-windows"
      Platform        = "Windows"
    }
  }

  tags = {
    Name = "${local.name_prefix}-logging-server-lt"
  }
}

#------------------------------------------------------------------------------
# Linux Launch Templates
#------------------------------------------------------------------------------

# Botpress Launch Template
resource "aws_launch_template" "botpress" {
  count = var.enable_botpress_servers ? 1 : 0
  name  = "${local.name_prefix}-botpress-lt"

  image_id      = data.aws_ami.linux.id
  instance_type = var.botpress_instance_type

  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = [var.linux_security_group_id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 50
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e

    # Install CodeDeploy Agent
    yum update -y
    yum install -y ruby wget

    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    cd /home/ec2-user
    wget https://aws-codedeploy-$REGION.s3.$REGION.amazonaws.com/latest/install
    chmod +x ./install
    ./install auto
    systemctl enable codedeploy-agent
    systemctl start codedeploy-agent

    # Install CloudWatch Agent
    yum install -y amazon-cloudwatch-agent

    # Install Docker for Botpress
    yum install -y docker
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user

    # Configure CloudWatch Agent for memory metrics and Botpress logs
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONFIG'
    {
      "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
      },
      "metrics": {
        "namespace": "${var.environment}-ajyal",
        "append_dimensions": {
          "InstanceId": "$${aws:InstanceId}",
          "AutoScalingGroupName": "$${aws:AutoScalingGroupName}"
        },
        "metrics_collected": {
          "mem": {
            "measurement": ["mem_used_percent", "mem_available", "mem_total"],
            "metrics_collection_interval": 60
          },
          "disk": {
            "measurement": ["disk_used_percent", "disk_free", "disk_total"],
            "metrics_collection_interval": 60,
            "resources": ["/", "/home"]
          },
          "cpu": {
            "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
            "metrics_collection_interval": 60,
            "totalcpu": true
          }
        }
      },
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/log/messages",
                "log_group_name": "/${var.environment}-ajyal/linux/botpress/system",
                "log_stream_name": "{instance_id}",
                "timezone": "UTC"
              },
              {
                "file_path": "/var/log/docker*.log",
                "log_group_name": "/${var.environment}-ajyal/linux/botpress/docker",
                "log_stream_name": "{instance_id}",
                "timezone": "UTC"
              },
              {
                "file_path": "/home/ec2-user/botpress/logs/*.log",
                "log_group_name": "/${var.environment}-ajyal/linux/botpress/application",
                "log_stream_name": "{instance_id}",
                "timezone": "UTC"
              }
            ]
          }
        }
      }
    }
CWCONFIG

    # Start CloudWatch Agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

    echo "Bootstrap complete"
    EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name            = "${local.name_prefix}-botpress"
      DeploymentGroup = "linux-botpress"
      PatchGroup      = "${local.name_prefix}-linux"
      Platform        = "Linux"
    }
  }

  tags = {
    Name = "${local.name_prefix}-botpress-lt"
  }
}

#------------------------------------------------------------------------------
# RabbitMQ - Single EC2 Instance (No ASG, No CodeDeploy)
# Message broker service - standalone instance for preprod
#------------------------------------------------------------------------------

resource "aws_instance" "rabbitmq" {
  count         = var.enable_rabbitmq_servers ? 1 : 0
  ami           = data.aws_ami.linux.id
  instance_type = var.rabbitmq_instance_type
  subnet_id     = var.private_app_subnet_id

  iam_instance_profile   = var.instance_profile_name
  vpc_security_group_ids = [var.linux_security_group_id]

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    encrypted             = true
    kms_key_id            = var.kms_key_arn
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e

    # Update system
    yum update -y
    yum install -y amazon-cloudwatch-agent

    # Install Erlang and RabbitMQ
    yum install -y erlang rabbitmq-server

    # Enable and start RabbitMQ
    systemctl enable rabbitmq-server
    systemctl start rabbitmq-server

    # Enable management plugin (web UI on port 15672)
    rabbitmq-plugins enable rabbitmq_management

    # Create admin user (change password in production!)
    rabbitmqctl add_user admin admin123
    rabbitmqctl set_user_tags admin administrator
    rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"

    # Configure CloudWatch Agent for memory metrics and RabbitMQ logs
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONFIG'
    {
      "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
      },
      "metrics": {
        "namespace": "${var.environment}-ajyal",
        "append_dimensions": {
          "InstanceId": "$${aws:InstanceId}"
        },
        "metrics_collected": {
          "mem": {
            "measurement": ["mem_used_percent", "mem_available", "mem_total"],
            "metrics_collection_interval": 60
          },
          "disk": {
            "measurement": ["disk_used_percent", "disk_free", "disk_total"],
            "metrics_collection_interval": 60,
            "resources": ["/", "/var"]
          },
          "cpu": {
            "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
            "metrics_collection_interval": 60,
            "totalcpu": true
          }
        }
      },
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/log/messages",
                "log_group_name": "/${var.environment}-ajyal/linux/rabbitmq/system",
                "log_stream_name": "{instance_id}",
                "timezone": "UTC"
              },
              {
                "file_path": "/var/log/rabbitmq/*.log",
                "log_group_name": "/${var.environment}-ajyal/linux/rabbitmq/application",
                "log_stream_name": "{instance_id}",
                "timezone": "UTC"
              }
            ]
          }
        }
      }
    }
CWCONFIG

    # Start CloudWatch Agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

    echo "RabbitMQ installation complete"
    EOF
  )

  tags = {
    Name        = "${local.name_prefix}-rabbitmq"
    PatchGroup  = "${local.name_prefix}-linux"
    Platform    = "Linux"
    Service     = "RabbitMQ"
    Environment = var.environment
    Project     = "Ajyal-LMS"
    ManagedBy   = "Terraform"
    Team        = "Slashtec-DevOps"
    Module      = "compute"
  }
}

# ML Server Launch Template
resource "aws_launch_template" "ml" {
  count = var.enable_ml_servers ? 1 : 0
  name  = "${local.name_prefix}-ml-lt"

  image_id      = data.aws_ami.linux.id
  instance_type = var.ml_server_instance_type

  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = [var.linux_security_group_id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 100
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e

    yum update -y
    yum install -y ruby wget

    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    cd /home/ec2-user
    wget https://aws-codedeploy-$REGION.s3.$REGION.amazonaws.com/latest/install
    chmod +x ./install
    ./install auto
    systemctl enable codedeploy-agent
    systemctl start codedeploy-agent

    yum install -y amazon-cloudwatch-agent amazon-efs-utils

    # Mount ML EFS if available
    ${var.ml_efs_id != "" ? "mkdir -p /mnt/ml && mount -t efs ${var.ml_efs_id}:/ /mnt/ml" : "echo 'No ML EFS configured'"}

    # Configure CloudWatch Agent for memory metrics and ML logs
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONFIG'
    {
      "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
      },
      "metrics": {
        "namespace": "${var.environment}-ajyal",
        "append_dimensions": {
          "InstanceId": "$${aws:InstanceId}",
          "AutoScalingGroupName": "$${aws:AutoScalingGroupName}"
        },
        "metrics_collected": {
          "mem": {
            "measurement": ["mem_used_percent", "mem_available", "mem_total"],
            "metrics_collection_interval": 60
          },
          "disk": {
            "measurement": ["disk_used_percent", "disk_free", "disk_total"],
            "metrics_collection_interval": 60,
            "resources": ["/", "/mnt/ml"]
          },
          "cpu": {
            "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
            "metrics_collection_interval": 60,
            "totalcpu": true
          }
        }
      },
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/log/messages",
                "log_group_name": "/${var.environment}-ajyal/linux/ml/system",
                "log_stream_name": "{instance_id}",
                "timezone": "UTC"
              },
              {
                "file_path": "/home/ec2-user/ml/logs/*.log",
                "log_group_name": "/${var.environment}-ajyal/linux/ml/application",
                "log_stream_name": "{instance_id}",
                "timezone": "UTC"
              }
            ]
          }
        }
      }
    }
CWCONFIG

    # Start CloudWatch Agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

    echo "Bootstrap complete"
    EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name            = "${local.name_prefix}-ml"
      DeploymentGroup = "linux-ml"
      PatchGroup      = "${local.name_prefix}-linux"
      Platform        = "Linux"
    }
  }

  tags = {
    Name = "${local.name_prefix}-ml-lt"
  }
}

# Content Server Launch Template
resource "aws_launch_template" "content" {
  count = var.enable_content_servers ? 1 : 0
  name  = "${local.name_prefix}-content-lt"

  image_id      = data.aws_ami.linux.id
  instance_type = var.content_server_instance_type

  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = [var.linux_security_group_id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 100
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e

    yum update -y
    yum install -y ruby wget

    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    cd /home/ec2-user
    wget https://aws-codedeploy-$REGION.s3.$REGION.amazonaws.com/latest/install
    chmod +x ./install
    ./install auto
    systemctl enable codedeploy-agent
    systemctl start codedeploy-agent

    yum install -y amazon-cloudwatch-agent amazon-efs-utils

    # Mount Content EFS if available
    ${var.content_efs_id != "" ? "mkdir -p /mnt/content && mount -t efs ${var.content_efs_id}:/ /mnt/content" : "echo 'No Content EFS configured'"}

    # Configure CloudWatch Agent for memory metrics and content server logs
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONFIG'
    {
      "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
      },
      "metrics": {
        "namespace": "${var.environment}-ajyal",
        "append_dimensions": {
          "InstanceId": "$${aws:InstanceId}",
          "AutoScalingGroupName": "$${aws:AutoScalingGroupName}"
        },
        "metrics_collected": {
          "mem": {
            "measurement": ["mem_used_percent", "mem_available", "mem_total"],
            "metrics_collection_interval": 60
          },
          "disk": {
            "measurement": ["disk_used_percent", "disk_free", "disk_total"],
            "metrics_collection_interval": 60,
            "resources": ["/", "/mnt/content"]
          },
          "cpu": {
            "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
            "metrics_collection_interval": 60,
            "totalcpu": true
          }
        }
      },
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/log/messages",
                "log_group_name": "/${var.environment}-ajyal/linux/content/system",
                "log_stream_name": "{instance_id}",
                "timezone": "UTC"
              },
              {
                "file_path": "/home/ec2-user/content/logs/*.log",
                "log_group_name": "/${var.environment}-ajyal/linux/content/application",
                "log_stream_name": "{instance_id}",
                "timezone": "UTC"
              },
              {
                "file_path": "/var/log/nginx/*.log",
                "log_group_name": "/${var.environment}-ajyal/linux/content/nginx",
                "log_stream_name": "{instance_id}",
                "timezone": "UTC"
              }
            ]
          }
        }
      }
    }
CWCONFIG

    # Start CloudWatch Agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

    echo "Bootstrap complete"
    EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name            = "${local.name_prefix}-content"
      DeploymentGroup = "linux-content"
      PatchGroup      = "${local.name_prefix}-linux"
      Platform        = "Linux"
    }
  }

  tags = {
    Name = "${local.name_prefix}-content-lt"
  }
}

#------------------------------------------------------------------------------
# Auto Scaling Groups
#------------------------------------------------------------------------------

# App Server ASG
resource "aws_autoscaling_group" "app" {
  count               = var.enable_app_servers ? 1 : 0
  name                = "${local.name_prefix}-app-asg"
  min_size            = var.app_server_min_size
  max_size            = var.app_server_max_size
  desired_capacity    = var.app_server_desired_size
  vpc_zone_identifier = [var.private_web_subnet_id]

  launch_template {
    id      = aws_launch_template.app_server[0].id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-app-server"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "Ajyal-LMS"
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "Terraform"
    propagate_at_launch = true
  }

  tag {
    key                 = "Team"
    value               = "Slashtec-DevOps"
    propagate_at_launch = true
  }

  tag {
    key                 = "Module"
    value               = "compute"
    propagate_at_launch = true
  }
}

# API Server ASG
resource "aws_autoscaling_group" "api" {
  count               = var.enable_api_servers ? 1 : 0
  name                = "${local.name_prefix}-api-asg"
  min_size            = var.api_server_min_size
  max_size            = var.api_server_max_size
  desired_capacity    = var.api_server_min_size
  vpc_zone_identifier = [var.private_app_subnet_id]
  target_group_arns   = [aws_lb_target_group.api[0].arn]

  launch_template {
    id      = aws_launch_template.api_server[0].id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-api-server"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "Ajyal-LMS"
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "Terraform"
    propagate_at_launch = true
  }

  tag {
    key                 = "Team"
    value               = "Slashtec-DevOps"
    propagate_at_launch = true
  }

  tag {
    key                 = "Module"
    value               = "compute"
    propagate_at_launch = true
  }
}

# Integration Server ASG
resource "aws_autoscaling_group" "integration" {
  count               = var.enable_integration_servers ? 1 : 0
  name                = "${local.name_prefix}-integration-asg"
  min_size            = var.integration_server_min_size
  max_size            = var.integration_server_max_size
  desired_capacity    = var.integration_server_min_size
  vpc_zone_identifier = [var.private_app_subnet_id]

  # Attach to NLB target group if NLB is enabled (port 80 only)
  target_group_arns = var.enable_integration_nlb ? [
    aws_lb_target_group.integration_http[0].arn
  ] : []

  launch_template {
    id      = aws_launch_template.integration_server[0].id
    version = "$Latest"
  }

  health_check_type         = var.enable_integration_nlb ? "ELB" : "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-integration-server"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "Ajyal-LMS"
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "Terraform"
    propagate_at_launch = true
  }

  tag {
    key                 = "Team"
    value               = "Slashtec-DevOps"
    propagate_at_launch = true
  }

  tag {
    key                 = "Module"
    value               = "compute"
    propagate_at_launch = true
  }
}

# Logging Server ASG
resource "aws_autoscaling_group" "logging" {
  count               = var.enable_logging_servers ? 1 : 0
  name                = "${local.name_prefix}-logging-asg"
  min_size            = var.logging_server_min_size
  max_size            = var.logging_server_max_size
  desired_capacity    = var.logging_server_min_size
  vpc_zone_identifier = [var.private_app_subnet_id]

  launch_template {
    id      = aws_launch_template.logging_server[0].id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-logging-server"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "Ajyal-LMS"
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "Terraform"
    propagate_at_launch = true
  }

  tag {
    key                 = "Team"
    value               = "Slashtec-DevOps"
    propagate_at_launch = true
  }

  tag {
    key                 = "Module"
    value               = "compute"
    propagate_at_launch = true
  }
}

# Botpress ASG
resource "aws_autoscaling_group" "botpress" {
  count               = var.enable_botpress_servers ? 1 : 0
  name                = "${local.name_prefix}-botpress-asg"
  min_size            = var.botpress_min_size
  max_size            = var.botpress_max_size
  desired_capacity    = var.botpress_min_size
  vpc_zone_identifier = [var.private_web_subnet_id]
  target_group_arns   = [aws_lb_target_group.botpress[0].arn]

  launch_template {
    id      = aws_launch_template.botpress[0].id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-botpress"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "Ajyal-LMS"
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "Terraform"
    propagate_at_launch = true
  }

  tag {
    key                 = "Team"
    value               = "Slashtec-DevOps"
    propagate_at_launch = true
  }

  tag {
    key                 = "Module"
    value               = "compute"
    propagate_at_launch = true
  }
}

# RabbitMQ - Single instance (no ASG) - see aws_instance.rabbitmq above

# ML Server ASG
resource "aws_autoscaling_group" "ml" {
  count               = var.enable_ml_servers ? 1 : 0
  name                = "${local.name_prefix}-ml-asg"
  min_size            = var.ml_server_min_size
  max_size            = var.ml_server_max_size
  desired_capacity    = var.ml_server_min_size
  vpc_zone_identifier = [var.private_app_subnet_id]

  launch_template {
    id      = aws_launch_template.ml[0].id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-ml"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "Ajyal-LMS"
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "Terraform"
    propagate_at_launch = true
  }

  tag {
    key                 = "Team"
    value               = "Slashtec-DevOps"
    propagate_at_launch = true
  }

  tag {
    key                 = "Module"
    value               = "compute"
    propagate_at_launch = true
  }
}

# Content Server ASG
resource "aws_autoscaling_group" "content" {
  count               = var.enable_content_servers ? 1 : 0
  name                = "${local.name_prefix}-content-asg"
  min_size            = var.content_server_min_size
  max_size            = var.content_server_max_size
  desired_capacity    = var.content_server_min_size
  vpc_zone_identifier = [var.private_app_subnet_id]

  launch_template {
    id      = aws_launch_template.content[0].id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-content"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "Ajyal-LMS"
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "Terraform"
    propagate_at_launch = true
  }

  tag {
    key                 = "Team"
    value               = "Slashtec-DevOps"
    propagate_at_launch = true
  }

  tag {
    key                 = "Module"
    value               = "compute"
    propagate_at_launch = true
  }
}

#------------------------------------------------------------------------------
# Single CloudFront Distribution (Botpress only)
#------------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "main" {
  count   = var.enable_cloudfront && var.enable_botpress_servers ? 1 : 0
  enabled = true
  comment = "${local.name_prefix} CloudFront Distribution (Botpress)"

  # Botpress ALB as origin
  origin {
    domain_name = aws_lb.botpress[0].dns_name
    origin_id   = "botpress-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-CloudFront-Secret"
      value = var.cloudfront_secret_header
    }
  }

  # Default behavior - Botpress ALB
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "botpress-alb"

    forwarded_values {
      query_string = true
      headers      = ["Host", "Origin", "Authorization"]

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 86400
    compress               = true
  }

  # Botpress WebSocket support
  ordered_cache_behavior {
    path_pattern     = "/socket.io/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "botpress-alb"

    forwarded_values {
      query_string = true
      headers      = ["*"]

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = false
  }

  price_class = var.cloudfront_price_class

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # WAF integration (if enabled)
  web_acl_id = var.waf_web_acl_arn

  tags = {
    Name = "${local.name_prefix}-cloudfront"
  }
}
