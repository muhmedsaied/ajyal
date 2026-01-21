# Preprod Windows Deployment Runbook (API + Integration)

## Current Setup

- Upload bucket: `preprod-ajyal-deployments-946846709937`
- Upload prefixes:
  - `windows/api/` (API services)
  - `windows/integration/` (Integration services)
- Bundler Lambda: `preprod-ajyal-codedeploy-bundler`
  - Repackages raw client ZIPs into CodeDeploy bundles.
  - Writes output bundles to:
    - `codedeploy/windows/api/`
    - `codedeploy/windows/integration/`
  - Creates per-service CodeDeploy app + deployment group on first run.
  - Seeds SSM parameters from config files only if the parameter does not exist.
- CodeDeploy app naming:
  - API: `preprod-ajyal-api-<ServiceName>`
  - Integration: `preprod-ajyal-integration-<ServiceName>`
  - Deployment group: `<app-name>-dg`
- ASGs:
  - API: `preprod-ajyal-api-asg`
  - Integration: `preprod-ajyal-integration-asg`
- Target group (API): `preprod-ajyal-api-tg`
- Current golden AMI: `ami-09b0bf2ddf943f4d6` (2026-01-21, includes IIS, ASP.NET 4.5, URL Rewrite, WebSockets)

Note: `preprod-ajyal-api-gateway` is a legacy app from earlier runs; it is not part of the per-service flow.

## Golden AMI Prerequisites

Golden AMI should include the following so instances do not download tools at boot:

- Windows Server 2025
- IIS + ASP.NET features
- .NET Hosting Bundles (6/8/9 as needed by services)
- WebSocket Protocol + URL Rewrite
- CodeDeploy agent
- SSM agent (already on AWS Windows AMIs)
- CloudWatch agent

When using a golden AMI:
- `use_custom_windows_ami = true`
- `custom_windows_ami_id = <ami-id>`
- `install_prerequisites_on_launch = false`

## Secrets and Configuration

SSM Parameter Store (SecureString):

- API base path: `/preprod-ajyal/secrets/api-services/<ServiceName>/`
  - `appsettings.json`
  - `web.config`
  - `ocelot.json`
  - `SystemSettingsSqlDbAccess.xml` (DBAccessSqlAPI only)

- Integration base path: `/preprod-ajyal/secrets/integration-services/<ServiceName>/`
  - `appsettings.json`

The bundler seeds parameters from ZIP config files only if missing. It never overwrites existing SSM values.

### Portal Variables (Excel)

The portal variables file `EduWaveLMSPortal_Variables.xlsx` is uploaded to:

- `s3://preprod-ajyal-deployments-946846709937/config/variables/EduWaveLMSPortal_Variables.xlsx`

SSM parameters derived from the Excel:

- `/preprod-ajyal/secrets/app-server/portal/MainApp/web.config`
- `/preprod-ajyal/secrets/app-server/portal/Settings/SystemSettings.xml`
- `/preprod-ajyal/secrets/app-server/portal/App_GlobalResources/Configuration.resx`
- `/preprod-ajyal/secrets/app-server/portal/PublishedServices.json`

Each parameter stores a JSON object of key/value pairs from the corresponding sheet.

Secrets Manager (RDP admin password):

- Secret should contain JSON with `username` and `password`:
  - `{ "username": "Administrator", "password": "<password>" }`
- User-data sets the local admin password from this secret on boot.

## Deployment Flow

1. Client uploads a raw ZIP to `windows/api/` or `windows/integration/`.
2. Bundler Lambda creates a CodeDeploy bundle and uploads it to `codedeploy/windows/...`.
3. CodeDeploy deployment starts automatically for the matching app.
4. Instance lifecycle:
   - BeforeInstall: backup + stop pools/sites
   - Install: copy files into `C:\inetpub\wwwroot\AjyalAPI` or `C:\inetpub\wwwroot\AjyalIntegration`
   - AfterInstall: configure IIS, sync SSM config, start pools/sites
   - ValidateService: health checks (`/health`, `/api/health`, `/`), accepts 200-399 or 403/404

## Deploy a New Service or Update an Existing One

1. Upload ZIP to the correct prefix in S3:
   - `s3://preprod-ajyal-deployments-946846709937/windows/api/<Service>.zip`
   - `s3://preprod-ajyal-deployments-946846709937/windows/integration/<Service>.zip`
