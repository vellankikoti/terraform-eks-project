#!/bin/bash
#
# EKS Cluster Creation Script
# Usage: ./scripts/create-cluster.sh <environment>
#
# Creates an EKS cluster and all addons for the specified environment using Terraform.
# Handles the full lifecycle: init, plan, apply, kubeconfig setup.
#
# Examples:
#   ./scripts/create-cluster.sh dev
#   ./scripts/create-cluster.sh staging
#   ./scripts/create-cluster.sh prod --auto-approve
#
set -euo pipefail

###############################################################################
# Configuration
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform/environments"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/eks-create-${TIMESTAMP}.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

###############################################################################
# Helper Functions
###############################################################################

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
info() { echo -e "${CYAN}[INFO]${NC} $*" | tee -a "$LOG_FILE"; }

header() {
    echo ""
    echo -e "${BLUE}================================================================${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}  $*${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}================================================================${NC}" | tee -a "$LOG_FILE"
    echo ""
}

confirm() {
    echo -e "${YELLOW}$1 [y/N]${NC}"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "$1 is required but not installed."
    fi
}

###############################################################################
# Parse Arguments
###############################################################################

ENVIRONMENT="${1:-}"
AUTO_APPROVE="false"

for arg in "$@"; do
    if [[ "$arg" == "--auto-approve" ]]; then
        AUTO_APPROVE="true"
    fi
done

if [[ -z "$ENVIRONMENT" ]]; then
    echo "Usage: $0 <environment> [--auto-approve]"
    echo ""
    echo "Arguments:"
    echo "  environment     Environment to create (dev, staging, prod)"
    echo "  --auto-approve  Skip confirmation prompts (use with caution)"
    echo ""
    echo "Examples:"
    echo "  $0 dev                  # Create dev cluster with confirmation"
    echo "  $0 staging              # Create staging cluster"
    echo "  $0 dev --auto-approve   # Create dev cluster without prompts"
    exit 1
fi

if [[ ! -d "${TERRAFORM_DIR}/${ENVIRONMENT}" ]]; then
    error "Environment '${ENVIRONMENT}' not found at ${TERRAFORM_DIR}/${ENVIRONMENT}"
fi

###############################################################################
# Pre-flight Checks
###############################################################################

header "Pre-flight Checks"

check_command aws
check_command terraform
check_command kubectl
check_command helm
log "All required tools available."

# Verify AWS credentials
log "Verifying AWS credentials..."
AWS_IDENTITY=$(aws sts get-caller-identity 2>/dev/null || error "AWS credentials not configured. Run 'aws configure' first.")
AWS_ACCOUNT=$(echo "$AWS_IDENTITY" | jq -r '.Account')
AWS_USER=$(echo "$AWS_IDENTITY" | jq -r '.Arn')
log "AWS Account: ${AWS_ACCOUNT}"
log "AWS Identity: ${AWS_USER}"

# Get region from variables
AWS_REGION=$(grep -A2 'variable "aws_region"' "${TERRAFORM_DIR}/${ENVIRONMENT}/variables.tf" | grep default | sed 's/.*"\(.*\)".*/\1/' || echo "us-east-1")
log "Target region: ${AWS_REGION}"

# Estimate costs
header "Cost Estimate"
case "$ENVIRONMENT" in
    dev)
        info "Estimated monthly cost: ~\$150-200"
        info "  EKS control plane: \$75"
        info "  2x t3.medium ON_DEMAND: ~\$60"
        info "  1x NAT Gateway: ~\$35"
        info "  CloudWatch, EBS: ~\$10"
        info ""
        info "Tip: Destroy dev clusters when not in use to save costs."
        ;;
    staging)
        info "Estimated monthly cost: ~\$300-400"
        info "  EKS control plane: \$75"
        info "  2x t3.large ON_DEMAND: ~\$120"
        info "  Spot nodes: ~\$30-60"
        info "  2x NAT Gateway: ~\$70"
        info "  Monitoring, logging: ~\$30"
        ;;
    prod)
        info "Estimated monthly cost: ~\$500-800"
        info "  EKS control plane: \$75"
        info "  3x m5.large ON_DEMAND: ~\$210"
        info "  Spot nodes: ~\$60-150"
        info "  3x NAT Gateway: ~\$105"
        info "  VPC endpoints, monitoring: ~\$50-80"
        warn ""
        warn "PRODUCTION CLUSTER - This will create a production-grade cluster."
        warn "Ensure you have reviewed all configurations before proceeding."
        ;;
