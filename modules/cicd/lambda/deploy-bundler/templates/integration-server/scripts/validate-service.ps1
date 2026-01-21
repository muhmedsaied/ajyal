# Validate Service - Check if deployed applications are responding
$ErrorActionPreference = "Continue"
$AppRoot = "C:\inetpub\wwwroot\AjyalIntegration"
$SiteName = "AjyalIntegration"
$Port = 80  # Changed from 5000 to 80 for production use
$MaxRetries = 6
$RetryDelay = 5

Write-Host "=========================================="
Write-Host "Validate Service - AjyalIntegration apps"
Write-Host "=========================================="

$appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
if (Test-Path $appcmd) {
    $siteInfo = & $appcmd list site /name:"$SiteName" 2>$null
    if ($siteInfo -and $siteInfo -notmatch "state:Started") {
        & $appcmd start site /site.name:"$SiteName" 2>$null
        Start-Sleep -Seconds 5
    }
}

function Get-ServiceDirs([string]$appRoot, [string[]]$skipNames) {
    $dirs = @()
    $topDirs = Get-ChildItem -Path $appRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $skipNames -notcontains $_.Name }
    foreach ($dir in $topDirs) {
        $dirs += $dir
    }
    return $dirs
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

function Get-DeploymentServices([string]$bundleAppPath) {
    $services = @()
    if (-not $bundleAppPath -or -not (Test-Path $bundleAppPath)) {
        return $services
    }

    $topDirs = Get-ChildItem -Path $bundleAppPath -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $topDirs) {
        if ($dir.Name -eq "S3 Publish") {
            $publishDir = Get-ChildItem -Path $dir.FullName -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($publishDir) {
                $services += "FileMgmtS3"
            }
        } else {
            $services += $dir.Name
        }
    }
    return $services
}

function Is-AllowedStatus([int]$code) {
    if ($code -ge 200 -and $code -lt 400) {
        return $true
    }
    if ($code -eq 403 -or $code -eq 404) {
        return $true
    }
    return $false
}

$skipDirs = @("logs", "S3 Publish")
$bundleAppPath = Get-BundleAppPath
$bundleServices = Get-DeploymentServices $bundleAppPath
$aliases = @()
if ($bundleServices -and $bundleServices.Count -gt 0) {
    $aliases = $bundleServices | Sort-Object -Unique
} else {
    $serviceDirs = Get-ServiceDirs $AppRoot $skipDirs
    if ($serviceDirs -and $serviceDirs.Count -gt 0) {
        $aliases = $serviceDirs | ForEach-Object { $_.Name } | Sort-Object -Unique
    } else {
        $aliases = @("")
    }
}

$failed = @()
foreach ($alias in $aliases) {
    if ($alias) {
        Write-Host ""
        Write-Host "Validating /$alias"
        $baseUrl = "http://localhost:$Port/$alias"
    } else {
        Write-Host ""
        Write-Host "Validating root site"
        $baseUrl = "http://localhost:$Port"
    }

    $endpoints = @(
        "$baseUrl/health",
        "$baseUrl/api/health",
        "$baseUrl/swagger",
        "$baseUrl/"
    )

    $aliasSuccess = $false
    foreach ($endpoint in $endpoints) {
        for ($i = 1; $i -le $MaxRetries; $i++) {
            try {
                Write-Host "Attempt $i of ${MaxRetries}: $endpoint"
                $response = Invoke-WebRequest -Uri $endpoint -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                if (Is-AllowedStatus $response.StatusCode) {
                    Write-Host "SUCCESS: $endpoint returned $($response.StatusCode)"
                    $aliasSuccess = $true
                    break
                }
            } catch {
                $statusCode = $null
                if ($_.Exception.Response) {
                    $statusCode = $_.Exception.Response.StatusCode.value__
                }

                if ($statusCode -and (Is-AllowedStatus $statusCode)) {
                    Write-Host "SUCCESS: Endpoint returned status $statusCode"
                    $aliasSuccess = $true
                    break
                }

                Write-Host "Attempt $i failed: Status=$statusCode Error=$($_.Exception.Message)"
                if ($i -lt $MaxRetries) {
                    Start-Sleep -Seconds $RetryDelay
                }
            }
        }

        if ($aliasSuccess) {
            break
        }
    }

    if (-not $aliasSuccess) {
        $failed += $alias
    }
}

if ($failed.Count -eq 0) {
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "VALIDATION SUCCESSFUL"
    Write-Host "=========================================="
    exit 0
}

Write-Host ""
Write-Host "=========================================="
Write-Host "VALIDATION FAILED"
Write-Host "=========================================="
Write-Host "Failed aliases: $($failed -join ', ')"

Write-Host ""
Write-Host "Diagnostic Information:"
Write-Host "----------------------"
Write-Host "Ports listening:"
netstat -an | Select-String ":$Port"

Write-Host ""
Write-Host "Recent Application Events:"
Get-EventLog -LogName Application -Newest 10 -EntryType Error -ErrorAction SilentlyContinue | Format-Table TimeGenerated, Source, Message -AutoSize

exit 1
