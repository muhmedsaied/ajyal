# Validate Service - Check if application is responding
$ErrorActionPreference = "Continue"
$AppName = "AjyalAPI"
$Port = 80
$MaxRetries = 12
$RetryDelay = 10

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
Write-Host "Validate Service - $AppName"
Write-Host "=========================================="

# Try multiple health check endpoints
$endpoints = @(
    "http://localhost:$Port/health",
    "http://localhost:$Port/api/health",
    "http://localhost:$Port/"
)

# First check if the IIS site is running
Import-Module WebAdministration -ErrorAction SilentlyContinue
$site = Get-Website -Name $AppName -ErrorAction SilentlyContinue
if ($site) {
    Write-Host "Website State: $($site.State)"
    if ($site.State -ne "Started") {
        Write-Host "Attempting to start website..."
        Start-Website -Name $AppName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
    }
}

$pool = Get-IISAppPool -Name "$AppName-Pool" -ErrorAction SilentlyContinue
if ($pool) {
    Write-Host "App Pool State: $($pool.State)"
    if ($pool.State -ne "Started") {
        Write-Host "Attempting to start app pool..."
        Start-WebAppPool -Name "$AppName-Pool" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
    }
}

# Health check loop
$success = $false
foreach ($endpoint in $endpoints) {
    Write-Host ""
    Write-Host "Testing endpoint: $endpoint"

    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Write-Host "Attempt $i of $MaxRetries..."
            $response = Invoke-WebRequest -Uri $endpoint -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop

            if (Is-AllowedStatus $response.StatusCode) {
                Write-Host "SUCCESS: Health check passed with status $($response.StatusCode)"
                $success = $true
                break
            }
        } catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            if ($statusCode -and (Is-AllowedStatus $statusCode)) {
                Write-Host "SUCCESS: Endpoint returned acceptable status $statusCode"
                $success = $true
                break
            }

            Write-Host "Attempt $i failed: Status=$statusCode Error=$($_.Exception.Message)"

            if ($i -lt $MaxRetries) {
                Write-Host "Waiting $RetryDelay seconds before retry..."
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
} else {
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "VALIDATION FAILED"
    Write-Host "=========================================="

    # Output diagnostic information
    Write-Host ""
    Write-Host "Diagnostic Information:"
    Write-Host "----------------------"

    # Check netstat
    Write-Host "Ports listening:"
    netstat -an | Select-String ":$Port"

    # Check event log
    Write-Host ""
    Write-Host "Recent Application Events:"
    Get-EventLog -LogName Application -Newest 10 -EntryType Error -ErrorAction SilentlyContinue | Format-Table TimeGenerated, Source, Message -AutoSize

    exit 1
}
