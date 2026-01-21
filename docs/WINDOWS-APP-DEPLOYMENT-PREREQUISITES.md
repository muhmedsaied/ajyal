# Windows Application Deployment Prerequisites

## Current Status Summary

| Component | Status |
|-----------|--------|
| Infrastructure | Deployed (ASGs scaled to 0) |
| CodeDeploy Apps | Created (preprod-windows-app, preprod-linux-app) |
| Deployment Bucket | `preprod-ajyal-deployments-946846709937` |
| Client Uploads | 4 ZIP files (missing appspec.yml) |

### Uploaded Applications

| Path | Application | Size |
|------|-------------|------|
| `windows/api/AuthorizationServerCore.zip` | Authorization Server (.NET) | 2 MB |
| `windows/api/EduK12API_LMSIntegration.zip` | LMS Integration API (.NET) | 10.6 MB |
| `windows/integration/APIK12Gateway.zip` | API Gateway (Ocelot) | 1.9 MB |
| `windows/integration/FileMgmtS3.zip` | File Management S3 | 1.6 MB |

---

## Automated CodeDeploy Bundling (Preferred)

Raw client ZIPs no longer need `appspec.yml` or `scripts/`. A Lambda now repackages
uploads into CodeDeploy-ready bundles and can trigger deployments automatically.

**Flow:**
- Client uploads raw ZIPs to `windows/api/` or `windows/integration/`
- Bundler writes new ZIPs to:
  - `codedeploy/windows/api/`
  - `codedeploy/windows/integration/`
- If auto-deploy is enabled, CodeDeploy runs for the matching deployment group

**Configured in:** `environments/preprod/05-cicd/variables.tf`
- `enable_codedeploy_bundler`
- `codedeploy_bundler_auto_deploy`
- `codedeploy_bundler_api_allowed_names` (glob patterns)
- `codedeploy_bundler_integration_allowed_names` (glob patterns)

## Prerequisites for Windows Servers

### 1. Base AMI Requirements (Already Configured)

The infrastructure uses **Windows Server 2025** AMI with:
- CodeDeploy Agent (auto-installed via user-data)
- CloudWatch Agent (auto-installed via user-data)
- SSM Agent (pre-installed on AWS AMIs)

### 2. Application Prerequisites (Must be installed)

The following must be installed on the Windows servers BEFORE deployment:

| Requirement | Version | Installation |
|-------------|---------|--------------|
| .NET 6 Hosting Bundle | 6.0.x | Required for IIS |
| IIS | Windows Feature | Required |
| ASP.NET Core Module | Included in Hosting Bundle | Required |

### 3. IIS Configuration

Each application requires an IIS Application Pool:

| Application | App Pool Name | CLR Version | Pipeline Mode |
|-------------|---------------|-------------|---------------|
| APIK12Gateway | APIK12Gateway-Pool | No Managed Code | Integrated |
| AuthorizationServerCore | AuthServer-Pool | No Managed Code | Integrated |
| EduK12API_LMSIntegration | LMSIntegration-Pool | No Managed Code | Integrated |
| FileMgmtS3 | FileMgmtS3-Pool | No Managed Code | Integrated |

---

## CodeDeploy Package Structure (Legacy / Manual)

If the bundler is disabled, each ZIP must include the required CodeDeploy structure:

```
package.zip
├── appspec.yml          # REQUIRED - CodeDeploy manifest
├── scripts/             # REQUIRED - Deployment hooks
│   ├── before-install.ps1
│   ├── after-install.ps1
│   └── validate-service.ps1
└── application/         # Application files
    └── [.NET application files]
```

### Required appspec.yml Template

Create this file at the root of each ZIP:

```yaml
version: 0.0
os: windows
files:
  - source: /application
    destination: C:\inetpub\wwwroot\[APP_NAME]
hooks:
  BeforeInstall:
    - location: scripts\before-install.ps1
      timeout: 300
  AfterInstall:
    - location: scripts\after-install.ps1
      timeout: 300
  ValidateService:
    - location: scripts\validate-service.ps1
      timeout: 300
```

---

## Deployment Scripts Templates

### scripts/before-install.ps1

