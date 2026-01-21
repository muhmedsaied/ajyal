import fnmatch
import json
import logging
import os
import re
import shutil
import tempfile
import zipfile
from urllib.parse import unquote_plus

import boto3
from botocore.exceptions import ClientError

LOGGER = logging.getLogger()
LOGGER.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())

S3_CLIENT = boto3.client("s3")
CODEDEPLOY_CLIENT = boto3.client("codedeploy")
SSM_CLIENT = boto3.client("ssm")

AUTO_DEPLOY = os.getenv("AUTO_DEPLOY", "true").lower() == "true"
CODEDEPLOY_APP_NAME = os.getenv("CODEDEPLOY_APP_NAME", "")
CODEDEPLOY_SERVICE_ROLE_ARN = os.getenv("CODEDEPLOY_SERVICE_ROLE_ARN", "")
KMS_KEY_ARN = os.getenv("KMS_KEY_ARN", "")
DEFAULT_DEPLOYMENT_CONFIG = os.getenv(
    "DEFAULT_DEPLOYMENT_CONFIG", "CodeDeployDefault.AllAtOnce"
)
DEFAULT_AUTO_ROLLBACK = os.getenv("DEFAULT_AUTO_ROLLBACK", "true").lower() == "true"
SSM_KMS_KEY_ID = os.getenv("SSM_KMS_KEY_ID", "")

try:
    PREFIX_CONFIG = json.loads(os.getenv("PREFIX_CONFIG", "{}"))
except json.JSONDecodeError:
    LOGGER.error("Invalid PREFIX_CONFIG JSON. Defaulting to empty config.")
    PREFIX_CONFIG = {}

IGNORE_ENTRIES = {"__MACOSX", ".DS_Store"}
DEFAULT_SSM_FILES = [
    "appsettings.json",
    "web.config",
    "ocelot.json",
    "SystemSettingsSqlDbAccess.xml",
]


def handler(event, _context):
    results = []
    records = event.get("Records", [])

    for record in records:
        bucket = record.get("s3", {}).get("bucket", {}).get("name")
        key = record.get("s3", {}).get("object", {}).get("key")
        if not bucket or not key:
            LOGGER.warning("Skipping record with missing bucket/key: %s", record)
            continue

        key = unquote_plus(key)
        try:
            result = _process_object(bucket, key)
            results.append({"key": key, "status": "ok", "detail": result})
        except Exception as exc:  # pylint: disable=broad-exception-caught
            LOGGER.exception("Failed to process %s", key)
            results.append({"key": key, "status": "error", "detail": str(exc)})

    return {"results": results}


