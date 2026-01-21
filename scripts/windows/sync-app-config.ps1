# Sync Application Secrets from SSM Parameter Store
# This script fetches secrets (DB connections, API keys) from SSM and updates appsettings.json
# Can be run manually, via SSM, or as a CodeDeploy hook

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("api-server", "integration-server", "app-server")]
    [string]$ServerType,

    [Parameter(Mandatory=$false)]
    [string]$AppPath,

    [switch]$RestartIIS,
    [switch]$BackupConfig
)

$ErrorActionPreference = "Stop"

Write-Host "=========================================="
Write-Host "Application Secrets Sync"
Write-Host "=========================================="
Write-Host "Timestamp: $(Get-Date)"

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

# Auto-detect server type from instance tags if not provided
if (-not $ServerType) {
    try {
        $instanceId = Get-InstanceMetadata -Path "meta-data/instance-id"
        $region = Get-InstanceMetadata -Path "meta-data/placement/region"
        $tags = aws ec2 describe-tags --filters "Name=resource-id,Values=$instanceId" --region $region --output json | ConvertFrom-Json
        $nameTag = ($tags.Tags | Where-Object { $_.Key -eq "Name" }).Value

        if ($nameTag -like "*api*") {
            $ServerType = "api-server"
        } elseif ($nameTag -like "*integration*") {
            $ServerType = "integration-server"
        } elseif ($nameTag -like "*app*") {
            $ServerType = "app-server"
        } else {
            Write-Host "Could not detect server type from tags: $nameTag"
            exit 1
        }
        Write-Host "Detected server type: $ServerType"
    } catch {
        Write-Host "Failed to detect server type: $_"
        exit 1
    }
}

# Set default paths based on server type (secrets only - DB connections, API keys)
$configMapping = @{
    "api-server" = @{
        AppPath = "C:\inetpub\wwwroot\AjyalAPI\AuthorizationServerCore"
        SSMSecretsBase = "/preprod-ajyal/secrets/api-server"
        ConfigFiles = @("appsettings.json")
    }
    "integration-server" = @{
        AppPath = "C:\inetpub\wwwroot\AjyalIntegration\APIK12Gateway"
        SSMSecretsBase = "/preprod-ajyal/secrets/integration-server"
        ConfigFiles = @("appsettings.json")
    }
    "app-server" = @{
        AppPath = "C:\inetpub\wwwroot\AjyalApp"
        SSMSecretsBase = "/preprod-ajyal/secrets/app-server"
        ConfigFiles = @("appsettings.json")
    }
}

$config = $configMapping[$ServerType]
if (-not $AppPath) {
    $AppPath = $config.AppPath
}

Write-Host "Server Type: $ServerType"
Write-Host "App Path: $AppPath"
Write-Host ""

#------------------------------------------------------------------------------
# Function: Get parameter from SSM
#------------------------------------------------------------------------------
function Get-SSMConfig {
    param(
        [string]$ParameterName,
        [switch]$Decrypt
    )

    try {
        $decryptFlag = if ($Decrypt) { "--with-decryption" } else { "" }
        $value = aws ssm get-parameter --name $ParameterName $decryptFlag --query 'Parameter.Value' --output text 2>$null
        return $value
    } catch {
        Write-Host "Parameter $ParameterName not found"
        return $null
    }
}

#------------------------------------------------------------------------------
# Function: Merge JSON objects
#------------------------------------------------------------------------------
function Merge-JsonObjects {
    param(
        [PSCustomObject]$Base,
        [PSCustomObject]$Override
    )

    $result = $Base.PSObject.Copy()

    foreach ($prop in $Override.PSObject.Properties) {
        if ($result.PSObject.Properties[$prop.Name]) {
            if ($prop.Value -is [PSCustomObject] -and $result.($prop.Name) -is [PSCustomObject]) {
                $result.($prop.Name) = Merge-JsonObjects -Base $result.($prop.Name) -Override $prop.Value
            } else {
                $result.($prop.Name) = $prop.Value
            }
        } else {
            $result | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
        }
    }

    return $result
}

#------------------------------------------------------------------------------
# Backup existing config
#------------------------------------------------------------------------------
if ($BackupConfig) {
    Write-Host "=== Backing up existing configuration ==="
    $backupDir = "C:\Backups\config\$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    foreach ($configFile in $config.ConfigFiles) {
        $sourcePath = Join-Path $AppPath $configFile
        if (Test-Path $sourcePath) {
            Copy-Item $sourcePath -Destination $backupDir
            Write-Host "Backed up: $configFile"
        }
    }
}

#------------------------------------------------------------------------------
# Fetch and apply secrets (DB connections, API keys)
#------------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Fetching secrets from SSM ==="

# Get secrets (sensitive - connection strings, API keys, etc.)
$ssmSecretsParam = "$($config.SSMSecretsBase)/appsettings"
$ssmSecrets = Get-SSMConfig -ParameterName $ssmSecretsParam -Decrypt

if (-not $ssmSecrets) {
    Write-Host "No SSM secrets found at: $ssmSecretsParam"
    Write-Host ""
    Write-Host "To create secrets, use:"
    Write-Host "  aws ssm put-parameter --name '$ssmSecretsParam' --type 'SecureString' --value '<secrets-json>'"
    Write-Host ""
    Write-Host "Expected format:"
    Write-Host '  {"ConnectionStrings":{"DefaultConnection":"Server=xxx;..."},"ITGSettings":{"ClientID":"xxx"}}'
    Write-Host ""
    Write-Host "No changes made to configuration."
    exit 0
}

#------------------------------------------------------------------------------
# Update appsettings.json with secrets
#------------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Updating appsettings.json with secrets ==="

$appSettingsPath = Join-Path $AppPath "appsettings.json"

if (Test-Path $appSettingsPath) {
    # Read current config
    $currentConfig = Get-Content $appSettingsPath -Raw | ConvertFrom-Json

    # Apply secrets (ConnectionStrings, API keys, etc.)
    $ssmSecretsObj = $ssmSecrets | ConvertFrom-Json
    $currentConfig = Merge-JsonObjects -Base $currentConfig -Override $ssmSecretsObj
    Write-Host "Applied secrets from SSM"

    # Write updated config
    $currentConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $appSettingsPath -Encoding UTF8
    Write-Host "Updated: appsettings.json"
} else {
    Write-Host "ERROR: appsettings.json not found at: $appSettingsPath"
    exit 1
}

#------------------------------------------------------------------------------
# Restart IIS if requested
#------------------------------------------------------------------------------
if ($RestartIIS) {
    Write-Host ""
    Write-Host "=== Restarting IIS ==="
    iisreset /restart
    Write-Host "IIS restarted"
}

Write-Host ""
Write-Host "=========================================="
Write-Host "Secrets sync complete"
Write-Host "=========================================="

exit 0