```powershell
# Before Install - Stop IIS Site and prepare for deployment
$AppName = "[APP_NAME]"
$SiteName = "$AppName"
$PoolName = "$AppName-Pool"

Write-Host "Stopping IIS site: $SiteName"
try {
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Stop the application pool
    if (Get-IISAppPool -Name $PoolName -ErrorAction SilentlyContinue) {
        Stop-WebAppPool -Name $PoolName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
    }

    # Stop the website
    if (Get-Website -Name $SiteName -ErrorAction SilentlyContinue) {
        Stop-Website -Name $SiteName -ErrorAction SilentlyContinue
    }

    Write-Host "Successfully stopped $SiteName"
} catch {
    Write-Host "Warning: Could not stop site (may not exist yet): $_"
}

# Backup existing files
$AppPath = "C:\inetpub\wwwroot\$AppName"
$BackupPath = "C:\Backups\$AppName-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
if (Test-Path $AppPath) {
    Write-Host "Backing up existing files to $BackupPath"
    New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
    Copy-Item -Path "$AppPath\*" -Destination $BackupPath -Recurse -Force
}

Write-Host "Before-install complete"
exit 0
```

### scripts/after-install.ps1

```powershell
# After Install - Configure and Start IIS Site
$AppName = "[APP_NAME]"
$SiteName = "$AppName"
$PoolName = "$AppName-Pool"
$AppPath = "C:\inetpub\wwwroot\$AppName"
$Port = [PORT]  # 80, 5000, etc.

Write-Host "Configuring IIS for $AppName"
Import-Module WebAdministration

# Create Application Pool if not exists
if (-not (Get-IISAppPool -Name $PoolName -ErrorAction SilentlyContinue)) {
    Write-Host "Creating Application Pool: $PoolName"
    New-WebAppPool -Name $PoolName
    Set-ItemProperty "IIS:\AppPools\$PoolName" -Name managedRuntimeVersion -Value ""
    Set-ItemProperty "IIS:\AppPools\$PoolName" -Name managedPipelineMode -Value "Integrated"
}

# Create Website if not exists
if (-not (Get-Website -Name $SiteName -ErrorAction SilentlyContinue)) {
    Write-Host "Creating Website: $SiteName on port $Port"
    New-Website -Name $SiteName -PhysicalPath $AppPath -ApplicationPool $PoolName -Port $Port
} else {
    # Update physical path
    Set-ItemProperty "IIS:\Sites\$SiteName" -Name physicalPath -Value $AppPath
}

# Start Application Pool and Website
Write-Host "Starting Application Pool: $PoolName"
Start-WebAppPool -Name $PoolName

Write-Host "Starting Website: $SiteName"
Start-Website -Name $SiteName

Write-Host "After-install complete"
exit 0
```

### scripts/validate-service.ps1

```powershell
# Validate Service - Check if application is responding
$AppName = "[APP_NAME]"
$HealthEndpoint = "http://localhost:[PORT]/health"
$MaxRetries = 10
$RetryDelay = 5

Write-Host "Validating $AppName health endpoint: $HealthEndpoint"

for ($i = 1; $i -le $MaxRetries; $i++) {
    try {
        $response = Invoke-WebRequest -Uri $HealthEndpoint -UseBasicParsing -TimeoutSec 10
        if ($response.StatusCode -eq 200) {
            Write-Host "Health check passed on attempt $i"
            exit 0
        }
    } catch {
        Write-Host "Attempt $i failed: $_"
        if ($i -lt $MaxRetries) {
            Write-Host "Retrying in $RetryDelay seconds..."
            Start-Sleep -Seconds $RetryDelay
        }
    }
}

Write-Host "Health check failed after $MaxRetries attempts"
exit 1
```

---

## Step-by-Step Deployment Process

### Step 1: Prepare Deployment Packages (Legacy)

Skip this step if the bundler is enabled. Raw ZIP uploads are repackaged automatically.

Client must repackage each application with:

```bash
# Example structure for APIK12Gateway
mkdir -p package/application
mkdir -p package/scripts

# Copy application files
cp -r APIK12Gateway/* package/application/

# Add appspec.yml (customize for each app)
# Add scripts (customize for each app)

# Create ZIP
cd package && zip -r ../APIK12Gateway-deploy.zip .
```

### Step 2: Scale Up Infrastructure

```bash
# Scale up API servers (for API applications)
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name preprod-ajyal-api-asg \
  --desired-capacity 1 \
  --region eu-west-1

# Scale up Integration servers (for integration apps)
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name preprod-ajyal-integration-asg \
  --desired-capacity 1 \
  --region eu-west-1

# Wait for instances to be healthy
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names preprod-ajyal-api-asg \
  --query "AutoScalingGroups[0].Instances[].LifecycleState" \
  --region eu-west-1
```

### Step 3: Install Prerequisites on Servers (One-time)

Connect via SSM Session Manager and run:

