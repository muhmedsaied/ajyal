# Before Install - Prepare AjyalIntegration root and target service folders
$ErrorActionPreference = "Continue"
$AppRoot = "C:\inetpub\wwwroot\AjyalIntegration"
$SiteName = "AjyalIntegration"
$BackupRoot = "C:\Backups\AjyalIntegration"
$LogsRoot = "C:\AjyalIntegration\logs"
$appcmd = "$env:windir\system32\inetsrv\appcmd.exe"

function Get-AppAlias([string]$name) {
    if ($name -eq "S3 Publish") {
        return "FileMgmtS3"
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

function Get-DeploymentServices([string]$bundleAppPath, [string]$appRoot) {
    $services = @()
    if (-not $bundleAppPath -or -not (Test-Path $bundleAppPath)) {
        return $services
    }

    $topDirs = Get-ChildItem -Path $bundleAppPath -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $topDirs) {
        if ($dir.Name -eq "S3 Publish") {
            $publishDir = Get-ChildItem -Path $dir.FullName -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($publishDir) {
                $services += [pscustomobject]@{
                    Name       = "FileMgmtS3"
                    TargetPath = Join-Path $appRoot "FileMgmtS3"
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

function Get-ExistingServiceDirs([string]$appRoot) {
    $dirs = @()
    $topDirs = Get-ChildItem -Path $appRoot -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $topDirs) {
        if ($dir.Name -eq "logs" -or $dir.Name -eq "S3 Publish") {
            continue
        }
        $dirs += $dir
    }
    return $dirs
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
Write-Host "Before Install - AjyalIntegration services"
Write-Host "=========================================="

# Create base directories if they don't exist
New-Item -ItemType Directory -Path $AppRoot -Force | Out-Null
New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
New-Item -ItemType Directory -Path $LogsRoot -Force | Out-Null

$bundleAppPath = Get-BundleAppPath
$services = Get-DeploymentServices $bundleAppPath $AppRoot
$bundleNames = @()
if ($services -and $services.Count -gt 0) {
    $bundleNames = $services | ForEach-Object { $_.Name }
}

$existingDirs = Get-ChildItem -Path $AppRoot -Directory -ErrorAction SilentlyContinue
$existingServiceDirs = Get-ExistingServiceDirs $AppRoot
$preserveRoot = Get-PreserveRoot $BackupRoot

foreach ($dir in $existingDirs) {
    if ($bundleNames -notcontains $dir.Name) {
        Write-Host "Preserving existing service: $($dir.Name)"
        New-Item -ItemType Directory -Path $preserveRoot -Force | Out-Null
        Copy-Item -Path $dir.FullName -Destination (Join-Path $preserveRoot $dir.Name) -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (Test-Path $appcmd) {
    foreach ($dir in $existingServiceDirs) {
        $alias = Get-AppAlias $dir.Name
        $poolName = "$alias-Pool"
        try {
            & $appcmd list apppool /name:"$poolName" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Stopping Application Pool: $poolName"
                & $appcmd stop apppool /apppool.name:"$poolName" 2>$null
            }
        } catch {
            Write-Host "Warning: Could not stop pool ${poolName}: $_"
        }
    }

    try {
        & $appcmd list site /name:"$SiteName" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Stopping Website: $SiteName"
            & $appcmd stop site /site.name:"$SiteName" 2>$null
        }
    } catch {
        Write-Host "Warning: Could not stop site ${SiteName}: $_"
    }
}

if (-not $services -or $services.Count -eq 0) {
    Write-Host "No service folders detected in bundle - skipping cleanup"
} else {
    foreach ($service in $services) {
        $alias = Get-AppAlias $service.Name
        $poolName = "$alias-Pool"

        if (Test-Path $appcmd) {
            try {
                $poolExists = & $appcmd list apppool /name:"$poolName" 2>$null
                if ($poolExists) {
                    Write-Host "Stopping Application Pool: $poolName"
                    & $appcmd stop apppool /apppool.name:"$poolName" 2>$null
                }
            } catch {
                Write-Host "Warning: Could not stop pool ${poolName}: $_"
            }
        }

        if (Test-Path $service.TargetPath) {
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $backupPath = Join-Path $BackupRoot "$alias-$timestamp"
            Write-Host "Backing up $($service.TargetPath) to $backupPath"
            New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
            Copy-Item -Path "$($service.TargetPath)\*" -Destination $backupPath -Recurse -Force -ErrorAction SilentlyContinue

            Write-Host "Cleaning target path: $($service.TargetPath)"
            Remove-Item -Path $service.TargetPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "Before-install complete"
return 0
}

$exitCode = Invoke-WithDeploymentLock { Invoke-Deployment }
exit $exitCode
