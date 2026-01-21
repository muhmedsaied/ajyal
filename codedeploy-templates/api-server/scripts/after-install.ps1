# After Install - Configure and Start IIS Site
# Uses appcmd.exe instead of PowerShell IIS cmdlets for CodeDeploy compatibility
$ErrorActionPreference = "Stop"
$AppName = "AjyalAPI"
$SiteName = $AppName
$PoolName = "$AppName-Pool"
$AppPath = "C:\inetpub\wwwroot\$AppName"
$Port = 80

# appcmd.exe path
$appcmd = "$env:windir\system32\inetsrv\appcmd.exe"

Write-Host "=========================================="
Write-Host "After Install - $AppName"
Write-Host "=========================================="

# Verify appcmd.exe exists
if (-not (Test-Path $appcmd)) {
    Write-Host "ERROR: appcmd.exe not found. IIS may not be installed."
    exit 1
}
Write-Host "Using appcmd.exe for IIS configuration"

# Check if .NET 6 Hosting Bundle is installed
$aspNetCore = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\ASP.NET Core" -ErrorAction SilentlyContinue
if (-not $aspNetCore) {
    Write-Host "WARNING: ASP.NET Core Hosting Bundle may not be installed!"
    Write-Host "Please install .NET 6 Hosting Bundle manually"
}

# Create Application Pool if not exists
Write-Host "Checking Application Pool: $PoolName"
$poolExists = & $appcmd list apppool /name:"$PoolName" 2>$null
if (-not $poolExists) {
    Write-Host "Creating Application Pool: $PoolName"
    & $appcmd add apppool /name:"$PoolName"
}

# Configure Application Pool for .NET Core
Write-Host "Configuring Application Pool..."
& $appcmd set apppool /apppool.name:"$PoolName" /managedRuntimeVersion:""
& $appcmd set apppool /apppool.name:"$PoolName" /managedPipelineMode:Integrated
& $appcmd set apppool /apppool.name:"$PoolName" /startMode:AlwaysRunning
& $appcmd set apppool /apppool.name:"$PoolName" /processModel.idleTimeout:00:00:00

# Create Website if not exists
Write-Host "Checking Website: $SiteName"
$siteExists = & $appcmd list site /name:"$SiteName" 2>$null
if (-not $siteExists) {
    Write-Host "Creating Website: $SiteName on port $Port"

    # Stop Default Web Site to free up port 80
    $defaultSite = & $appcmd list site /name:"Default Web Site" 2>$null
    if ($defaultSite) {
        Write-Host "Stopping Default Web Site to free port 80"
        & $appcmd stop site /site.name:"Default Web Site" 2>$null
    }

    & $appcmd add site /name:"$SiteName" /physicalPath:"$AppPath" /bindings:http/*:${Port}:
    & $appcmd set app "$SiteName/" /applicationPool:"$PoolName"
} else {
    # Update physical path if site exists
    Write-Host "Updating Website physical path"
    & $appcmd set vdir "$SiteName/" /physicalPath:"$AppPath"
    & $appcmd set app "$SiteName/" /applicationPool:"$PoolName"
}

# Set permissions on application folder
Write-Host "Setting folder permissions..."
$acl = Get-Acl $AppPath
$iisUser = New-Object System.Security.Principal.NTAccount("IIS_IUSRS")
$permission = New-Object System.Security.AccessControl.FileSystemAccessRule($iisUser, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($permission)
Set-Acl $AppPath $acl

# Set permissions on logs folder
$logsPath = "C:\AjyalAPI\logs"
if (Test-Path $logsPath) {
    $acl = Get-Acl $logsPath
    $permission = New-Object System.Security.AccessControl.FileSystemAccessRule($iisUser, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($permission)
    Set-Acl $logsPath $acl
}

#------------------------------------------------------------------------------
# Sync Secrets from SSM Parameter Store (DB connections, credentials)
#------------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Syncing Secrets from SSM Parameter Store ==="

# Get IMDSv2 token for metadata access
try {
    $token = Invoke-RestMethod -Uri http://169.254.169.254/latest/api/token -Method PUT -Headers @{"X-aws-ec2-metadata-token-ttl-seconds"="21600"} -TimeoutSec 5
    $region = Invoke-RestMethod -Uri http://169.254.169.254/latest/meta-data/placement/region -Headers @{"X-aws-ec2-metadata-token"=$token} -TimeoutSec 5
} catch {
    Write-Host "Warning: Could not get region from metadata, using eu-west-1"
    $region = "eu-west-1"
}

# Find the actual app folder (it may be nested)
$appFolder = Get-ChildItem $AppPath -Directory | Where-Object { Test-Path (Join-Path $_.FullName "appsettings.json") } | Select-Object -First 1
if ($appFolder) {
    $appSettingsPath = Join-Path $appFolder.FullName "appsettings.json"
} else {
    $appSettingsPath = Join-Path $AppPath "appsettings.json"
}

# Get secrets (encrypted) - contains DB connections, API keys, etc.
try {
    $secretsParam = "/preprod-ajyal/secrets/api-server/appsettings"
    $secretsValue = aws ssm get-parameter --name $secretsParam --with-decryption --query 'Parameter.Value' --output text --region $region 2>$null

    if ($secretsValue) {
        Write-Host "Found config in SSM: $secretsParam"
        $ssmConfig = $secretsValue | ConvertFrom-Json

        Write-Host "Overwriting config at: $appSettingsPath"
        $ssmConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $appSettingsPath -Encoding UTF8
        Write-Host "appsettings.json overwritten from SSM"
    } elseif (-not (Test-Path $appSettingsPath)) {
        Write-Host "appsettings.json not found at: $appSettingsPath"
    } else {
        Write-Host "No config found at $secretsParam - using package config"
    }
} catch {
    Write-Host "Warning: Could not sync secrets from SSM: $_"
    Write-Host "Continuing with default configuration..."
}

# Start Application Pool
Write-Host "Starting Application Pool: $PoolName"
& $appcmd start apppool /apppool.name:"$PoolName" 2>$null
Start-Sleep -Seconds 3

# Start Website
Write-Host "Starting Website: $SiteName"
& $appcmd start site /site.name:"$SiteName" 2>$null
Start-Sleep -Seconds 5

Write-Host "After-install complete"
exit 0
