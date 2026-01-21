# After Install - Configure AjyalIntegration site and service applications
# Uses appcmd.exe instead of PowerShell IIS cmdlets for CodeDeploy compatibility
$ErrorActionPreference = "Stop"
$AppRoot = "C:\inetpub\wwwroot\AjyalIntegration"
$SiteName = "AjyalIntegration"
$RootPoolName = "$SiteName-Pool"
$Port = 80  # Changed from 5000 to 80 for production use
$LogsRoot = "C:\AjyalIntegration\logs"
$BackupRoot = "C:\Backups\AjyalIntegration"

# appcmd.exe path
$appcmd = "$env:windir\system32\inetsrv\appcmd.exe"

function Invoke-WithDeploymentLock([scriptblock]$script) {
    $mutexName = "Global\AjyalCodeDeployLock"
    $mutex = $null
    $hasHandle = $false
    try {
        $mutex = New-Object System.Threading.Mutex($false, $mutexName)
        $hasHandle = $mutex.WaitOne([TimeSpan]::FromMinutes(30))
        if (-not $hasHandle) {
            Write-Host "ERROR: Timed out waiting for deployment lock"
            return 1
        }
        return & $script
    } catch {
        Write-Host "ERROR: Deployment lock failure: $($_.Exception.Message)"
        return 1
    } finally {
        if ($hasHandle -and $mutex) {
            $mutex.ReleaseMutex() | Out-Null
        }
        if ($mutex) {
            $mutex.Dispose()
        }
    }
}

function Invoke-Deployment {
Write-Host "=========================================="
Write-Host "After Install - AjyalIntegration services"
Write-Host "=========================================="

# Verify appcmd.exe exists
if (-not (Test-Path $appcmd)) {
    Write-Host "ERROR: appcmd.exe not found. IIS may not be installed."
    return 1
}
Write-Host "Using appcmd.exe for IIS configuration"

# Ensure base directories exist
New-Item -ItemType Directory -Path $AppRoot -Force | Out-Null
New-Item -ItemType Directory -Path $LogsRoot -Force | Out-Null

# Check if ASP.NET Core Hosting Bundle is installed (informational)
$aspNetCore = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\ASP.NET Core" -ErrorAction SilentlyContinue
if (-not $aspNetCore) {
    Write-Host "WARNING: ASP.NET Core Hosting Bundle may not be installed!"
}

function Get-ManagedRuntime([string]$servicePath) {
    if (Test-Path (Join-Path $servicePath "appsettings.json")) {
        return ""
    }
    if (Test-Path (Join-Path $servicePath "web.config")) {
        return "v4.0"
    }
    return ""
}

function Ensure-AppPool([string]$poolName, [string]$managedRuntime) {
    & $appcmd list apppool /name:"$poolName" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Creating Application Pool: $poolName"
        & $appcmd add apppool /name:"$poolName"
    }

    & $appcmd set apppool /apppool.name:"$poolName" /managedRuntimeVersion:"$managedRuntime"
    & $appcmd set apppool /apppool.name:"$poolName" /managedPipelineMode:Integrated
    & $appcmd set apppool /apppool.name:"$poolName" /startMode:AlwaysRunning
    & $appcmd set apppool /apppool.name:"$poolName" /processModel.idleTimeout:00:00:00
    & $appcmd start apppool /apppool.name:"$poolName" 2>$null
}

function Ensure-App([string]$alias, [string]$physicalPath, [string]$poolName) {
    $appId = "$SiteName/$alias"
    & $appcmd list app /name:"$appId" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Creating IIS application: /$alias"
        & $appcmd add app /site.name:"$SiteName" /path:"/$alias" /physicalPath:"$physicalPath" /applicationPool:"$poolName"
    }

    & $appcmd set app /app.name:"$appId" /physicalPath:"$physicalPath"
    & $appcmd set app /app.name:"$appId" /applicationPool:"$poolName"
}

function Get-SsmValue([string]$paramName, [string]$region) {
    try {
        $value = aws ssm get-parameter --name $paramName --with-decryption --query 'Parameter.Value' --output text --region $region 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $value -or $value -eq "None") {
            return $null
        }
        return $value
    } catch {
        return $null
    }
}

function Write-ConfigFile([string]$path, [string]$content) {
    $content | Out-File -FilePath $path -Encoding UTF8
}

function Sync-ServiceConfig([string]$serviceName, [string]$servicePath, [string]$region) {
    $appSettingsPath = Join-Path $servicePath "appsettings.json"
    if (Test-Path $appSettingsPath) {
        $paramBase = "/preprod-ajyal/secrets/integration-services/$serviceName"
        $value = Get-SsmValue "$paramBase/appsettings.json" $region
        if (-not $value) {
            $value = Get-SsmValue "$paramBase/appsettings" $region
        }
        if (-not $value -and $serviceName -eq "EduK12API_LMSIntegration") {
            $value = Get-SsmValue "/preprod-ajyal/secrets/integration-server/appsettings" $region
            if (-not $value) {
                $value = Get-SsmValue "/preprod-ajyal/secrets/integration-server/appsettings.json" $region
            }
        }

        if ($value) {
            Write-Host "Overwriting appsettings.json for $serviceName from SSM"
            try {
                $json = $value | ConvertFrom-Json -ErrorAction Stop
                $json | ConvertTo-Json -Depth 10 | Out-File -FilePath $appSettingsPath -Encoding UTF8
            } catch {
                Write-Host "SSM content is not valid JSON, writing raw text"
                Write-ConfigFile $appSettingsPath $value
            }
        }
    }
}