```powershell
# Install IIS
Install-WindowsFeature -Name Web-Server -IncludeManagementTools

# Download and install .NET 6 Hosting Bundle
$dotnetUrl = "https://download.visualstudio.microsoft.com/download/pr/dotnet-6-hosting-bundle/xxx/dotnet-hosting-6.x.x-win.exe"
Invoke-WebRequest -Uri $dotnetUrl -OutFile "C:\temp\dotnet-hosting.exe"
Start-Process "C:\temp\dotnet-hosting.exe" -ArgumentList "/quiet /install" -Wait

# Restart IIS
iisreset /restart
```

### Step 4: Upload Corrected Deployment Packages (Legacy)

If the bundler is enabled, upload the raw ZIPs to `windows/api/` or `windows/integration/` and skip this step.

```bash
# Upload to S3
aws s3 cp APIK12Gateway-deploy.zip \
  s3://preprod-ajyal-deployments-946846709937/windows/integration/ \
  --region eu-west-1

aws s3 cp AuthorizationServerCore-deploy.zip \
  s3://preprod-ajyal-deployments-946846709937/windows/api/ \
  --region eu-west-1
```

### Step 5: Trigger CodeDeploy Deployment (Legacy)

If `codedeploy_bundler_auto_deploy` is enabled, deployments start automatically after bundling. Otherwise, use the CodeDeploy-ready ZIPs under `codedeploy/windows/...` as the revision source.

```bash
# Deploy to Integration servers
aws deploy create-deployment \
  --application-name preprod-windows-app \
  --deployment-group-name preprod-ajyal-windows-integration-dg \
  --s3-location bucket=preprod-ajyal-deployments-946846709937,key=windows/integration/APIK12Gateway-deploy.zip,bundleType=zip \
  --region eu-west-1

# Deploy to API servers
aws deploy create-deployment \
  --application-name preprod-windows-app \
  --deployment-group-name preprod-ajyal-windows-api-dg \
  --s3-location bucket=preprod-ajyal-deployments-946846709937,key=windows/api/AuthorizationServerCore-deploy.zip,bundleType=zip \
  --region eu-west-1
```

### Step 6: Monitor Deployment

```bash
# List deployments
aws deploy list-deployments \
  --application-name preprod-windows-app \
  --deployment-group-name preprod-ajyal-windows-integration-dg \
  --region eu-west-1

# Get deployment status
aws deploy get-deployment \
  --deployment-id d-XXXXXXXXX \
  --region eu-west-1
```

---

## Quick Reference - Deployment Groups

| Application Type | Deployment Group | Target Instances |
|-----------------|------------------|------------------|
| API | preprod-ajyal-windows-api-dg | Tag: DeploymentGroup=windows-api |
| Integration | preprod-ajyal-windows-integration-dg | Tag: DeploymentGroup=windows-integration |
| App | preprod-ajyal-windows-app-dg | Tag: DeploymentGroup=windows-app |
| Logging | preprod-ajyal-windows-logging-dg | Tag: DeploymentGroup=windows-logging |

---

## Application Configuration (ocelot.json)

The APIK12Gateway requires ocelot.json configuration for routing:

```json
{
  "Routes": [
    {
      "DownstreamPathTemplate": "/EduK12API_LMSIntegration/api/{everything}",
      "DownstreamScheme": "http",
      "DownstreamHostAndPorts": [
        {
          "Host": "internal-api-alb.eu-west-1.elb.amazonaws.com",
          "Port": 80
        }
      ],
      "UpstreamPathTemplate": "/lms/{everything}",
      "UpstreamHttpMethod": ["GET", "POST", "PUT", "DELETE"]
    }
  ],
  "GlobalConfiguration": {
    "BaseUrl": "http://localhost:5000"
  }
}
```

**Note:** Update the `Host` to point to the internal API ALB DNS name after deployment.

---

## Troubleshooting

### CodeDeploy Agent Issues

```powershell
# Check CodeDeploy agent status
Get-Service -Name codedeployagent

# View agent logs
Get-Content "C:\ProgramData\Amazon\CodeDeploy\log\codedeploy-agent-log.txt" -Tail 100

# Restart agent
Restart-Service -Name codedeployagent
```

### IIS Issues

```powershell
# Check IIS sites
Get-Website

# Check application pools
Get-IISAppPool

# View IIS logs
Get-Content "C:\inetpub\logs\LogFiles\W3SVC1\*.log" -Tail 100
```

### Application Logs

```powershell
# View .NET application logs
Get-Content "C:\inetpub\wwwroot\[APP_NAME]\logs\*.log" -Tail 100

# View Windows Event Log
Get-EventLog -LogName Application -Newest 50 -Source "ASP.NET Core Module"
```
