# Update CloudWatch Agent Configuration
# This script fetches the latest configuration from SSM Parameter Store
# and restarts the CloudWatch agent to apply changes

param(
    [string]$ParameterName,
    [switch]$Restart
)

$ErrorActionPreference = "Stop"

Write-Host "=========================================="
Write-Host "CloudWatch Agent Configuration Update"
Write-Host "=========================================="
Write-Host "Timestamp: $(Get-Date)"
Write-Host ""

#------------------------------------------------------------------------------
# Function: Get instance metadata (IMDSv2 with fallback)
#------------------------------------------------------------------------------
function Get-InstanceMetadata {
    param(
        [string]$Path
    )

    $baseUri = "http://169.254.169.254/latest"
    try {
        $token = Invoke-RestMethod -Uri "$baseUri/api/token" -Method PUT -Headers @{"X-aws-ec2-metadata-token-ttl-seconds"="21600"} -TimeoutSec 5
        return Invoke-RestMethod -Uri "$baseUri/$Path" -Headers @{"X-aws-ec2-metadata-token"=$token} -TimeoutSec 5
    } catch {
        return Invoke-RestMethod -Uri "$baseUri/$Path" -TimeoutSec 5
    }
}

# If no parameter name provided, detect from instance tags
if (-not $ParameterName) {
    Write-Host "Detecting server type from instance tags..."

    try {
        $instanceId = Get-InstanceMetadata -Path "meta-data/instance-id"
        $region = Get-InstanceMetadata -Path "meta-data/placement/region"

        # Get instance tags
        $tags = aws ec2 describe-tags --filters "Name=resource-id,Values=$instanceId" --region $region --output json | ConvertFrom-Json
        $nameTag = ($tags.Tags | Where-Object { $_.Key -eq "Name" }).Value

        # Determine parameter name based on server type
        if ($nameTag -like "*api*") {
            $ParameterName = "/preprod-ajyal/cloudwatch/windows-api-server"
        } elseif ($nameTag -like "*integration*") {
            $ParameterName = "/preprod-ajyal/cloudwatch/windows-integration-server"
        } elseif ($nameTag -like "*app*") {
            $ParameterName = "/preprod-ajyal/cloudwatch/windows-app-server"
        } elseif ($nameTag -like "*logging*") {
            $ParameterName = "/preprod-ajyal/cloudwatch/windows-logging-server"
        } else {
            $ParameterName = "/preprod-ajyal/cloudwatch/windows-default"
        }

        Write-Host "Server type detected: $nameTag"
    } catch {
        Write-Host "Could not detect server type, using default config"
        $ParameterName = "/preprod-ajyal/cloudwatch/windows-default"
    }
}

Write-Host "Using SSM Parameter: $ParameterName"
Write-Host ""

# Fetch and apply CloudWatch configuration
Write-Host "=== Fetching Configuration from SSM ==="
try {
    & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" `
        -a fetch-config -m ec2 -c "ssm:$ParameterName" -s

    Write-Host "CloudWatch Agent configuration updated successfully"
} catch {
    Write-Host "ERROR: Failed to update CloudWatch Agent configuration"
    Write-Host "Error: $_"
    exit 1
}

# Optionally restart the agent
if ($Restart) {
    Write-Host ""
    Write-Host "=== Restarting CloudWatch Agent ==="
    & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a stop
    Start-Sleep -Seconds 3
    & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a start
    Write-Host "CloudWatch Agent restarted"
}

# Show current status
Write-Host ""
Write-Host "=== CloudWatch Agent Status ==="
& "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a status

Write-Host ""
Write-Host "Configuration update complete"
exit 0
