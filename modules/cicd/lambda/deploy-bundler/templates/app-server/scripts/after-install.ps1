# After Install - Configure AjyalApp site
$ErrorActionPreference = "Stop"
$AppRoot = "C:\inetpub\wwwroot\AjyalApp"
$SiteName = "AjyalApp"
$LogsRoot = "C:\AjyalApp\logs"
$BackupRoot = "C:\Backups\AjyalApp"
$Port = 80
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

function Get-AppContentRoot([string]$rootPath) {
    if (-not (Test-Path $rootPath)) {
        return $rootPath
    }

    $rootAspx = Get-ChildItem -Path $rootPath -Filter *.aspx -File -ErrorAction SilentlyContinue
    if ($rootAspx) {
        return $rootPath
    }

    $candidates = @()
    $dirs = Get-ChildItem -Path $rootPath -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $dirs) {
        $found = Get-ChildItem -Path $dir.FullName -Filter *.aspx -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $candidates += $dir.FullName
        }
    }

    if ($candidates.Count -eq 1) {
        return $candidates[0]
    }

    return $rootPath
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

function Ensure-Site([string]$siteName, [string]$physicalPath, [int]$port, [string]$poolName) {
    $siteExists = & $appcmd list site /name:"$siteName" 2>$null
    if (-not $siteExists) {
        Write-Host "Creating Website: $siteName on port $port"
        & $appcmd add site /name:"$siteName" /physicalPath:"$physicalPath" /bindings:http/*:${port}:
    } else {
        Write-Host "Updating Website physical path"
        & $appcmd set vdir "$siteName/" /physicalPath:"$physicalPath"
    }
    & $appcmd set app "$siteName/" /applicationPool:"$poolName"
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

function Update-AppSettingsXml([string]$filePath, [hashtable]$settings) {
    if (-not (Test-Path $filePath)) {
        return
    }

    [xml]$xml = Get-Content -Path $filePath
    if (-not $xml.configuration.appSettings) {
        $appSettingsNode = $xml.CreateElement("appSettings")
        $xml.configuration.AppendChild($appSettingsNode) | Out-Null
    }

    $appSettingsNode = $xml.configuration.appSettings
    foreach ($key in $settings.Keys) {
        $value = $settings[$key]
        if ($null -eq $value -or $value -eq "") {
            continue
        }
        $node = $appSettingsNode.SelectSingleNode("add[@key='$key']")
        if (-not $node) {
            $node = $xml.CreateElement("add")
            $node.SetAttribute("key", $key)
            $node.SetAttribute("value", $value)
            $appSettingsNode.AppendChild($node) | Out-Null
        } else {
            $node.SetAttribute("value", $value)
        }
    }

    $xml.Save($filePath)
}

function Parse-ConnectionString([string]$value) {
    $map = @{}
    foreach ($pair in ($value -split ';')) {
        if (-not $pair) { continue }
        $parts = $pair -split '=', 2
        if ($parts.Count -ne 2) { continue }
        $map[$parts[0].Trim()] = $parts[1]
    }
    return $map
}

function Update-ConnectionNode([xml]$xml, [string]$path, [string]$value) {
    $node = $xml.SelectSingleNode($path)
    if (-not $node) {
        return
    }
    $map = Parse-ConnectionString $value
    $server = $map["Server"]; if (-not $server) { $server = $map["server"] }
    $db = $map["DataBase"]; if (-not $db) { $db = $map["Database"] }
    $uid = $map["uid"]; if (-not $uid) { $uid = $map["UId"] }
    $pwd = $map["pwd"]; if (-not $pwd) { $pwd = $map["Pwd"] }

    if ($server) { ($node.SelectSingleNode("Server")).InnerText = $server }
    if ($db) { ($node.SelectSingleNode("DataBase")).InnerText = $db }
    if ($uid) { ($node.SelectSingleNode("uid")).InnerText = $uid }
    if ($pwd) { ($node.SelectSingleNode("pwd")).InnerText = $pwd }
}

function Update-SystemSettingsXml([string]$filePath, [hashtable]$settings) {
    if (-not (Test-Path $filePath)) {
        return
    }

    [xml]$xml = Get-Content -Path $filePath
    $keyMap = @{
        "LMSEnableTracking" = "EnableTracking"
    }

    foreach ($rawKey in $settings.Keys) {
        $value = $settings[$rawKey]
        if ($null -eq $value -or $value -eq "") {
            continue
        }

        $cleanKey = $rawKey.TrimEnd("*")
        if ($keyMap.ContainsKey($cleanKey)) {
            $cleanKey = $keyMap[$cleanKey]
        }

        if ($cleanKey -eq "PushNotificationSettings") {
            Update-ConnectionNode $xml "//Settings/EduWaveSettings/PushNotificationSettings/ConnectionString" $value
            continue
        }

        if ($cleanKey -eq "EduWaveConnectionString") {
            Update-ConnectionNode $xml "//Settings/EduWaveSettings/EduWaveConnectionString" $value
            continue
        }

        $node = $xml.SelectSingleNode("//$cleanKey")
        if ($node) {
            if ($node.Attributes["Value"]) {
                $node.Attributes["Value"].Value = $value
            } else {
                $node.InnerText = $value
            }
        }
    }

    $xml.Save($filePath)
}

function Update-Resx([string]$filePath, [hashtable]$settings) {
    if (-not (Test-Path $filePath)) {
        return
    }
    [xml]$xml = Get-Content -Path $filePath
    foreach ($key in $settings.Keys) {
        $value = $settings[$key]
        if ($null -eq $value -or $value -eq "") {
            continue
        }
        $node = $xml.SelectSingleNode("//data[@name='$key']/value")
        if ($node) {
            $node.InnerText = $value
        }
    }
    $xml.Save($filePath)
}

function Write-JsonFile([string]$filePath, [string]$content) {
    try {
        $obj = $content | ConvertFrom-Json -ErrorAction Stop
        $obj | ConvertTo-Json -Depth 20 | Out-File -FilePath $filePath -Encoding UTF8
    } catch {
        Write-ConfigFile $filePath $content
    }
}

function Convert-ToHashtable($obj) {
    if ($obj -is [System.Collections.IDictionary]) {
        return $obj
    }
    $table = @{}
    if ($obj -is [pscustomobject]) {
        foreach ($prop in $obj.PSObject.Properties) {
            $table[$prop.Name] = $prop.Value
        }
    }
    return $table
}

function Invoke-Deployment {
    Write-Host "=========================================="
    Write-Host "After Install - AjyalApp"
    Write-Host "=========================================="

    if (-not (Test-Path $appcmd)) {
        Write-Host "ERROR: appcmd.exe not found. IIS may not be installed."
        return 1
    }

    New-Item -ItemType Directory -Path $AppRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $LogsRoot -Force | Out-Null

    $siteRoot = Get-AppContentRoot $AppRoot
    $serviceName = Split-Path -Path $siteRoot -Leaf
    if (-not $serviceName -or $serviceName -eq "AjyalApp") {
        $serviceName = "portal"
    }

    Ensure-AppPool "$SiteName-Pool" "v4.0"
    Ensure-Site $SiteName $siteRoot $Port "$SiteName-Pool"

    # Stop Default Web Site if it conflicts on port 80
    $defaultSite = & $appcmd list site /name:"Default Web Site" 2>$null
    if ($defaultSite) {
        try {
            & $appcmd stop site /site.name:"Default Web Site" 2>$null
        } catch {
        }
    }

    # Set permissions
    $acl = Get-Acl $siteRoot
    $iisUser = New-Object System.Security.Principal.NTAccount("IIS_IUSRS")
    $permission = New-Object System.Security.AccessControl.FileSystemAccessRule($iisUser, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($permission)
    Set-Acl $siteRoot $acl

    if (Test-Path $LogsRoot) {
        $acl = Get-Acl $LogsRoot
        $permission = New-Object System.Security.AccessControl.FileSystemAccessRule($iisUser, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($permission)
        Set-Acl $LogsRoot $acl
    }

    # Get region for SSM
    try {
        $token = Invoke-RestMethod -Uri http://169.254.169.254/latest/api/token -Method PUT -Headers @{"X-aws-ec2-metadata-token-ttl-seconds"="21600"} -TimeoutSec 5
        $region = Invoke-RestMethod -Uri http://169.254.169.254/latest/meta-data/placement/region -Headers @{"X-aws-ec2-metadata-token"=$token} -TimeoutSec 5
    } catch {
        $region = "eu-west-1"
    }

    $portalBase = "/preprod-ajyal/secrets/app-server/portal"
    $webConfigPath = Join-Path $siteRoot "Web.config"
    if (-not (Test-Path $webConfigPath)) {
        $webConfigPath = Join-Path $siteRoot "web.config"
    }

    $webConfigValue = Get-SsmValue "$portalBase/MainApp/web.config" $region
    $appSettingsMap = $null
    if ($webConfigValue) {
        if ($webConfigValue.TrimStart().StartsWith("<")) {
            Write-Host "Overwriting web.config from SSM"
            Write-ConfigFile $webConfigPath $webConfigValue
        } else {
            try {
                $appSettingsMap = Convert-ToHashtable ($webConfigValue | ConvertFrom-Json -ErrorAction Stop)
            } catch {
                $appSettingsMap = $null
            }
            if ($appSettingsMap) {
                Write-Host "Updating appSettings from SSM"
                Update-AppSettingsXml $webConfigPath $appSettingsMap
            }
        }
    }

    $settingsDir = Join-Path $siteRoot "Settings"
    $systemSettingsPath = Join-Path $settingsDir "SystemSettings.xml"
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null

    if ($appSettingsMap) {
        $appSettingsMap["SystemSettingsFile"] = $systemSettingsPath
        if ($appSettingsMap.ContainsKey("ErrorLogFilePath")) {
            $appSettingsMap["ErrorLogFilePath"] = Join-Path $LogsRoot "ErrorLogs.xml"
        }
        if ($appSettingsMap.ContainsKey("ProfilerLogFilePath")) {
            $appSettingsMap["ProfilerLogFilePath"] = Join-Path $LogsRoot "ProfilerLogFilePath.xml"
        }
    }

    if (-not (Test-Path $systemSettingsPath)) {
        $bundleSettings = Join-Path $AppRoot "SystemSettings.xml"
        if (Test-Path $bundleSettings) {
            Copy-Item -Path $bundleSettings -Destination $systemSettingsPath -Force
        }
    }

    $systemSettingsValue = Get-SsmValue "$portalBase/Settings/SystemSettings.xml" $region
    if ($systemSettingsValue) {
        if ($systemSettingsValue.TrimStart().StartsWith("<")) {
            Write-Host "Overwriting SystemSettings.xml from SSM"
            Write-ConfigFile $systemSettingsPath $systemSettingsValue
        } else {
            Write-Host "Updating SystemSettings.xml from SSM"
            try {
                $settingsMap = Convert-ToHashtable ($systemSettingsValue | ConvertFrom-Json -ErrorAction Stop)
                if ($settingsMap) {
                    Update-SystemSettingsXml $systemSettingsPath $settingsMap
                }
            } catch {
                Write-Host "SystemSettings value is not JSON, writing raw"
                Write-ConfigFile $systemSettingsPath $systemSettingsValue
            }
        }
    } elseif (-not (Test-Path $systemSettingsPath)) {
        $bundleSettings = Join-Path $AppRoot "SystemSettings.xml"
        if (Test-Path $bundleSettings) {
            Copy-Item -Path $bundleSettings -Destination $systemSettingsPath -Force
        }
    }

    if (Test-Path $webConfigPath) {
        Update-AppSettingsXml $webConfigPath @{ "SystemSettingsFile" = $systemSettingsPath }
    }

    $configResxPath = Join-Path $siteRoot "App_GlobalResources\\Configuration.resx"
    $configResxValue = Get-SsmValue "$portalBase/App_GlobalResources/Configuration.resx" $region
    if ($configResxValue) {
        try {
            $configMap = Convert-ToHashtable ($configResxValue | ConvertFrom-Json -ErrorAction Stop)
            if ($configMap) {
                Write-Host "Updating Configuration.resx from SSM"
                Update-Resx $configResxPath $configMap
            } else {
                Write-ConfigFile $configResxPath $configResxValue
            }
        } catch {
            Write-ConfigFile $configResxPath $configResxValue
        }
    }

    $publishedPath = Join-Path $siteRoot "PublishedServices.json"
    $publishedValue = Get-SsmValue "$portalBase/PublishedServices.json" $region
    if ($publishedValue) {
        Write-Host "Writing PublishedServices.json from SSM"
        Write-JsonFile $publishedPath $publishedValue
    }

    # Remove deployment docs from web root
    Get-ChildItem -Path $AppRoot -Filter *.xlsx -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $AppRoot -Filter *.docx -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    Write-Host "Starting Website: $SiteName"
    & $appcmd start site /site.name:"$SiteName" 2>$null
    Start-Sleep -Seconds 5

    Write-Host "After-install complete"
    return 0
}

$exitCode = Invoke-WithDeploymentLock { Invoke-Deployment }
exit $exitCode
