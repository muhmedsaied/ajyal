# Validate Service - Check AjyalApp response
$ErrorActionPreference = "Continue"
$SiteName = "AjyalApp"
$Port = 80
$MaxRetries = 6
$RetryDelay = 5

Write-Host "=========================================="
Write-Host "Validate Service - AjyalApp"
Write-Host "=========================================="

$appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
if (Test-Path $appcmd) {
    $siteInfo = & $appcmd list site /name:"$SiteName" 2>$null
    if ($siteInfo -and $siteInfo -notmatch "state:Started") {
        & $appcmd start site /site.name:"$SiteName" 2>$null
        Start-Sleep -Seconds 5
    }
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

$endpoints = @(
    "http://localhost:$Port/health",
    "http://localhost:$Port/api/health",
    "http://localhost:$Port/"
)

$success = $false
foreach ($endpoint in $endpoints) {
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Write-Host "Attempt $i of ${MaxRetries}: $endpoint"
            $response = Invoke-WebRequest -Uri $endpoint -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            if (Is-AllowedStatus $response.StatusCode) {
                Write-Host "SUCCESS: $endpoint returned $($response.StatusCode)"
                $success = $true
                break
            }
        } catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            if ($statusCode -and (Is-AllowedStatus $statusCode)) {
                Write-Host "SUCCESS: Endpoint returned status $statusCode"
                $success = $true
                break
            }

            Write-Host "Attempt $i failed: Status=$statusCode Error=$($_.Exception.Message)"
            if ($i -lt $MaxRetries) {
                Start-Sleep -Seconds $RetryDelay
            }
        }
    }

    if ($success) {
        break
    }
}

if ($success) {
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

Write-Host ""
Write-Host "Diagnostic Information:"
Write-Host "----------------------"
Write-Host "Ports listening:"
netstat -an | Select-String ":$Port"

Write-Host ""
Write-Host "Recent Application Events:"
Get-EventLog -LogName Application -Newest 10 -EntryType Error -ErrorAction SilentlyContinue | Format-Table TimeGenerated, Source, Message -AutoSize

exit 1