def _process_object(bucket, key):
    if not key.lower().endswith(".zip"):
        LOGGER.info("Skipping non-zip object: %s", key)
        return "skipped: non-zip"

    for cfg in PREFIX_CONFIG.values():
        output_prefix = cfg.get("output_prefix", "")
        if output_prefix and key.startswith(output_prefix):
            LOGGER.info("Skipping already-processed object: %s", key)
            return "skipped: output"

    prefix, config = _match_prefix(key)
    if not config:
        LOGGER.info("No prefix match for object: %s", key)
        return "skipped: no prefix"

    template_name = config.get("template")
    output_prefix = config.get("output_prefix")
    deployment_group = config.get("deployment_group", "")
    allowed_names = config.get("allowed_names", [])
    bundle_all = config.get("bundle_all", False)
    app_name_prefix = config.get("app_name_prefix", "")
    asg_name = config.get("asg_name", "")
    target_group_name = config.get("target_group_name", "")
    deployment_config_name = config.get("deployment_config_name") or DEFAULT_DEPLOYMENT_CONFIG
    auto_rollback = config.get("auto_rollback", DEFAULT_AUTO_ROLLBACK)
    ssm_base_path = config.get("ssm_base_path", "")
    ssm_files = config.get("ssm_files", [])
    seed_ssm = config.get("seed_ssm", True)

    if not template_name or not output_prefix:
        raise ValueError("Missing template or output_prefix in PREFIX_CONFIG")

    base_name = os.path.splitext(os.path.basename(key))[0]
    if allowed_names and not _matches_allowed(base_name, allowed_names):
        LOGGER.info("Skipping %s not in allowed_names patterns", base_name)
        return "skipped: not allowed"

    source_keys = [key]
    if bundle_all:
        source_keys = _list_source_keys(bucket, prefix, output_prefix, allowed_names)
        if not source_keys:
            LOGGER.info("No source zips found under %s", prefix)
            return "skipped: no sources"

    workdir = tempfile.mkdtemp(prefix="codedeploy-bundler-")
    try:
        extracted_root = os.path.join(workdir, "extracted")
        bundle_dir = os.path.join(workdir, "bundle")
        app_dir = os.path.join(bundle_dir, "app")

        os.makedirs(extracted_root, exist_ok=True)
        os.makedirs(app_dir, exist_ok=True)

        for idx, source_key in enumerate(sorted(source_keys)):
            source_zip = os.path.join(workdir, f"source-{idx}.zip")
            extracted_dir = os.path.join(extracted_root, f"source-{idx}")
            os.makedirs(extracted_dir, exist_ok=True)

            LOGGER.info("Downloading s3://%s/%s", bucket, source_key)
            S3_CLIENT.download_file(bucket, source_key, source_zip)

            with zipfile.ZipFile(source_zip, "r") as archive:
                archive.extractall(extracted_dir)

            source_root = _normalize_source_root(extracted_dir)
            _copy_contents(source_root, app_dir)

        _copy_template(template_name, bundle_dir)

        service_dirs = _discover_service_dirs(app_dir)
        if not service_dirs:
            service_dirs = [{"name": base_name, "path": app_dir}]

        if seed_ssm and ssm_base_path:
            files_to_seed = ssm_files if ssm_files else DEFAULT_SSM_FILES
            _seed_ssm_parameters(service_dirs, ssm_base_path, files_to_seed)

        primary_service_name = service_dirs[0]["name"] if len(service_dirs) == 1 else base_name
        codedeploy_service_name = _sanitize_codedeploy_name(primary_service_name)
        codedeploy_app_name = _build_codedeploy_app_name(
            app_name_prefix, codedeploy_service_name
        )
        deployment_group_name = (
            _build_deployment_group_name(codedeploy_app_name)
            if codedeploy_app_name
            else ""
        )

        output_key = f"{output_prefix}{base_name}-deploy.zip"
        output_zip = os.path.join(workdir, "bundle.zip")
        _zip_directory(bundle_dir, output_zip)

        extra_args = None
        if KMS_KEY_ARN:
            extra_args = {
                "ServerSideEncryption": "aws:kms",
                "SSEKMSKeyId": KMS_KEY_ARN,
            }

        LOGGER.info("Uploading bundle to s3://%s/%s", bucket, output_key)
        if extra_args:
            S3_CLIENT.upload_file(output_zip, bucket, output_key, ExtraArgs=extra_args)
        else:
            S3_CLIENT.upload_file(output_zip, bucket, output_key)

        if codedeploy_app_name and deployment_group_name:
            _ensure_codedeploy_app(codedeploy_app_name)
            group_ready = _ensure_deployment_group(
                app_name=codedeploy_app_name,
                deployment_group_name=deployment_group_name,
                service_role_arn=CODEDEPLOY_SERVICE_ROLE_ARN,
                asg_name=asg_name,
                target_group_name=target_group_name,
                deployment_config_name=deployment_config_name,
                auto_rollback=auto_rollback,
            )

            if AUTO_DEPLOY and group_ready:
                LOGGER.info(
                    "Triggering CodeDeploy deployment for %s", deployment_group_name
                )
                CODEDEPLOY_CLIENT.create_deployment(
                    applicationName=codedeploy_app_name,
                    deploymentGroupName=deployment_group_name,
                    revision={
                        "revisionType": "S3",
                        "s3Location": {
                            "bucket": bucket,
                            "key": output_key,
                            "bundleType": "zip",
                        },
                    },
                    description=f"Auto deployment for {key}",
                )
            elif AUTO_DEPLOY:
                LOGGER.warning(
                    "Auto-deploy enabled but deployment group is not ready for %s",
                    codedeploy_app_name,
                )
        elif AUTO_DEPLOY and CODEDEPLOY_APP_NAME and deployment_group:
            LOGGER.info("Triggering CodeDeploy deployment for %s", deployment_group)
            CODEDEPLOY_CLIENT.create_deployment(
                applicationName=CODEDEPLOY_APP_NAME,
                deploymentGroupName=deployment_group,
                revision={
                    "revisionType": "S3",
                    "s3Location": {
                        "bucket": bucket,
                        "key": output_key,
                        "bundleType": "zip",
                    },
                },
                description=f"Auto deployment for {key}",
            )
        elif AUTO_DEPLOY:
            LOGGER.warning(
                "Auto-deploy enabled but missing CodeDeploy app/deployment group configuration"
            )

        return output_key
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def _match_prefix(key):
    matched_prefix = ""
    matched_config = None

    for prefix, config in PREFIX_CONFIG.items():
        if key.startswith(prefix) and len(prefix) > len(matched_prefix):
            matched_prefix = prefix
            matched_config = config

    return matched_prefix, matched_config


