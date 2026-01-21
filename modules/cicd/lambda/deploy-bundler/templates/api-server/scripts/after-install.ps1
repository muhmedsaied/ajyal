# After Install - Configure AjyalAPI site and service applications
# Uses appcmd.exe instead of PowerShell IIS cmdlets for CodeDeploy compatibility
$ErrorActionPreference = "Stop"
$AppRoot = "C:\inetpub\wwwroot\AjyalAPI"
$SiteName = "AjyalAPI"
$RootPoolName = "$SiteName-Pool"
$Port = 80
$LogsRoot = "C:\AjyalAPI\logs"
$BackupRoot = "C:\Backups\AjyalAPI"

# appcmd.exe path
$appcmd = "$env:windir\system32\inetsrv\appcmd.exe"

$aliasMap = @{
    "AuthorizationServerCore" = "ITG_AuthorizationServerCode"
    "EduWaveAssessment.API"   = "DashBoardAPI"
    "WebSocketsWebAPI"        = "WebSocketWebAPI"
}

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
Write-Host "After Install - AjyalAPI services"
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

# Check if .NET Hosting Bundle is installed (informational)
$aspNetCore = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\ASP.NET Core" -ErrorAction SilentlyContinue
if (-not $aspNetCore) {
    Write-Host "WARNING: ASP.NET Core Hosting Bundle may not be installed!"
}

function Get-AppAlias([string]$name) {
    if ($aliasMap.ContainsKey($name)) {
        return $aliasMap[$name]
    }
    return $name
}

function Get-BundleAppPath() {
    if ($env:DEPLOYMENT_ROOT) {
        $candidate = Join-Path $env:DEPLOYMENT_ROOT "app"
        if (Test-Path $candidate) {
            return $candidate
        }
    }
    if ($PSScriptRoot) {
        $candidate = Join-Path $PSScriptRoot "..\\app"
        $resolved = Resolve-Path $candidate -ErrorAction SilentlyContinue
        if ($resolved) {
            return $resolved.Path
        }
    }
    return ""
}

function Get-PreserveRoot([string]$backupRoot) {
    $deploymentId = $env:DEPLOYMENT_ID
    if (-not $deploymentId) {
        $deploymentId = Get-Date -Format "yyyyMMdd-HHmmss"
    }
    return Join-Path $backupRoot "preserve-$deploymentId"
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

function Get-DeploymentServices([string]$bundleAppPath, [string]$appRoot) {
    $services = @()
    if (-not $bundleAppPath -or -not (Test-Path $bundleAppPath)) {
        return $services
    }

    $topDirs = Get-ChildItem -Path $bundleAppPath -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $topDirs) {
        if ($dir.Name -eq "WebSocketFullFiles") {
            $subDirs = Get-ChildItem -Path $dir.FullName -Directory -ErrorAction SilentlyContinue
            foreach ($sub in $subDirs) {
                $services += [pscustomobject]@{
                    Name       = $sub.Name
                    TargetPath = Join-Path (Join-Path $appRoot "WebSocketFullFiles") $sub.Name
                }
            }
        } else {
            $services += [pscustomobject]@{
                Name       = $dir.Name
                TargetPath = Join-Path $appRoot $dir.Name
            }
        }
    }

    return $services
}

function Get-ServiceDirs([string]$appRoot, [string[]]$skipNames) {
    $dirs = @()
    $topDirs = Get-ChildItem -Path $appRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $skipNames -notcontains $_.Name }
    foreach ($dir in $topDirs) {
        if ($dir.Name -eq "WebSocketFullFiles") {
            $subDirs = Get-ChildItem -Path $dir.FullName -Directory -ErrorAction SilentlyContinue
            foreach ($sub in $subDirs) {
                $dirs += $sub
            }
        } else {
            $dirs += $dir
        }
    }
    return $dirs
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
        $paramBase = "/preprod-ajyal/secrets/api-services/$serviceName"
        $value = Get-SsmValue "$paramBase/appsettings.json" $region
        if (-not $value) {
            $value = Get-SsmValue "$paramBase/appsettings" $region
        }
        if (-not $value -and $serviceName -eq "APIK12Gateway") {
            $value = Get-SsmValue "/preprod-ajyal/secrets/api-server/appsettings" $region
            if (-not $value) {
                $value = Get-SsmValue "/preprod-ajyal/secrets/api-server/appsettings.json" $region
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

    $webConfigPath = Join-Path $servicePath "web.config"
    if (Test-Path $webConfigPath) {
        $paramName = "/preprod-ajyal/secrets/api-services/$serviceName/web.config"
        $value = Get-SsmValue $paramName $region
        if ($value) {
            Write-Host "Overwriting web.config for $serviceName from SSM"
            Write-ConfigFile $webConfigPath $value
        }
    }

    $ocelotPath = Join-Path $servicePath "ocelot.json"
    if (Test-Path $ocelotPath) {
        $paramName = "/preprod-ajyal/secrets/api-services/$serviceName/ocelot.json"
        $value = Get-SsmValue $paramName $region
        if ($value) {
            Write-Host "Overwriting ocelot.json for $serviceName from SSM"
            Write-ConfigFile $ocelotPath $value
        }
    }

    if ($serviceName -eq "DBAccessSqlAPI") {
        $paramName = "/preprod-ajyal/secrets/api-services/$serviceName/SystemSettingsSqlDbAccess.xml"
        $value = Get-SsmValue $paramName $region
        if ($value) {
            $settingsPath = "C:\EduWaveK12Jordan\Settings\Oracle\SystemSettingsSqlDbAccess.xml"
            $settingsDir = Split-Path $settingsPath -Parent
            New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
            Write-Host "Writing SystemSettingsSqlDbAccess.xml for $serviceName"
            Write-ConfigFile $settingsPath $value
        }
    }
}

# Stop Default Web Site to free port 80
$defaultSite = & $appcmd list site /name:"Default Web Site" 2>$null
if ($defaultSite) {
    Write-Host "Stopping Default Web Site to free port 80"
    & $appcmd stop site /site.name:"Default Web Site" 2>$null
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
    Write-Host "Updating Website physical path"
    & $appcmd set vdir "$SiteName/" /physicalPath:"$AppRoot"
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
$preserveRoot = Get-PreserveRoot $BackupRoot
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

# Configure all service folders under AjyalAPI root
$skipDirs = @("logs")
$serviceDirs = Get-ServiceDirs $AppRoot $skipDirs

if (-not $serviceDirs -or $serviceDirs.Count -eq 0) {
    Write-Host "No service folders found under $AppRoot"
} else {
    foreach ($dir in $serviceDirs) {
        $serviceName = $dir.Name
        $alias = Get-AppAlias $serviceName
        $poolName = "$alias-Pool"
        $managedRuntime = Get-ManagedRuntime $dir.FullName

        Write-Host "Configuring service: $serviceName => /$alias"
        Ensure-AppPool $poolName $managedRuntime
        Ensure-App $alias $dir.FullName $poolName
        Sync-ServiceConfig $serviceName $dir.FullName $region
    }
}

# Start Website
Write-Host "Starting Website: $SiteName"
& $appcmd start site /site.name:"$SiteName" 2>$null
Start-Sleep -Seconds 5

Write-Host "After-install complete"
return 0
}

$exitCode = Invoke-WithDeploymentLock { Invoke-Deployment }
exit $exitCode
