#!/bin/bash
###############################################################################
# Stop All Preprod Services
# Stops ASGs, RDS, ElastiCache, OpenSearch, and standalone EC2 instances
# Usage: ./stop-all-services.sh [--region eu-west-1] [--dry-run]
###############################################################################

set -e

# Default values
REGION="eu-west-1"
ENVIRONMENT="preprod"
DRY_RUN=false
NAME_PREFIX="${ENVIRONMENT}-ajyal"

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
echo "Stopping All ${ENVIRONMENT} Services"
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

# 1. Scale down all Auto Scaling Groups to 0
echo "--- Scaling down Auto Scaling Groups ---"
ASG_NAMES=(
    "${NAME_PREFIX}-app-asg"
    "${NAME_PREFIX}-api-asg"
    "${NAME_PREFIX}-integration-asg"
    "${NAME_PREFIX}-logging-asg"
    "${NAME_PREFIX}-botpress-asg"
    "${NAME_PREFIX}-ml-asg"
    "${NAME_PREFIX}-content-asg"
)

for ASG in "${ASG_NAMES[@]}"; do
    echo "Scaling down ASG: ${ASG}"
    run_cmd "aws autoscaling update-auto-scaling-group \
        --auto-scaling-group-name ${ASG} \
        --min-size 0 \
        --max-size 0 \
        --desired-capacity 0 \
        --region ${REGION} 2>/dev/null || echo 'ASG ${ASG} not found or already scaled down'"
done
echo ""

# 2. Stop RabbitMQ standalone EC2 instance
echo "--- Stopping RabbitMQ EC2 Instance ---"
RABBITMQ_INSTANCE=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${NAME_PREFIX}-rabbitmq" "Name=instance-state-name,Values=running" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text \
    --region ${REGION} 2>/dev/null || echo "")

if [ -n "$RABBITMQ_INSTANCE" ] && [ "$RABBITMQ_INSTANCE" != "None" ]; then
    echo "Stopping RabbitMQ instance: ${RABBITMQ_INSTANCE}"
    run_cmd "aws ec2 stop-instances --instance-ids ${RABBITMQ_INSTANCE} --region ${REGION}"
else
    echo "No running RabbitMQ instance found"
fi
echo ""

# 3. Stop RDS instances
echo "--- Stopping RDS Instances ---"
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

    if [ "$STATUS" = "available" ]; then
        echo "Stopping RDS instance: ${RDS}"
        run_cmd "aws rds stop-db-instance --db-instance-identifier ${RDS} --region ${REGION}"
    else
        echo "RDS instance ${RDS} is not in 'available' state (current: ${STATUS})"
    fi
done
echo ""

# 4. Stop ElastiCache Redis clusters
echo "--- Stopping ElastiCache Redis ---"
# Note: ElastiCache cannot be stopped, only deleted or scaled down
# For cost savings, we'll reduce node count to minimum
REDIS_CLUSTERS=$(aws elasticache describe-replication-groups \
    --query "ReplicationGroups[?contains(ReplicationGroupId, '${NAME_PREFIX}')].ReplicationGroupId" \
    --output text \
    --region ${REGION} 2>/dev/null || echo "")

if [ -n "$REDIS_CLUSTERS" ] && [ "$REDIS_CLUSTERS" != "None" ]; then
    echo "NOTE: ElastiCache cannot be stopped. Consider deleting for cost savings."
    echo "Found clusters: ${REDIS_CLUSTERS}"
    echo "To delete, run: aws elasticache delete-replication-group --replication-group-id <ID> --region ${REGION}"
else
    echo "No ElastiCache clusters found"
fi
echo ""

# 5. Pause OpenSearch domain (if supported) or note for manual action
echo "--- OpenSearch Domain ---"
# Note: OpenSearch cannot be stopped, only deleted
# Check if domain exists
OS_DOMAINS=$(aws opensearch list-domain-names \
    --query "DomainNames[?contains(DomainName, '${NAME_PREFIX}')].DomainName" \
    --output text \
    --region ${REGION} 2>/dev/null || echo "")

if [ -n "$OS_DOMAINS" ] && [ "$OS_DOMAINS" != "None" ]; then
    echo "NOTE: OpenSearch domains cannot be stopped. Consider deleting for cost savings."
    echo "Found domains: ${OS_DOMAINS}"
    echo "To delete, run: aws opensearch delete-domain --domain-name <NAME> --region ${REGION}"
else
    echo "No OpenSearch domains found"
fi
echo ""

# 6. Stop NAT Gateway (optional - saves ~$32/month per gateway)
echo "--- NAT Gateways ---"
NAT_GATEWAYS=$(aws ec2 describe-nat-gateways \
    --filter "Name=tag:Name,Values=*${NAME_PREFIX}*" "Name=state,Values=available" \
    --query 'NatGateways[*].NatGatewayId' \
    --output text \
    --region ${REGION} 2>/dev/null || echo "")

if [ -n "$NAT_GATEWAYS" ] && [ "$NAT_GATEWAYS" != "None" ]; then
    echo "Found NAT Gateways: ${NAT_GATEWAYS}"
    echo "NOTE: Deleting NAT Gateway will disrupt private subnet internet access."
    echo "To delete, run: aws ec2 delete-nat-gateway --nat-gateway-id <ID> --region ${REGION}"
else
    echo "No NAT Gateways found"
fi
echo ""

echo "========================================"
echo "Stop operation completed!"
echo "========================================"
echo ""
echo "Summary of what was stopped:"
echo "- ASGs scaled to 0 (instances will terminate)"
echo "- RabbitMQ EC2 instance stopped"
echo "- RDS instances stopped"
echo ""
echo "Manual actions required for full cost savings:"
echo "- Delete ElastiCache clusters if not needed"
echo "- Delete OpenSearch domains if not needed"
echo "- Delete NAT Gateways if not needed (will break private subnet connectivity)"
echo ""
echo "To start services again, run: ./start-all-services.sh"