def _matches_allowed(base_name, allowed_names):
    for pattern in allowed_names:
        if fnmatch.fnmatchcase(base_name, pattern):
            return True
    return False


def _list_source_keys(bucket, prefix, output_prefix, allowed_names):
    keys = []
    paginator = S3_CLIENT.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for item in page.get("Contents", []):
            key = item.get("Key")
            if not key or not key.lower().endswith(".zip"):
                continue
            if output_prefix and key.startswith(output_prefix):
                continue
            base_name = os.path.splitext(os.path.basename(key))[0]
            if allowed_names and not _matches_allowed(base_name, allowed_names):
                continue
            keys.append(key)
    return keys


def _normalize_source_root(extracted_dir):
    entries = [
        entry
        for entry in os.listdir(extracted_dir)
        if entry not in IGNORE_ENTRIES and not entry.startswith(".")
    ]

    if len(entries) == 1:
        candidate = os.path.join(extracted_dir, entries[0])
        if os.path.isdir(candidate):
            return candidate

    return extracted_dir


def _copy_contents(src, dest):
    os.makedirs(dest, exist_ok=True)

    for name in os.listdir(src):
        if name in IGNORE_ENTRIES or name.startswith("."):
            continue

        source_path = os.path.join(src, name)
        dest_path = os.path.join(dest, name)

        if os.path.isdir(source_path):
            shutil.copytree(source_path, dest_path, dirs_exist_ok=True)
        else:
            shutil.copy2(source_path, dest_path)


def _copy_template(template_name, bundle_dir):
    template_root = os.path.join(os.path.dirname(__file__), "templates", template_name)
    appspec_src = os.path.join(template_root, "appspec.yml")
    scripts_src = os.path.join(template_root, "scripts")

    if not os.path.isfile(appspec_src):
        raise FileNotFoundError(f"Template not found: {appspec_src}")

    shutil.copy2(appspec_src, os.path.join(bundle_dir, "appspec.yml"))

    if os.path.isdir(scripts_src):
        shutil.copytree(scripts_src, os.path.join(bundle_dir, "scripts"))


def _zip_directory(source_dir, output_zip):
    with zipfile.ZipFile(output_zip, "w", zipfile.ZIP_DEFLATED) as archive:
        for root, _dirs, files in os.walk(source_dir):
            for filename in files:
                file_path = os.path.join(root, filename)
                archive_name = os.path.relpath(file_path, source_dir)
                archive.write(file_path, archive_name)


def _sanitize_codedeploy_name(value):
    if not value:
        return ""
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-")
    cleaned = re.sub(r"-{2,}", "-", cleaned)
    return cleaned


def _build_codedeploy_app_name(prefix, service_name):
    if not prefix and not service_name:
        return ""
    if not prefix:
        return service_name
    prefix = prefix.rstrip("-")
    if service_name:
        return f"{prefix}-{service_name}"
    return prefix


def _build_deployment_group_name(app_name):
    if not app_name:
        return ""
    return f"{app_name}-dg"


def _ensure_codedeploy_app(app_name):
    if not app_name:
        return
    try:
        CODEDEPLOY_CLIENT.get_application(applicationName=app_name)
        return
    except ClientError as exc:
        if exc.response["Error"]["Code"] != "ApplicationDoesNotExistException":
            raise
    LOGGER.info("Creating CodeDeploy application: %s", app_name)
    CODEDEPLOY_CLIENT.create_application(
        applicationName=app_name, computePlatform="Server"
    )