2. If the service doc requests secrets/configs, create SecureString parameters under the service base path.
3. If needed, invoke bundler directly:

```sh
aws lambda invoke \
  --function-name preprod-ajyal-codedeploy-bundler \
  --cli-binary-format raw-in-base64-out \
  --payload '{"Records":[{"s3":{"bucket":{"name":"preprod-ajyal-deployments-946846709937"},"object":{"key":"windows/api/<Service>.zip"}}}]}' \
  /tmp/bundler.json
```

4. Monitor CodeDeploy:

```sh
aws deploy list-deployments \
  --application-name preprod-ajyal-api-<ServiceName> \
  --deployment-group-name preprod-ajyal-api-<ServiceName>-dg
```

## Validation Checklist

- CodeDeploy deployment status is `Succeeded` for each service.
- New instances appear under each deployment group and complete deployment.
- API target group health is `healthy` for all instances.
- IIS apps exist under:
  - `C:\inetpub\wwwroot\AjyalAPI\<Service>`
  - `C:\inetpub\wwwroot\AjyalIntegration\<Service>`
- Health endpoints respond (200-399 or 403/404):
  - `http://<instance>/health`
  - `http://<instance>/api/health`
  - `http://<instance>/<service>/health`

## Zip Settings Check (Current Findings)

- `windows/integration/EduK12API_LMSIntegration.zip`:
  - `appsettings.json` includes commented lines and is invalid JSON.
  - Cleaned JSON is stored in:
    - `/preprod-ajyal/secrets/integration-services/EduK12API_LMSIntegration/appsettings.json`
    - `/preprod-ajyal/secrets/integration-services/EduK12API_LMSIntegration/appsettings`
  - Deployments now succeed after syncing from SSM.
- `windows/integration/FileMgmtS3.zip`:
  - `appsettings.json` is valid JSON.

Action: keep SSM values valid JSON. If the ZIP contains comments, strip them before writing to SSM.

## RDP Access Notes (Golden AMI)

If RDP works on older instances but fails on new instances from the golden AMI:

- The `Administrator` password on the AMI may be older than the new instance launch time.
- The AMI can carry EC2Launch user-data state (`C:\\ProgramData\\Amazon\\EC2Launch\\state\\.run-once`),
  causing user-data to skip and never reset the password from Secrets Manager.

Recommended fix before creating a new AMI:

1. On the AMI source instance, delete EC2Launch state:
   - `Remove-Item -Path "C:\\ProgramData\\Amazon\\EC2Launch\\state\\*" -Force`
2. Reboot the instance and verify user-data runs on boot.
3. Create a new AMI from this instance and update `custom_windows_ami_id`.

Optional (immediate fix on running instances):
- Use SSM to set the `Administrator` password from the Secrets Manager secret
  `preprod-ajyal/windows/admin-password`.

## Scale Down/Up Test

1. Scale desired capacity down to 1, wait for termination.
2. Scale desired capacity back to 2, wait for a new instance.
3. Confirm:
   - New instance registers in target group
   - CodeDeploy auto-deploys latest revision to the new instance
   - Health checks pass

Example commands:

```sh
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name preprod-ajyal-api-asg \
  --desired-capacity 1

aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name preprod-ajyal-api-asg \
  --desired-capacity 2
```

## Latest Validation Notes

- **2026-01-21**: Created new Golden AMI `ami-09b0bf2ddf943f4d6` with all prerequisites:
  - Windows Server 2025
  - IIS with ASP.NET 4.5
  - URL Rewrite Module 2.1
  - WebSockets feature
  - CodeDeploy agent
  - No sites/pools pre-configured (clean state)
- Previous AMI `ami-03247397a546e1ff5` was missing URL Rewrite and WebSockets on some servers.
- Latest CodeDeploy deployments for all API and integration apps are `Succeeded`.
- API target group reports all targets `healthy`.

## Troubleshooting

- CodeDeploy logs:
  - `C:\ProgramData\Amazon\CodeDeploy\deployment-logs\codedeploy-agent-deployments.log`
- If IIS changes fail with `hresult:80070020`, it indicates overlapping deploys.
  - The deployment scripts now use a global mutex and longer hook timeouts to serialize IIS updates.
- If secrets are missing:
  - Create SSM parameters under the service path using `SecureString`.