function Normalize-FileMgmtS3([string]$appRoot) {
    $legacyRoot = Join-Path $appRoot "S3 Publish"
    if (-not (Test-Path $legacyRoot)) {
        return
    }

    $publishDir = Get-ChildItem -Path $legacyRoot -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $publishDir) {
        return
    }

    $target = Join-Path $appRoot "FileMgmtS3"
    if (Test-Path $target) {
        Remove-Item -Path $target -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -Path $publishDir.FullName -Destination $target -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $legacyRoot -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-ServiceDirs([string]$appRoot, [string[]]$skipNames) {
    $dirs = @()
    $topDirs = Get-ChildItem -Path $appRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $skipNames -notcontains $_.Name }
    foreach ($dir in $topDirs) {
        $dirs += $dir
    }
    return $dirs
}

# Create root app pool if needed
Ensure-AppPool $RootPoolName ""

# Create Website if not exists
Write-Host "Checking Website: $SiteName"
$siteExists = & $appcmd list site /name:"$SiteName" 2>$null
if (-not $siteExists) {
    Write-Host "Creating Website: $SiteName on port $Port"
    & $appcmd add site /name:"$SiteName" /physicalPath:"$AppRoot" /bindings:http/*:${Port}:
} else {
    Write-Host "Updating Website physical path and binding"
    & $appcmd set vdir "$SiteName/" /physicalPath:"$AppRoot"
    # Update binding to use port 80 (in case it was previously on a different port)
    & $appcmd set site /site.name:"$SiteName" /bindings:http/*:${Port}: 2>$null
}
& $appcmd set app "$SiteName/" /applicationPool:"$RootPoolName"

# Set permissions on application folder
Write-Host "Setting folder permissions..."
$acl = Get-Acl $AppRoot
$iisUser = New-Object System.Security.Principal.NTAccount("IIS_IUSRS")
$permission = New-Object System.Security.AccessControl.FileSystemAccessRule($iisUser, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($permission)
Set-Acl $AppRoot $acl

# Set permissions on logs folder
if (Test-Path $LogsRoot) {
    $acl = Get-Acl $LogsRoot
    $permission = New-Object System.Security.AccessControl.FileSystemAccessRule($iisUser, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($permission)
    Set-Acl $LogsRoot $acl
}

# Get IMDSv2 token for metadata access
try {
    $token = Invoke-RestMethod -Uri http://169.254.169.254/latest/api/token -Method PUT -Headers @{"X-aws-ec2-metadata-token-ttl-seconds"="21600"} -TimeoutSec 5
    $region = Invoke-RestMethod -Uri http://169.254.169.254/latest/meta-data/placement/region -Headers @{"X-aws-ec2-metadata-token"=$token} -TimeoutSec 5
} catch {
    Write-Host "Warning: Could not get region from metadata, using eu-west-1"
    $region = "eu-west-1"
}

# Restore preserved services from previous deployments
$preserveRoot = Join-Path $BackupRoot "preserve-$($env:DEPLOYMENT_ID)"
if (Test-Path $preserveRoot) {
    $preserved = Get-ChildItem -Path $preserveRoot -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $preserved) {
        $target = Join-Path $AppRoot $dir.Name
        if (-not (Test-Path $target)) {
            Write-Host "Restoring preserved service: $($dir.Name)"
            Copy-Item -Path $dir.FullName -Destination $target -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Normalize FileMgmtS3 folder structure if needed
Normalize-FileMgmtS3 $AppRoot

# Configure all service folders under AjyalIntegration root
$skipDirs = @("logs", "S3 Publish")
$serviceDirs = Get-ServiceDirs $AppRoot $skipDirs

if (-not $serviceDirs -or $serviceDirs.Count -eq 0) {
    Write-Host "No service folders found under $AppRoot"
} else {
    foreach ($dir in $serviceDirs) {
        $serviceName = $dir.Name
        $poolName = "$serviceName-Pool"
        $managedRuntime = Get-ManagedRuntime $dir.FullName

        Write-Host "Configuring service: $serviceName => /$serviceName"
        Ensure-AppPool $poolName $managedRuntime
        Ensure-App $serviceName $dir.FullName $poolName
        Sync-ServiceConfig $serviceName $dir.FullName $region
    }
}

# Stop Default Web Site to free up port 80
Write-Host "Stopping Default Web Site..."
& $appcmd stop site /site.name:"Default Web Site" 2>$null

# Start Website
Write-Host "Starting Website: $SiteName"
& $appcmd start site /site.name:"$SiteName" 2>$null
Start-Sleep -Seconds 5

Write-Host "After-install complete"
return 0
}

$exitCode = Invoke-WithDeploymentLock { Invoke-Deployment }
exit $exitCode