esac

if [[ "$AUTO_APPROVE" != "true" ]]; then
    if ! confirm "Create ${ENVIRONMENT} EKS cluster in account ${AWS_ACCOUNT}?"; then
        log "Cluster creation cancelled by user."
        exit 0
    fi
fi

###############################################################################
# Terraform Init
###############################################################################

header "Terraform Init"

cd "${TERRAFORM_DIR}/${ENVIRONMENT}"

log "Initializing Terraform..."
terraform init -upgrade 2>&1 | tee -a "$LOG_FILE"
log "Terraform initialized successfully."

###############################################################################
# Terraform Plan
###############################################################################

header "Terraform Plan"

PLAN_FILE="/tmp/eks-create-${ENVIRONMENT}-${TIMESTAMP}.tfplan"

log "Generating execution plan..."
terraform plan -out="$PLAN_FILE" 2>&1 | tee -a "$LOG_FILE"
log "Plan saved to ${PLAN_FILE}"

if [[ "$AUTO_APPROVE" != "true" ]]; then
    echo ""
    if ! confirm "Review the plan above. Proceed with cluster creation?"; then
        log "Cluster creation cancelled by user after plan review."
        exit 0
    fi
fi

###############################################################################
# Terraform Apply
###############################################################################

header "Terraform Apply"

log "Creating EKS cluster and all resources..."
log "This will take approximately 15-25 minutes..."
echo ""

terraform apply "$PLAN_FILE" 2>&1 | tee -a "$LOG_FILE"

log "Terraform apply completed successfully."

###############################################################################
# Post-creation Setup
###############################################################################

header "Post-creation Setup"

# Get cluster name from outputs
CLUSTER_NAME=$(terraform output -raw cluster_id 2>/dev/null || echo "")
if [[ -z "$CLUSTER_NAME" ]]; then
    warn "Could not get cluster_id from outputs."
    CLUSTER_NAME="myapp-${ENVIRONMENT}"
fi

# Update kubeconfig
log "Configuring kubectl..."
aws eks update-kubeconfig \
    --name "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --alias "$CLUSTER_NAME" \
    2>&1 | tee -a "$LOG_FILE"

log "kubectl configured for cluster ${CLUSTER_NAME}"

# Verify connectivity
log "Verifying cluster connectivity..."
kubectl cluster-info 2>&1 | head -3 | tee -a "$LOG_FILE"

# Show nodes
log "Cluster nodes:"
kubectl get nodes -o wide 2>/dev/null | tee -a "$LOG_FILE"

# Show namespaces
log "Namespaces:"
kubectl get namespaces 2>/dev/null | tee -a "$LOG_FILE"

# Wait for system pods
log "Waiting for system pods to be ready..."
kubectl wait --for=condition=Ready pod --all -n kube-system --timeout=300s 2>/dev/null || warn "Some system pods may not be ready yet."

# Show all pods
log "All pods:"
kubectl get pods --all-namespaces 2>/dev/null | tee -a "$LOG_FILE"

###############################################################################
# Summary
###############################################################################

header "Cluster Created Successfully"

log "Cluster: ${CLUSTER_NAME}"
log "Environment: ${ENVIRONMENT}"
log "Region: ${AWS_REGION}"
log "Account: ${AWS_ACCOUNT}"

echo ""
info "Outputs:"
terraform output 2>/dev/null | tee -a "$LOG_FILE"

echo ""
log "Useful commands:"
info "  kubectl get nodes                          # List nodes"
info "  kubectl get pods --all-namespaces           # List all pods"
info "  kubectl get svc --all-namespaces            # List all services"
info "  aws eks describe-cluster --name ${CLUSTER_NAME}  # Cluster details"

echo ""
log "Log file: ${LOG_FILE}"
echo ""