def _ensure_deployment_group(
    app_name,
    deployment_group_name,
    service_role_arn,
    asg_name,
    target_group_name,
    deployment_config_name,
    auto_rollback,
):
    if not app_name or not deployment_group_name:
        return False
    if not service_role_arn:
        LOGGER.warning("Missing CodeDeploy service role ARN; skipping group creation.")
        return False
    if not asg_name:
        LOGGER.warning("Missing ASG name for %s; skipping group creation.", app_name)
        return False

    deployment_style = {
        "deploymentType": "IN_PLACE",
        "deploymentOption": "WITH_TRAFFIC_CONTROL" if target_group_name else "WITHOUT_TRAFFIC_CONTROL",
    }
    rollback_events = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
    auto_rollback_config = {
        "enabled": bool(auto_rollback),
        "events": rollback_events if auto_rollback else [],
    }

    load_balancer_info = None
    if target_group_name:
        load_balancer_info = {"targetGroupInfoList": [{"name": target_group_name}]}

    try:
        CODEDEPLOY_CLIENT.get_deployment_group(
            applicationName=app_name, deploymentGroupName=deployment_group_name
        )
        update_args = {
            "applicationName": app_name,
            "currentDeploymentGroupName": deployment_group_name,
            "deploymentConfigName": deployment_config_name,
            "serviceRoleArn": service_role_arn,
            "autoScalingGroups": [asg_name],
            "deploymentStyle": deployment_style,
            "autoRollbackConfiguration": auto_rollback_config,
        }
        if load_balancer_info:
            update_args["loadBalancerInfo"] = load_balancer_info

        CODEDEPLOY_CLIENT.update_deployment_group(**update_args)
        return True
    except ClientError as exc:
        if exc.response["Error"]["Code"] != "DeploymentGroupDoesNotExistException":
            raise

    LOGGER.info("Creating CodeDeploy deployment group: %s", deployment_group_name)
    create_args = {
        "applicationName": app_name,
        "deploymentGroupName": deployment_group_name,
        "deploymentConfigName": deployment_config_name,
        "serviceRoleArn": service_role_arn,
        "autoScalingGroups": [asg_name],
        "deploymentStyle": deployment_style,
        "autoRollbackConfiguration": auto_rollback_config,
    }
    if load_balancer_info:
        create_args["loadBalancerInfo"] = load_balancer_info

    CODEDEPLOY_CLIENT.create_deployment_group(**create_args)
    return True


def _discover_service_dirs(app_dir):
    services = []
    if not app_dir or not os.path.isdir(app_dir):
        return services

    entries = [
        entry
        for entry in os.listdir(app_dir)
        if entry not in IGNORE_ENTRIES and not entry.startswith(".")
    ]

    for entry in entries:
        full_path = os.path.join(app_dir, entry)
        if not os.path.isdir(full_path):
            continue
        entry_lower = entry.lower()
        if entry == "WebSocketFullFiles":
            subdirs = [
                sub
                for sub in os.listdir(full_path)
                if os.path.isdir(os.path.join(full_path, sub))
            ]
            for sub in subdirs:
                services.append(
                    {"name": sub, "path": os.path.join(full_path, sub)}
                )
        elif entry_lower in ("s3 publish", "s3_publish", "s3publish"):
            subdirs = [
                sub
                for sub in os.listdir(full_path)
                if os.path.isdir(os.path.join(full_path, sub))
            ]
            subdirs.sort()
            if subdirs:
                services.append(
                    {
                        "name": "FileMgmtS3",
                        "path": os.path.join(full_path, subdirs[0]),
                    }
                )
        else:
            services.append({"name": entry, "path": full_path})

    return services


def _seed_ssm_parameters(services, ssm_base_path, files_to_seed):
    base_path = ssm_base_path.rstrip("/")
    for service in services:
        service_name = service.get("name")
        service_path = service.get("path")
        if not service_name or not service_path:
            continue
        if not re.match(r"^[A-Za-z0-9_.-]+$", service_name):
            LOGGER.warning("Skipping SSM seed for unsupported service name: %s", service_name)
            continue
        for filename in files_to_seed:
            file_path = os.path.join(service_path, filename)
            if not os.path.isfile(file_path):
                continue

            param_name = f"{base_path}/{service_name}/{filename}"
            with open(file_path, "rb") as handle:
                content = handle.read().decode("utf-8", errors="replace")

            put_args = {
                "Name": param_name,
                "Type": "SecureString",
                "Value": content,
                "Overwrite": False,
            }
            if SSM_KMS_KEY_ID:
                put_args["KeyId"] = SSM_KMS_KEY_ID

            try:
                SSM_CLIENT.put_parameter(**put_args)
                LOGGER.info("Seeded SSM parameter: %s", param_name)
            except ClientError as exc:
                if exc.response["Error"]["Code"] == "ParameterAlreadyExists":
                    LOGGER.info("SSM parameter already exists: %s", param_name)
                else:
                    raise
