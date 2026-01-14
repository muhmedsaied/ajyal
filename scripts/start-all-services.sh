#!/bin/bash
###############################################################################
# Start All Preprod Services
# Starts ASGs, RDS, and standalone EC2 instances
# Usage: ./start-all-services.sh [--region eu-west-1] [--dry-run]
###############################################################################

set -e

# Default values
REGION="eu-west-1"
ENVIRONMENT="preprod"
DRY_RUN=false
NAME_PREFIX="${ENVIRONMENT}-ajyal"

# Default ASG sizes (min, max, desired)
declare -A ASG_SIZES
ASG_SIZES["${NAME_PREFIX}-app-asg"]="2,20,2"
ASG_SIZES["${NAME_PREFIX}-api-asg"]="2,10,2"
ASG_SIZES["${NAME_PREFIX}-integration-asg"]="2,10,2"
ASG_SIZES["${NAME_PREFIX}-logging-asg"]="2,4,2"
ASG_SIZES["${NAME_PREFIX}-botpress-asg"]="2,3,2"
ASG_SIZES["${NAME_PREFIX}-ml-asg"]="2,4,2"
ASG_SIZES["${NAME_PREFIX}-content-asg"]="2,8,2"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            REGION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--region REGION] [--dry-run]"
            echo "  --region    AWS region (default: eu-west-1)"
            echo "  --dry-run   Show what would be done without making changes"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "========================================"
echo "Starting All ${ENVIRONMENT} Services"
echo "Region: ${REGION}"
echo "Dry Run: ${DRY_RUN}"
echo "========================================"
echo ""

run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would execute: $*"
    else
        echo "[EXECUTING] $*"
        eval "$@"
    fi
}

# 1. Start RDS instances first (they take longest)
echo "--- Starting RDS Instances ---"
RDS_INSTANCES=$(aws rds describe-db-instances \
    --query "DBInstances[?contains(DBInstanceIdentifier, '${NAME_PREFIX}')].DBInstanceIdentifier" \
    --output text \
    --region ${REGION} 2>/dev/null || echo "")

for RDS in $RDS_INSTANCES; do
    STATUS=$(aws rds describe-db-instances \
        --db-instance-identifier ${RDS} \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text \
        --region ${REGION} 2>/dev/null || echo "not-found")

    if [ "$STATUS" = "stopped" ]; then
        echo "Starting RDS instance: ${RDS}"
        run_cmd "aws rds start-db-instance --db-instance-identifier ${RDS} --region ${REGION}"
    else
        echo "RDS instance ${RDS} is not in 'stopped' state (current: ${STATUS})"
    fi
done
echo ""

# 2. Start RabbitMQ standalone EC2 instance
echo "--- Starting RabbitMQ EC2 Instance ---"
RABBITMQ_INSTANCE=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${NAME_PREFIX}-rabbitmq" "Name=instance-state-name,Values=stopped" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text \
    --region ${REGION} 2>/dev/null || echo "")

if [ -n "$RABBITMQ_INSTANCE" ] && [ "$RABBITMQ_INSTANCE" != "None" ]; then
    echo "Starting RabbitMQ instance: ${RABBITMQ_INSTANCE}"
    run_cmd "aws ec2 start-instances --instance-ids ${RABBITMQ_INSTANCE} --region ${REGION}"
else
    echo "No stopped RabbitMQ instance found"
fi
echo ""

# 3. Scale up all Auto Scaling Groups
echo "--- Scaling up Auto Scaling Groups ---"
for ASG in "${!ASG_SIZES[@]}"; do
    IFS=',' read -r MIN MAX DESIRED <<< "${ASG_SIZES[$ASG]}"
    echo "Scaling up ASG: ${ASG} (min=${MIN}, max=${MAX}, desired=${DESIRED})"
    run_cmd "aws autoscaling update-auto-scaling-group \
        --auto-scaling-group-name ${ASG} \
        --min-size ${MIN} \
        --max-size ${MAX} \
        --desired-capacity ${DESIRED} \
        --region ${REGION} 2>/dev/null || echo 'ASG ${ASG} not found'"
done
echo ""

# 4. Wait for RDS to be available (optional)
echo "--- Waiting for RDS Instances ---"
for RDS in $RDS_INSTANCES; do
    echo "Waiting for RDS instance ${RDS} to become available..."
    if [ "$DRY_RUN" = false ]; then
        aws rds wait db-instance-available \
            --db-instance-identifier ${RDS} \
            --region ${REGION} 2>/dev/null || echo "Timeout or error waiting for ${RDS}"
    fi
done
echo ""

# 5. Verify services are starting
echo "--- Verification ---"
echo ""
echo "ASG Status:"
for ASG in "${!ASG_SIZES[@]}"; do
    INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names ${ASG} \
        --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
        --output text \
        --region ${REGION} 2>/dev/null || echo "N/A")
    DESIRED=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names ${ASG} \
        --query 'AutoScalingGroups[0].DesiredCapacity' \
        --output text \
        --region ${REGION} 2>/dev/null || echo "0")
    echo "  ${ASG}: Desired=${DESIRED}, Instances=${INSTANCES:-none}"
done
echo ""

echo "RDS Status:"
for RDS in $RDS_INSTANCES; do
    STATUS=$(aws rds describe-db-instances \
        --db-instance-identifier ${RDS} \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text \
        --region ${REGION} 2>/dev/null || echo "not-found")
    echo "  ${RDS}: ${STATUS}"
done
echo ""

echo "========================================"
echo "Start operation completed!"
echo "========================================"
echo ""
echo "Note: It may take several minutes for all services to become healthy."
echo "- RDS instances typically take 5-10 minutes to start"
echo "- EC2 instances in ASGs take 3-5 minutes to launch and pass health checks"
echo ""
echo "To check ALB health, run:"
echo "  aws elbv2 describe-target-health --target-group-arn <ARN> --region ${REGION}"
