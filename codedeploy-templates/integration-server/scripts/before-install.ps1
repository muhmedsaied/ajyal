# Before Install - Stop IIS Site and prepare for deployment
$ErrorActionPreference = "Continue"
$AppName = "AjyalIntegration"
$SiteName = $AppName
$PoolName = "$AppName-Pool"
$AppPath = "C:\inetpub\wwwroot\$AppName"

Write-Host "=========================================="
Write-Host "Before Install - $AppName"
Write-Host "=========================================="

# Import WebAdministration module
try {
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    Write-Host "WebAdministration module loaded"
} catch {
    Write-Host "WebAdministration module not available - IIS may not be installed"
}

# Stop the application pool if it exists
try {
    $pool = Get-IISAppPool -Name $PoolName -ErrorAction SilentlyContinue
    if ($pool) {
        Write-Host "Stopping Application Pool: $PoolName"
        Stop-WebAppPool -Name $PoolName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        Write-Host "Application Pool stopped"
    } else {
        Write-Host "Application Pool $PoolName does not exist yet"
    }
} catch {
    Write-Host "Warning: Could not stop pool: $_"
}

# Stop the website if it exists
try {
    $site = Get-Website -Name $SiteName -ErrorAction SilentlyContinue
    if ($site) {
        Write-Host "Stopping Website: $SiteName"
        Stop-Website -Name $SiteName -ErrorAction SilentlyContinue
        Write-Host "Website stopped"
    } else {
        Write-Host "Website $SiteName does not exist yet"
    }
} catch {
    Write-Host "Warning: Could not stop site: $_"
}

# Backup existing files
if (Test-Path $AppPath) {
    $BackupPath = "C:\Backups\$AppName-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Write-Host "Backing up existing files to $BackupPath"
    New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
    Copy-Item -Path "$AppPath\*" -Destination $BackupPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Backup complete"

    # Clean the deployment directory
    Write-Host "Cleaning deployment directory"
    Remove-Item -Path "$AppPath\*" -Recurse -Force -ErrorAction SilentlyContinue
}

# Create directories if they don't exist
New-Item -ItemType Directory -Path $AppPath -Force | Out-Null
New-Item -ItemType Directory -Path "C:\Backups" -Force | Out-Null
New-Item -ItemType Directory -Path "C:\AjyalIntegration\logs" -Force | Out-Null

Write-Host "Before-install complete"
exit 0
