#!/bin/bash
#
# EKS Cluster Destruction Script
# Usage: ./scripts/destroy-cluster.sh <environment>
#
# Safely destroys an EKS cluster and all associated resources.
# Includes safety checks to prevent accidental production deletion.
#
# Examples:
#   ./scripts/destroy-cluster.sh dev
#   ./scripts/destroy-cluster.sh staging
#   ./scripts/destroy-cluster.sh prod    # Requires extra confirmation
#
set -euo pipefail

###############################################################################
# Configuration
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform/environments"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/eks-destroy-${TIMESTAMP}.log"

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

if [[ -z "$ENVIRONMENT" ]]; then
    echo "Usage: $0 <environment>"
    echo ""
    echo "Arguments:"
    echo "  environment   Environment to destroy (dev, staging, prod)"
    echo ""
    echo "Examples:"
    echo "  $0 dev       # Destroy dev cluster"
    echo "  $0 staging   # Destroy staging cluster"
    echo "  $0 prod      # Destroy prod (requires typing environment name)"
    exit 1
fi

if [[ ! -d "${TERRAFORM_DIR}/${ENVIRONMENT}" ]]; then
    error "Environment '${ENVIRONMENT}' not found at ${TERRAFORM_DIR}/${ENVIRONMENT}"
fi

###############################################################################
# Safety Checks
###############################################################################

header "Safety Checks"

check_command aws
check_command terraform
log "Required tools available."

# Verify AWS identity
AWS_IDENTITY=$(aws sts get-caller-identity 2>/dev/null || error "AWS credentials not configured.")
AWS_ACCOUNT=$(echo "$AWS_IDENTITY" | jq -r '.Account')
AWS_USER=$(echo "$AWS_IDENTITY" | jq -r '.Arn')
log "AWS Account: ${AWS_ACCOUNT}"
log "AWS Identity: ${AWS_USER}"

# Get cluster info
cd "${TERRAFORM_DIR}/${ENVIRONMENT}"
CLUSTER_NAME=$(terraform output -raw cluster_id 2>/dev/null || echo "unknown")
log "Cluster to destroy: ${CLUSTER_NAME}"

# Production safety: require typing the environment name
if [[ "$ENVIRONMENT" == "prod" ]]; then
    echo ""
    echo -e "${RED}================================================================${NC}"
    echo -e "${RED}  DANGER: You are about to destroy the PRODUCTION cluster!${NC}"
    echo -e "${RED}================================================================${NC}"
    echo ""
    echo -e "${RED}Cluster: ${CLUSTER_NAME}${NC}"
    echo -e "${RED}Account: ${AWS_ACCOUNT}${NC}"
    echo ""
    echo -e "${YELLOW}This action CANNOT be undone. All data will be lost.${NC}"
    echo ""
    echo -e "${YELLOW}Type the environment name '${ENVIRONMENT}' to confirm:${NC}"
    read -r confirmation
    if [[ "$confirmation" != "$ENVIRONMENT" ]]; then
        error "Confirmation failed. Destruction cancelled."
    fi
    echo ""
    echo -e "${YELLOW}Are you ABSOLUTELY sure? Type 'yes-destroy-production' to confirm:${NC}"
    read -r final_confirmation
    if [[ "$final_confirmation" != "yes-destroy-production" ]]; then
        error "Final confirmation failed. Destruction cancelled."
    fi
else
    warn "You are about to destroy the ${ENVIRONMENT} EKS cluster."
    warn "Cluster: ${CLUSTER_NAME}"
    warn "Account: ${AWS_ACCOUNT}"
    echo ""
    if ! confirm "Proceed with destroying the ${ENVIRONMENT} cluster?"; then
        log "Destruction cancelled by user."
        exit 0
    fi
fi

###############################################################################
# Pre-destruction Cleanup
###############################################################################

header "Pre-destruction Cleanup"

# Clean up Kubernetes resources that may block Terraform destroy
# (LoadBalancers create AWS resources that Terraform doesn't manage)

