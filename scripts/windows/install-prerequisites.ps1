# Windows Server Prerequisites Installation Script
# This script installs all prerequisites needed for Ajyal LMS Windows applications
# Run via SSM or as part of user-data when not using pre-built AMI

param(
    [switch]$ForceReinstall,
    [string]$S3Bucket = "preprod-ajyal-deployments-946846709937",
    [string]$ToolsPrefix = "tools"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

Write-Host "=========================================="
Write-Host "Ajyal LMS Prerequisites Installation"
Write-Host "=========================================="
Write-Host "Timestamp: $(Get-Date)"
Write-Host "Force Reinstall: $ForceReinstall"
Write-Host ""

# Create temp directory
$TempDir = "C:\temp\prerequisites"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

# Ensure TLS 1.2 for downloads
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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

#------------------------------------------------------------------------------
# Function: Ensure AWS CLI is installed
#------------------------------------------------------------------------------
function Ensure-AwsCli {
    $awsExe = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
    $awsCmd = Get-Command aws -ErrorAction SilentlyContinue

    if ($awsCmd -or (Test-Path $awsExe)) {
        return $true
    }

    Write-Host "AWS CLI not found, installing..."
    try {
        $installer = Join-Path $TempDir "AWSCLIV2.msi"
        Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile $installer
        Start-Process msiexec.exe -ArgumentList "/i", $installer, "/quiet" -Wait -NoNewWindow
    } catch {
        Write-Host "WARNING: Failed to install AWS CLI: $_"
        return $false
    }

    return (Test-Path $awsExe) -or (Get-Command aws -ErrorAction SilentlyContinue)
}

#------------------------------------------------------------------------------
# Function: Test if a component is installed
#------------------------------------------------------------------------------
function Test-ComponentInstalled {
    param(
        [string]$Name,
        [scriptblock]$TestScript
    )

    try {
        $result = & $TestScript
        return $result
    } catch {
        return $false
    }
}

#------------------------------------------------------------------------------
# Function: Download from S3
#------------------------------------------------------------------------------
function Get-S3File {
    param(
        [string]$S3Path,
        [string]$LocalPath
    )

    Write-Host "Downloading $S3Path..."

    $region = Get-InstanceMetadata -Path "meta-data/placement/region"

    # Prefer AWS CLI if available (install if missing)
    if (Ensure-AwsCli) {
        try {
            $awsExe = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
            if (Test-Path $awsExe) {
                & $awsExe s3 cp "s3://$S3Bucket/$S3Path" $LocalPath --region $region
            } else {
                aws s3 cp "s3://$S3Bucket/$S3Path" $LocalPath --region $region
            }
            return
        } catch {
            Write-Host "Failed to download via AWS CLI: $_"
        }
    }

    # Fallback to AWS Tools for PowerShell if available
    if (Get-Command Read-S3Object -ErrorAction SilentlyContinue) {
        Read-S3Object -BucketName $S3Bucket -Key $S3Path -File $LocalPath
        return
    }

    throw "Unable to download from S3. AWS CLI and AWSPowerShell are not available."
}

#------------------------------------------------------------------------------
# 1. Install IIS
#------------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Checking IIS ==="

$iisInstalled = Test-ComponentInstalled -Name "IIS" -TestScript {
    $feature = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
    return ($feature -and $feature.Installed)
}

if (-not $iisInstalled -or $ForceReinstall) {
    Write-Host "Installing IIS with ASP.NET..."

    # Try Install-WindowsFeature first (works on Server with GUI)
    try {
        Install-WindowsFeature -Name Web-Server, Web-Asp-Net45, Web-Mgmt-Tools, Web-Mgmt-Console -IncludeManagementTools -ErrorAction Stop
        Write-Host "IIS installed via Install-WindowsFeature"
    } catch {
        Write-Host "Install-WindowsFeature not available, trying DISM..."

        # Use DISM for Server Core
        $features = @(
            "IIS-WebServerRole",
            "IIS-WebServer",
            "IIS-CommonHttpFeatures",
            "IIS-DefaultDocument",
            "IIS-DirectoryBrowsing",
            "IIS-HttpErrors",
            "IIS-StaticContent",
            "IIS-HttpLogging",
            "IIS-RequestMonitor",
            "IIS-RequestFiltering",
            "IIS-ISAPIExtensions",
            "IIS-ISAPIFilter",
            "IIS-NetFxExtensibility45",
            "IIS-ASPNET45",
            "IIS-ManagementConsole",
            "IIS-ManagementService"
        )

        foreach ($feature in $features) {
            dism.exe /Online /Enable-Feature /FeatureName:$feature /All /NoRestart 2>&1 | Out-Null
        }
        Write-Host "IIS installed via DISM"
    }
} else {
    Write-Host "IIS is already installed"
}

#------------------------------------------------------------------------------
# 2. Install .NET Hosting Bundles
#------------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Checking .NET Hosting Bundles ==="

$dotnetExe = "C:\Program Files\dotnet\dotnet.exe"
if (Test-Path $dotnetExe) {
    $installedRuntimes = & $dotnetExe --list-runtimes 2>&1
    Write-Host "Currently installed runtimes:"
    $installedRuntimes | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host "dotnet.exe not found; treating as no runtimes installed"
    $installedRuntimes = @()
}

# .NET 6 Hosting Bundle
$net6Installed = $installedRuntimes | Select-String "Microsoft.AspNetCore.App 6\."
if (-not $net6Installed -or $ForceReinstall) {
    Write-Host "Installing .NET 6 Hosting Bundle..."
    Get-S3File -S3Path "$ToolsPrefix/dotnet-hosting-6.0.36-win.exe" -LocalPath "$TempDir\dotnet-hosting-6.exe"
    Start-Process -FilePath "$TempDir\dotnet-hosting-6.exe" -ArgumentList "/install", "/quiet", "/norestart" -Wait -NoNewWindow
    Write-Host ".NET 6 Hosting Bundle installed"
} else {
    Write-Host ".NET 6 Hosting Bundle already installed"
}

# .NET 8 Hosting Bundle
$net8Installed = $installedRuntimes | Select-String "Microsoft.AspNetCore.App 8\."
if (-not $net8Installed -or $ForceReinstall) {
    Write-Host "Installing .NET 8 Hosting Bundle..."
    Get-S3File -S3Path "$ToolsPrefix/dotnet-hosting-8.0.12-win.exe" -LocalPath "$TempDir\dotnet-hosting-8.exe"
    Start-Process -FilePath "$TempDir\dotnet-hosting-8.exe" -ArgumentList "/install", "/quiet", "/norestart" -Wait -NoNewWindow
    Write-Host ".NET 8 Hosting Bundle installed"
} else {
    Write-Host ".NET 8 Hosting Bundle already installed"
}

# .NET 9 Hosting Bundle
$net9Installed = $installedRuntimes | Select-String "Microsoft.AspNetCore.App 9\."
if (-not $net9Installed -or $ForceReinstall) {
    Write-Host "Installing .NET 9 Hosting Bundle..."
    Get-S3File -S3Path "$ToolsPrefix/dotnet-hosting-9.0.1-win.exe" -LocalPath "$TempDir\dotnet-hosting-9.exe"
    Start-Process -FilePath "$TempDir\dotnet-hosting-9.exe" -ArgumentList "/install", "/quiet", "/norestart" -Wait -NoNewWindow
    Write-Host ".NET 9 Hosting Bundle installed"
} else {
    Write-Host ".NET 9 Hosting Bundle already installed"
}

#------------------------------------------------------------------------------
# 3. Install CodeDeploy Agent
#------------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Checking CodeDeploy Agent ==="

$codeDeployInstalled = Get-Service -Name codedeployagent -ErrorAction SilentlyContinue
if (-not $codeDeployInstalled -or $ForceReinstall) {
    Write-Host "Installing CodeDeploy Agent..."
    $region = Get-InstanceMetadata -Path "meta-data/placement/region"
    $source = "https://aws-codedeploy-$region.s3.$region.amazonaws.com/latest/codedeploy-agent.msi"
    Invoke-WebRequest -Uri $source -OutFile "$TempDir\codedeploy-agent.msi"
    Start-Process msiexec.exe -ArgumentList "/i", "$TempDir\codedeploy-agent.msi", "/quiet" -Wait -NoNewWindow
    Write-Host "CodeDeploy Agent installed"
} else {
    Write-Host "CodeDeploy Agent already installed"
    Write-Host "Status: $($codeDeployInstalled.Status)"
}

#------------------------------------------------------------------------------
# 4. Install CloudWatch Agent
#------------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Checking CloudWatch Agent ==="

$cwAgentInstalled = Test-Path "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1"
if (-not $cwAgentInstalled -or $ForceReinstall) {
    Write-Host "Installing CloudWatch Agent..."
    $region = Get-InstanceMetadata -Path "meta-data/placement/region"
    $cwSource = "https://s3.$region.amazonaws.com/amazoncloudwatch-agent-$region/windows/amd64/latest/amazon-cloudwatch-agent.msi"
    Invoke-WebRequest -Uri $cwSource -OutFile "$TempDir\amazon-cloudwatch-agent.msi"
    Start-Process msiexec.exe -ArgumentList "/i", "$TempDir\amazon-cloudwatch-agent.msi", "/quiet" -Wait -NoNewWindow
    Write-Host "CloudWatch Agent installed"
} else {
    Write-Host "CloudWatch Agent already installed"
}

#------------------------------------------------------------------------------
# 5. Configure CloudWatch Agent from SSM Parameter Store
#------------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Configuring CloudWatch Agent ==="

# Determine server type from instance tags
try {
    $instanceId = Get-InstanceMetadata -Path "meta-data/instance-id"
    $region = Get-InstanceMetadata -Path "meta-data/placement/region"

    # Get instance tags to determine server type
    $tags = aws ec2 describe-tags --filters "Name=resource-id,Values=$instanceId" --region $region --output json | ConvertFrom-Json
    $nameTag = ($tags.Tags | Where-Object { $_.Key -eq "Name" }).Value

    # Determine parameter name based on server type
    if ($nameTag -like "*api*") {
        $parameterName = "/preprod-ajyal/cloudwatch/windows-api-server"
    } elseif ($nameTag -like "*integration*") {
        $parameterName = "/preprod-ajyal/cloudwatch/windows-integration-server"
    } elseif ($nameTag -like "*app*") {
        $parameterName = "/preprod-ajyal/cloudwatch/windows-app-server"
    } elseif ($nameTag -like "*logging*") {
        $parameterName = "/preprod-ajyal/cloudwatch/windows-logging-server"
    } else {
        $parameterName = "/preprod-ajyal/cloudwatch/windows-default"
    }

    Write-Host "Server type detected: $nameTag"
    Write-Host "Using CloudWatch config from SSM: $parameterName"

    # Fetch and apply CloudWatch config
    & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" `
        -a fetch-config -m ec2 -c "ssm:$parameterName" -s

    Write-Host "CloudWatch Agent configured from SSM Parameter Store"
} catch {
    Write-Host "WARNING: Could not configure CloudWatch Agent from SSM: $_"
    Write-Host "CloudWatch Agent will need to be configured manually"
}

#------------------------------------------------------------------------------
# 6. Create required directories
#------------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Creating Required Directories ==="

$directories = @(
    "C:\inetpub\wwwroot\AjyalAPI",
    "C:\inetpub\wwwroot\AjyalIntegration",
    "C:\AjyalAPI\logs",
    "C:\AjyalIntegration\logs",
    "C:\Backups"
)

foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "Created: $dir"
    } else {
        Write-Host "Exists: $dir"
    }
}

#------------------------------------------------------------------------------
# 7. Restart IIS to apply changes
#------------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Restarting IIS ==="
iisreset /restart
Write-Host "IIS restarted"

#------------------------------------------------------------------------------
# 8. Cleanup
#------------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Cleanup ==="
Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Temporary files cleaned up"

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
Write-Host ""
Write-Host "=========================================="
Write-Host "Prerequisites Installation Complete"
Write-Host "=========================================="
Write-Host ""
Write-Host "Installed Components:"
Write-Host "  - IIS with ASP.NET"
Write-Host "  - .NET 6, 8, 9 Hosting Bundles"
Write-Host "  - CodeDeploy Agent"
Write-Host "  - CloudWatch Agent"
Write-Host ""
Write-Host "Note: A reboot may be required for all changes to take effect"
Write-Host ""

# Verify .NET runtimes
Write-Host "=== Installed .NET Runtimes ==="
if (Test-Path $dotnetExe) {
    & $dotnetExe --list-runtimes
} else {
    Write-Host "dotnet.exe not found after installation"
}

exit 0
