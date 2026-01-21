# Before Install - Prepare AjyalApp site
$ErrorActionPreference = "Continue"
$AppRoot = "C:\inetpub\wwwroot\AjyalApp"
$SiteName = "AjyalApp"
$BackupRoot = "C:\Backups\AjyalApp"
$LogsRoot = "C:\AjyalApp\logs"
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
    Write-Host "Before Install - AjyalApp"
    Write-Host "=========================================="

    New-Item -ItemType Directory -Path $AppRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $LogsRoot -Force | Out-Null

    if (Test-Path $appcmd) {
        try {
            & $appcmd list apppool /name:"$SiteName-Pool" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Stopping Application Pool: $SiteName-Pool"
                & $appcmd stop apppool /apppool.name:"$SiteName-Pool" 2>$null
            }
        } catch {
            Write-Host "Warning: Could not stop pool ${SiteName}-Pool: $_"
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

    if (Test-Path $AppRoot) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = Join-Path $BackupRoot $timestamp
        Write-Host "Backing up $AppRoot to $backupPath"
        New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
        Copy-Item -Path "$AppRoot\*" -Destination $backupPath -Recurse -Force -ErrorAction SilentlyContinue

        Write-Host "Cleaning $AppRoot"
        Get-ChildItem -Path $AppRoot -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Before-install complete"
    return 0
}

$exitCode = Invoke-WithDeploymentLock { Invoke-Deployment }
exit $exitCode
