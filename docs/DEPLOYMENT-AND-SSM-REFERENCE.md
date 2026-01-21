# Ajyal LMS - Deployment & SSM Parameter Reference

## Table of Contents
1. [Deployment Flow](#deployment-flow)
2. [SSM Parameters Reference](#ssm-parameters-reference)
3. [CloudWatch Configuration](#cloudwatch-configuration)
4. [Service Configuration Details](#service-configuration-details)

---

## Deployment Flow

### Overview
The deployment process uses AWS CodeDeploy with a Lambda-based bundler that automatically processes uploaded packages and deploys them to the appropriate server groups.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           DEPLOYMENT FLOW                                        │
└─────────────────────────────────────────────────────────────────────────────────┘

  ┌──────────┐     ┌─────────────────┐     ┌──────────────────┐     ┌────────────┐
  │  User    │────▶│  S3 Bucket      │────▶│  Lambda Bundler  │────▶│ CodeDeploy │
  │  Upload  │     │  (Source)       │     │  (Triggered)     │     │            │
  └──────────┘     └─────────────────┘     └──────────────────┘     └────────────┘
                          │                        │                       │
                          │                        │                       │
                          ▼                        ▼                       ▼
                   ┌─────────────┐         ┌─────────────┐         ┌─────────────┐
                   │ windows/    │         │ codedeploy/ │         │ EC2 ASG     │
                   │ ├── api/    │         │ windows/    │         │ Instances   │
                   │ ├── app/    │         │ ├── api/    │         │             │
                   │ └── integ/  │         │ └── ...     │         │             │
                   └─────────────┘         └─────────────┘         └─────────────┘
```

### Step-by-Step Process

#### Step 1: User Uploads Package
User uploads a ZIP file to the S3 deployment bucket:
```
s3://preprod-ajyal-deployments-946846709937/windows/<server-type>/<AppName>.zip
```

| Server Type | S3 Path | Target ASG |
|-------------|---------|------------|
| API Server | `windows/api/` | preprod-ajyal-api-asg |
| App Server | `windows/app/` | preprod-ajyal-app-asg |
| Integration Server | `windows/integration/` | preprod-ajyal-integration-asg |
| Logging Server | `windows/logging/` | preprod-ajyal-logging-asg |

**Example:**
```bash
aws s3 cp MyApp.zip s3://preprod-ajyal-deployments-946846709937/windows/api/MyApp.zip
```

#### Step 2: Lambda Bundler Triggered
S3 event triggers the Lambda bundler function which:

1. **Downloads** the source ZIP
2. **Extracts** contents
3. **Adds CodeDeploy scripts** (appspec.yml, before-install.ps1, after-install.ps1, validate-service.ps1)
4. **Seeds SSM parameters** (if config files exist and SSM param doesn't)
5. **Creates bundled package** at `codedeploy/windows/<server-type>/<AppName>-deploy.zip`
6. **Creates/Updates CodeDeploy application** (`preprod-ajyal-<server-type>-<AppName>`)
7. **Creates/Updates deployment group** with ASG attachment
8. **Triggers deployment** automatically

#### Step 3: CodeDeploy Executes on EC2

```
┌─────────────────────────────────────────────────────────────────┐
│                    CodeDeploy Lifecycle                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. BeforeInstall (before-install.ps1)                          │
│     ├── Stop IIS App Pool                                        │
│     ├── Backup existing files                                    │
│     └── Clean deployment directory                               │
│                                                                  │
│  2. Install (automatic)                                          │
│     └── Copy files from bundle to target directory               │
│                                                                  │
│  3. AfterInstall (after-install.ps1)                            │
│     ├── Create/Configure IIS App Pool                            │
│     ├── Create/Configure IIS Application                         │
│     ├── Fetch config from SSM Parameter Store                    │
│     │   ├── appsettings.json (for .NET Core)                    │
│     │   ├── web.config (for .NET Framework)                     │
│     │   └── ocelot.json (for API Gateway)                       │
│     ├── Set folder permissions                                   │
│     └── Start IIS App Pool and Site                             │
│                                                                  │
│  4. ValidateService (validate-service.ps1)                      │
│     └── HTTP health check on port 80                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

#### Step 4: Configuration from SSM
During AfterInstall, the script fetches configuration from SSM:

```powershell
# For .NET Core apps (appsettings.json)
/preprod-ajyal/secrets/<server-type>-services/<AppName>/appsettings.json

# For .NET Framework apps (web.config)
/preprod-ajyal/secrets/<server-type>-services/<AppName>/web.config

# For API Gateway (ocelot.json)
/preprod-ajyal/secrets/<server-type>-services/<AppName>/ocelot.json
```

### Deployment Commands

**Manual Deployment Trigger:**
```bash
# Trigger deployment for existing package
aws deploy create-deployment \
  --application-name "preprod-ajyal-api-<AppName>" \
  --deployment-group-name "preprod-ajyal-api-<AppName>-dg" \
  --revision "revisionType=S3,s3Location={bucket=preprod-ajyal-deployments-946846709937,key=codedeploy/windows/api/<AppName>-deploy.zip,bundleType=zip}" \
  --description "Manual deployment"
```

**Check Deployment Status:**
```bash
aws deploy get-deployment --deployment-id <deployment-id> \
  --query 'deploymentInfo.{status:status,completeTime:completeTime}'
```

---

## SSM Parameters Reference

### CloudWatch Agent Configuration

| Parameter | Type | Description |
|-----------|------|-------------|
| `/preprod-ajyal/cloudwatch/windows-api-server` | String | CloudWatch Agent config for API servers |
| `/preprod-ajyal/cloudwatch/windows-app-server` | String | CloudWatch Agent config for App servers |
| `/preprod-ajyal/cloudwatch/windows-integration-server` | String | CloudWatch Agent config for Integration servers |
| `/preprod-ajyal/cloudwatch/windows-logging-server` | String | CloudWatch Agent config for Logging servers |
| `/preprod-ajyal/cloudwatch/windows-default` | String | Default CloudWatch Agent config |

### API Server Services

| Parameter | Type | Service | Description |
|-----------|------|---------|-------------|
| `/preprod-ajyal/secrets/api-services/APIK12Gateway/appsettings.json` | SecureString | APIK12Gateway | App settings for API Gateway |
| `/preprod-ajyal/secrets/api-services/APIK12Gateway/ocelot.json` | SecureString | APIK12Gateway | Ocelot routing configuration |
| `/preprod-ajyal/secrets/api-services/AuthorizationServerCore/appsettings.json` | SecureString | AuthorizationServerCore | Auth server settings |
| `/preprod-ajyal/secrets/api-services/DBAccessSqlAPI/SystemSettingsSqlDbAccess.xml` | SecureString | DBAccessSqlAPI | DB access settings XML |
| `/preprod-ajyal/secrets/api-services/EduWaveAssessment.API/appsettings.json` | SecureString | EduWaveAssessment.API | Dashboard API settings |
| `/preprod-ajyal/secrets/api-services/ITG_RealTime/web.config` | SecureString | ITG_RealTime | RealTime SignalR web.config |
| `/preprod-ajyal/secrets/api-services/RealTimePresentation/web.config` | SecureString | RealTimePresentation | RealTime Presentation web.config |
| `/preprod-ajyal/secrets/api-services/MicrosoftEduSession/appsettings.json` | SecureString | MicrosoftEduSession | Microsoft Edu Session settings |
| `/preprod-ajyal/secrets/api-services/MicWebSocket/web.config` | SecureString | MicWebSocket | WebSocket handler web.config |
| `/preprod-ajyal/secrets/api-services/WebSocketsWebAPI/web.config` | SecureString | WebSocketsWebAPI | WebSocket API web.config |

### Integration Server Services

| Parameter | Type | Service | Description |
|-----------|------|---------|-------------|
| `/preprod-ajyal/secrets/integration-services/FileMgmtS3/appsettings.json` | SecureString | FileMgmtS3 | File management S3 settings |
| `/preprod-ajyal/secrets/integration-services/EduK12API_LMSIntegration/appsettings.json` | SecureString | EduK12API_LMSIntegration | LMS Integration API settings |

### App Server Configuration

| Parameter | Type | Description |
|-----------|------|-------------|
| `/preprod-ajyal/secrets/app-server/portal/MainApp/web.config` | SecureString | Main portal web.config |
| `/preprod-ajyal/secrets/app-server/portal/Settings/SystemSettings.xml` | SecureString | System settings XML |
| `/preprod-ajyal/secrets/app-server/portal/PublishedServices.json` | SecureString | Published services configuration |
| `/preprod-ajyal/secrets/app-server/portal/App_GlobalResources/Configuration.resx` | SecureString | Global resources configuration |

---

## CloudWatch Configuration

### Log Groups

| Log Group | Server | Description | Retention |
|-----------|--------|-------------|-----------|
| `/preprod-ajyal/windows/api-server/iis` | API | IIS access logs | 30 days |
| `/preprod-ajyal/windows/api-server/api-logs` | API | Application *.log files | 30 days |
| `/preprod-ajyal/windows/api-server/api-logs-xml` | API | Application *.xml files | 30 days |
| `/preprod-ajyal/windows/api-server/application` | API | Windows Application events | 30 days |
| `/preprod-ajyal/windows/api-server/system` | API | Windows System events | 30 days |
| `/preprod-ajyal/windows/app-server/iis` | App | IIS access logs | 30 days |
| `/preprod-ajyal/windows/app-server/application-logs` | App | Application *.log files | 30 days |
| `/preprod-ajyal/windows/app-server/application-logs-xml` | App | Application *.xml files | 30 days |
| `/preprod-ajyal/windows/integration-server/iis` | Integration | IIS access logs | 30 days |
| `/preprod-ajyal/windows/integration-server/integration-logs` | Integration | Application *.log files | 30 days |
| `/preprod-ajyal/windows/integration-server/integration-logs-xml` | Integration | Application *.xml files | 30 days |

### Log File Paths Collected

**API Server:**
- `C:\inetpub\logs\LogFiles\W3SVC*\*.log` - IIS logs
- `C:\AjyalAPI\logs\*.log` - Application logs
- `C:\AjyalAPI\logs\*.xml` - XML error logs
- `C:\inetpub\wwwroot\AjyalAPI\**\logs\*.log` - Per-app logs

**App Server:**
- `C:\inetpub\logs\LogFiles\W3SVC*\*.log` - IIS logs
- `C:\AjyalApp\logs\*.log` - Application logs
- `C:\AjyalApp\logs\*.xml` - XML error logs

**Integration Server:**
- `C:\inetpub\logs\LogFiles\W3SVC*\*.log` - IIS logs
- `C:\AjyalIntegration\logs\*.log` - Application logs
- `C:\AjyalIntegration\logs\*.xml` - XML error logs

---

## Service Configuration Details

### API Server Services

| Service | IIS Path | App Pool | CLR Version | Pipeline |
|---------|----------|----------|-------------|----------|
| APIK12Gateway | /APIK12Gateway | APIK12Gateway-Pool | No Managed Code | Integrated |
| AuthorizationServerCore | /ITG_AuthorizationServerCode | AuthorizationServerCore-Pool | No Managed Code | Integrated |
| DBAccessSqlAPI | /DBAccessSqlAPI | DBAccessSqlAPI-Pool | No Managed Code | Integrated |
| EduWaveAssessment.API | /DashBoardAPI | EduWaveAssessment.API-Pool | No Managed Code | Integrated |
| ITG_RealTime | /ITG_RealTime | ITG_RealTime-Pool | v4.0 | Integrated |
| RealTimePresentation | /RealTimePresentation | RealTimePresentation-Pool | v4.0 | Integrated |
| MicrosoftEduSession | /MicrosoftEduSession | MicrosoftEduSession-Pool | No Managed Code | Integrated |
| MicWebSocket | /MicWebSocket | MicWebSocket-Pool | v4.0 | Integrated |
| WebSocketWebAPI | /WebSocketWebAPI | WebSocketWebAPI-Pool | v4.0 | Integrated |

### Integration Server Services

| Service | IIS Path | App Pool | CLR Version | Pipeline |
|---------|----------|----------|-------------|----------|
| FileMgmtS3 | /FileMgmtS3 | FileMgmtS3-Pool | No Managed Code | Integrated |
| EduK12API_LMSIntegration | /EduK12API_LMSIntegration | EduK12API_LMSIntegration-Pool | No Managed Code | Integrated |

### Internal DNS Records

| DNS Name | Target | Purpose |
|----------|--------|---------|
| mssql.lms.internal | RDS MSSQL endpoint | Database connectivity |
| redis.lms.internal | ElastiCache endpoint | Caching |
| rabbitmq.lms.internal | RabbitMQ EC2 | Message queue |
| api.lms.internal | API ALB | Internal API access |
| app.lms.internal | App ALB | Internal app access |
| integration.lms.internal | Integration NLB | Internal integration services |

### Load Balancer Configuration

| ALB | Scheme | Sticky Sessions | Target Group |
|-----|--------|-----------------|--------------|
| preprod-ajyal-api-alb | Internal | **Enabled** (24h) | preprod-ajyal-api-tg |
| preprod-ajyal-app-alb | Internet-facing | Disabled | preprod-ajyal-app-tg |
| preprod-ajyal-botpress-alb | Internet-facing | Disabled | preprod-ajyal-botpress-tg |

> **Note:** Sticky sessions are enabled on API ALB for WebSocket/SignalR support with multiple instances.

---

## Quick Reference Commands

### Upload and Deploy
```bash
# Upload package (triggers automatic deployment)
aws s3 cp MyApp.zip s3://preprod-ajyal-deployments-946846709937/windows/api/MyApp.zip

# Check Lambda bundler logs
aws logs tail /aws/lambda/preprod-ajyal-deploy-bundler --follow

# List recent deployments
aws deploy list-deployments --application-name "preprod-ajyal-api-MyApp" --max-items 5
```

### Update SSM Parameter and Redeploy
```bash
# Update SSM parameter
aws ssm put-parameter \
  --name "/preprod-ajyal/secrets/api-services/MyApp/appsettings.json" \
  --type "SecureString" \
  --value '{"key": "value"}' \
  --overwrite

# Trigger redeployment to apply new config
aws deploy create-deployment \
  --application-name "preprod-ajyal-api-MyApp" \
  --deployment-group-name "preprod-ajyal-api-MyApp-dg" \
  --revision "revisionType=S3,s3Location={bucket=preprod-ajyal-deployments-946846709937,key=codedeploy/windows/api/MyApp-deploy.zip,bundleType=zip}"
```

### Check Service Status on Server
```bash
# Via SSM Run Command
aws ssm send-command \
  --instance-ids "i-xxxxxxxxx" \
  --document-name "AWS-RunPowerShellScript" \
  --parameters 'commands=["Import-Module WebAdministration; Get-WebApplication | Format-Table"]'
```

---

*Last Updated: January 2026*
*Managed by: Slashtec DevOps Team*
