# Validate Service - Check if deployed applications are responding
$ErrorActionPreference = "Continue"
$AppRoot = "C:\inetpub\wwwroot\AjyalAPI"
$SiteName = "AjyalAPI"
$Port = 80
$MaxRetries = 12
$RetryDelay = 10

$aliasMap = @{
    "AuthorizationServerCore" = "ITG_AuthorizationServerCode"
    "EduWaveAssessment.API"   = "DashBoardAPI"
    "WebSocketsWebAPI"        = "WebSocketWebAPI"
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

function Get-DeploymentServices([string]$bundleAppPath) {
    $services = @()
    if (-not $bundleAppPath -or -not (Test-Path $bundleAppPath)) {
        return $services
    }

    $topDirs = Get-ChildItem -Path $bundleAppPath -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $topDirs) {
        if ($dir.Name -eq "WebSocketFullFiles") {
            $subDirs = Get-ChildItem -Path $dir.FullName -Directory -ErrorAction SilentlyContinue
            foreach ($sub in $subDirs) {
                $services += $sub.Name
            }
        } else {
            $services += $dir.Name
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

function Is-AllowedStatus([int]$code) {
    if ($code -ge 200 -and $code -lt 400) {
        return $true
    }
    if ($code -eq 403 -or $code -eq 404) {
        return $true
    }
    return $false
}

Write-Host "=========================================="
Write-Host "Validate Service - AjyalAPI apps"
Write-Host "=========================================="

$appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
if (Test-Path $appcmd) {
    $siteInfo = & $appcmd list site /name:"$SiteName" 2>$null
    if ($siteInfo -and $siteInfo -notmatch "state:Started") {
        & $appcmd start site /site.name:"$SiteName" 2>$null
        Start-Sleep -Seconds 5
    }
}

$skipDirs = @("logs")
$bundleAppPath = Get-BundleAppPath
$bundleServices = Get-DeploymentServices $bundleAppPath
$aliases = @()
if ($bundleServices -and $bundleServices.Count -gt 0) {
    $aliases = $bundleServices | ForEach-Object { Get-AppAlias $_ } | Sort-Object -Unique
} else {
    $serviceDirs = Get-ServiceDirs $AppRoot $skipDirs
    if ($serviceDirs -and $serviceDirs.Count -gt 0) {
        $aliases = $serviceDirs | ForEach-Object { Get-AppAlias $_.Name } | Sort-Object -Unique
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
                    Write-Host "SUCCESS: $endpoint returned status $statusCode"
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