log "Checking for LoadBalancer services that need cleanup..."
if command -v kubectl &> /dev/null; then
    # Try to connect to the cluster
    aws eks update-kubeconfig --name "$CLUSTER_NAME" 2>/dev/null || true

    LB_SERVICES=$(kubectl get svc --all-namespaces -o json 2>/dev/null | jq -r '.items[] | select(.spec.type == "LoadBalancer") | "\(.metadata.namespace)/\(.metadata.name)"' || true)
    if [[ -n "$LB_SERVICES" ]]; then
        warn "Found LoadBalancer services (these create AWS ELBs):"
        echo "$LB_SERVICES" | tee -a "$LOG_FILE"
        log "Deleting LoadBalancer services to clean up AWS resources..."
        for svc in $LB_SERVICES; do
            NS=$(echo "$svc" | cut -d/ -f1)
            NAME=$(echo "$svc" | cut -d/ -f2)
            kubectl delete svc "$NAME" -n "$NS" --timeout=60s 2>/dev/null || warn "Failed to delete ${svc}"
        done
        log "Waiting 30s for AWS resources to be cleaned up..."
        sleep 30
    else
        log "No LoadBalancer services found."
    fi

    # Delete Ingress resources (ALB Ingress Controller creates ALBs)
    log "Checking for Ingress resources..."
    INGRESSES=$(kubectl get ingress --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    if [[ "$INGRESSES" -gt 0 ]]; then
        warn "Found ${INGRESSES} Ingress resource(s). Deleting..."
        kubectl delete ingress --all --all-namespaces --timeout=60s 2>/dev/null || true
        sleep 15
    fi
else
    warn "kubectl not available. Skipping Kubernetes resource cleanup."
    warn "You may need to manually clean up AWS ELBs after destruction."
fi

###############################################################################
# Backup Terraform State
###############################################################################

header "Backing Up Terraform State"

BACKUP_DIR="${PROJECT_ROOT}/.state-backups/${ENVIRONMENT}"
mkdir -p "$BACKUP_DIR"

terraform state pull > "${BACKUP_DIR}/terraform.tfstate.pre-destroy.${TIMESTAMP}" 2>/dev/null || true
if [[ -s "${BACKUP_DIR}/terraform.tfstate.pre-destroy.${TIMESTAMP}" ]]; then
    log "State backed up to ${BACKUP_DIR}/terraform.tfstate.pre-destroy.${TIMESTAMP}"
else
    warn "Could not backup state (may already be empty)."
fi

###############################################################################
# Terraform Destroy
###############################################################################

header "Terraform Destroy"

log "Destroying all resources for ${ENVIRONMENT}..."
log "This will take approximately 10-20 minutes..."
echo ""

terraform destroy -auto-approve 2>&1 | tee -a "$LOG_FILE"

log "Terraform destroy completed."

###############################################################################
# Post-destruction Cleanup
###############################################################################

header "Post-destruction Cleanup"

# Remove kubeconfig context
log "Cleaning up kubeconfig..."
kubectl config delete-context "$CLUSTER_NAME" 2>/dev/null || true
kubectl config delete-cluster "$CLUSTER_NAME" 2>/dev/null || true
log "Kubeconfig cleaned up."

# Check for orphaned resources
log "Checking for orphaned AWS resources..."
warn "Please manually verify the following are cleaned up:"
info "  - EC2 instances (check for any stuck instances)"
info "  - EBS volumes (persistent volumes may remain)"
info "  - Elastic Load Balancers (from LoadBalancer services)"
info "  - Security Groups (custom ones may remain)"
info "  - ENIs (network interfaces may take time to release)"
info "  - CloudWatch Log Groups (may be retained by policy)"

###############################################################################
# Summary
###############################################################################

header "Destruction Complete"

log "Environment: ${ENVIRONMENT}"
log "Cluster: ${CLUSTER_NAME}"
log "Account: ${AWS_ACCOUNT}"
log "State backup: ${BACKUP_DIR}/"
log "Log file: ${LOG_FILE}"

echo ""
info "The ${ENVIRONMENT} cluster has been destroyed."
if [[ "$ENVIRONMENT" == "dev" || "$ENVIRONMENT" == "staging" ]]; then
    info "To recreate: ./scripts/create-cluster.sh ${ENVIRONMENT}"
fi
echo ""
