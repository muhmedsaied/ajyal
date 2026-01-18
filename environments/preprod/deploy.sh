#!/bin/bash
###############################################################################
# Ajyal LMS PreProd - Deployment Script
# Deploys all modules in correct order with separate tfstate per module
#
# S3 State Structure:
#   s3://preprod-ajyal-terraform-state/preprod/vpc/terraform.tfstate
#   s3://preprod-ajyal-terraform-state/preprod/security/terraform.tfstate
#   s3://preprod-ajyal-terraform-state/preprod/storage/terraform.tfstate
#   s3://preprod-ajyal-terraform-state/preprod/database/terraform.tfstate
#   s3://preprod-ajyal-terraform-state/preprod/cicd/terraform.tfstate
#   s3://preprod-ajyal-terraform-state/preprod/compute/terraform.tfstate
#   s3://preprod-ajyal-terraform-state/preprod/patching/terraform.tfstate
#   s3://preprod-ajyal-terraform-state/preprod/monitoring/terraform.tfstate
###############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Modules in deployment order (dependencies respected)
MODULES=(
    "01-vpc"
    "02-security"
    "03-storage"
    "04-database"
    "05-cicd"
    "06-compute"
    "07-patching"
    "08-monitoring"
    "09-budget"
)

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to deploy a module
deploy_module() {
    local module=$1
    local action=${2:-apply}

    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}Deploying: ${module}${NC}"
    echo -e "${YELLOW}========================================${NC}"

    cd "${SCRIPT_DIR}/${module}"

    # Initialize
    terraform init -upgrade

    if [ "$action" == "plan" ]; then
        terraform plan
    elif [ "$action" == "apply" ]; then
        terraform apply -auto-approve
    elif [ "$action" == "destroy" ]; then
        terraform destroy -auto-approve
    fi

    echo -e "${GREEN}Completed: ${module}${NC}"
    cd "${SCRIPT_DIR}"
}

# Function to deploy all modules
deploy_all() {
    local action=${1:-apply}

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Deploying ALL modules (${action})${NC}"
    echo -e "${GREEN}========================================${NC}"

    for module in "${MODULES[@]}"; do
        deploy_module "$module" "$action"
    done

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}All modules deployed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# Function to destroy all modules (reverse order)
destroy_all() {
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Destroying ALL modules (reverse order)${NC}"
    echo -e "${RED}========================================${NC}"

    # Reverse order for destroy
    for ((i=${#MODULES[@]}-1; i>=0; i--)); do
        deploy_module "${MODULES[$i]}" "destroy"
    done

    echo -e "${RED}========================================${NC}"
    echo -e "${RED}All modules destroyed!${NC}"
    echo -e "${RED}========================================${NC}"
}

# Main
case "${1:-}" in
    "plan")
        if [ -n "${2:-}" ]; then
            deploy_module "$2" "plan"
        else
            deploy_all "plan"
        fi
        ;;
    "apply")
        if [ -n "${2:-}" ]; then
            deploy_module "$2" "apply"
        else
            deploy_all "apply"
        fi
        ;;
    "destroy")
        if [ -n "${2:-}" ]; then
            deploy_module "$2" "destroy"
        else
            destroy_all
        fi
        ;;
    *)
        echo "Usage: $0 {plan|apply|destroy} [module-name]"
        echo ""
        echo "Examples:"
        echo "  $0 plan                    # Plan all modules"
        echo "  $0 apply                   # Deploy all modules"
        echo "  $0 destroy                 # Destroy all modules"
        echo "  $0 apply 01-vpc           # Deploy only VPC"
        echo "  $0 apply 06-compute       # Deploy only Compute (EC2)"
        echo "  $0 destroy 04-database    # Destroy only Database"
        echo ""
        echo "Available modules:"
        for module in "${MODULES[@]}"; do
            echo "  - $module"
        done
        ;;
esac
