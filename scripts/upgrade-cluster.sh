#!/bin/bash
#
# EKS Cluster Upgrade Script
# Usage: ./scripts/upgrade-cluster.sh <environment> [target-version]
#
# This script orchestrates EKS cluster upgrades following AWS best practices:
# 1. Pre-upgrade validation (PDBs, node health, addon compatibility)
# 2. Terraform state backup
# 3. Control plane upgrade (via aws eks update-cluster-version)
# 4. Managed node group upgrades (one at a time, rolling)
# 5. EKS managed addon updates (VPC CNI, CoreDNS, kube-proxy)
# 6. Post-upgrade validation
#
# Supports --dry-run to preview changes without applying them.
#
# Examples:
#   ./scripts/upgrade-cluster.sh dev                    # Upgrade dev to next minor version
#   ./scripts/upgrade-cluster.sh staging 1.31           # Upgrade staging to 1.31
#   ./scripts/upgrade-cluster.sh prod 1.31 --dry-run    # Preview prod upgrade to 1.31
#
set -euo pipefail

###############################################################################
# Configuration
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform/environments"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/eks-upgrade-${TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

###############################################################################
# Helper Functions
###############################################################################

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${CYAN}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

header() {
    echo ""
    echo -e "${BLUE}================================================================${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}  $*${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}================================================================${NC}" | tee -a "$LOG_FILE"
    echo ""
}

confirm() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would prompt for confirmation: $1"
        return 0
    fi
    echo -e "${YELLOW}$1 [y/N]${NC}"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "$1 is required but not installed. Please install it first."
    fi
}

###############################################################################
# Parse Arguments
###############################################################################

ENVIRONMENT="${1:-}"
TARGET_VERSION="${2:-}"
DRY_RUN="false"

# Check for --dry-run flag in any position
for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN="true"
    fi
done

# If target version is --dry-run, clear it
if [[ "$TARGET_VERSION" == "--dry-run" ]]; then
    TARGET_VERSION=""
fi

if [[ -z "$ENVIRONMENT" ]]; then
    echo "Usage: $0 <environment> [target-version] [--dry-run]"
    echo ""
    echo "Arguments:"
    echo "  environment      Environment to upgrade (dev, staging, prod)"
    echo "  target-version   Target Kubernetes version (e.g., 1.31). Optional - defaults to next minor."
    echo "  --dry-run        Preview changes without applying them"
    echo ""
    echo "Examples:"
    echo "  $0 dev                      # Upgrade dev to next minor version"
    echo "  $0 staging 1.31             # Upgrade staging to 1.31"
    echo "  $0 prod 1.31 --dry-run      # Preview prod upgrade"
    exit 1
fi

# Validate environment
if [[ ! -d "${TERRAFORM_DIR}/${ENVIRONMENT}" ]]; then
    error "Environment '${ENVIRONMENT}' not found at ${TERRAFORM_DIR}/${ENVIRONMENT}"
fi

###############################################################################
# Pre-flight Checks
###############################################################################

header "Pre-flight Checks"

log "Checking required tools..."
check_command aws
check_command kubectl
check_command terraform
check_command jq
log "All required tools are available."

# Derive cluster name from Terraform
CLUSTER_NAME=$(cd "${TERRAFORM_DIR}/${ENVIRONMENT}" && terraform output -raw cluster_id 2>/dev/null || echo "")
if [[ -z "$CLUSTER_NAME" ]]; then
    # Fallback: construct from convention
    PROJECT_NAME=$(grep -A2 'variable "project_name"' "${TERRAFORM_DIR}/${ENVIRONMENT}/variables.tf" | grep default | sed 's/.*"\(.*\)".*/\1/' || echo "myapp")
    CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}"
    warn "Could not get cluster_id from Terraform output. Using convention: ${CLUSTER_NAME}"
fi

log "Cluster: ${CLUSTER_NAME}"
log "Environment: ${ENVIRONMENT}"
log "Dry run: ${DRY_RUN}"
log "Log file: ${LOG_FILE}"

# Get current cluster version
CURRENT_VERSION=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.version' --output text 2>/dev/null || echo "unknown")
log "Current EKS version: ${CURRENT_VERSION}"

if [[ "$CURRENT_VERSION" == "unknown" ]]; then
    error "Could not determine current cluster version. Is the cluster running? Check AWS credentials."
fi

# Determine target version
if [[ -z "$TARGET_VERSION" ]]; then
    # Calculate next minor version
    MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)
    MINOR=$(echo "$CURRENT_VERSION" | cut -d. -f2)
    TARGET_VERSION="${MAJOR}.$((MINOR + 1))"
    log "No target version specified. Defaulting to next minor: ${TARGET_VERSION}"
fi

log "Target EKS version: ${TARGET_VERSION}"

# Validate version jump (EKS only supports +1 minor version upgrade)
CURRENT_MINOR=$(echo "$CURRENT_VERSION" | cut -d. -f2)
TARGET_MINOR=$(echo "$TARGET_VERSION" | cut -d. -f2)
VERSION_JUMP=$((TARGET_MINOR - CURRENT_MINOR))

if [[ $VERSION_JUMP -le 0 ]]; then
    error "Target version ${TARGET_VERSION} is not newer than current version ${CURRENT_VERSION}."
fi

if [[ $VERSION_JUMP -gt 1 ]]; then
    error "EKS only supports upgrading one minor version at a time. Current: ${CURRENT_VERSION}, Target: ${TARGET_VERSION}. Upgrade to 1.$((CURRENT_MINOR + 1)) first."
fi

# Check available EKS versions
header "Available EKS Versions"

log "Checking available EKS versions in this region..."
AVAILABLE_VERSIONS=$(aws eks describe-addon-versions --query 'addons[0].addonVersions[*].compatibilities[*].clusterVersion' --output text 2>/dev/null | tr '\t' '\n' | sort -V | uniq || echo "")
if [[ -n "$AVAILABLE_VERSIONS" ]]; then
    info "Available versions: $(echo "$AVAILABLE_VERSIONS" | tr '\n' ' ')"
    if ! echo "$AVAILABLE_VERSIONS" | grep -q "^${TARGET_VERSION}$"; then
        error "Target version ${TARGET_VERSION} is not available in this region."
    fi
    log "Target version ${TARGET_VERSION} is available."
else
    warn "Could not determine available versions. Proceeding with caution."
fi

###############################################################################
# Pre-upgrade Validation
###############################################################################

header "Pre-upgrade Validation"

# Update kubeconfig
log "Updating kubeconfig for cluster ${CLUSTER_NAME}..."
if [[ "$DRY_RUN" == "false" ]]; then
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --alias "$CLUSTER_NAME" 2>&1 | tee -a "$LOG_FILE"
fi

# Check node health
log "Checking node health..."
if [[ "$DRY_RUN" == "false" ]]; then
    NOT_READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready " || true)
    if [[ -n "$NOT_READY_NODES" ]]; then
        warn "The following nodes are NOT ready:"
        echo "$NOT_READY_NODES" | tee -a "$LOG_FILE"
        if [[ "$ENVIRONMENT" == "prod" ]]; then
            error "Cannot upgrade production cluster with unhealthy nodes. Fix node issues first."
        else
            warn "Non-ready nodes detected in ${ENVIRONMENT}. Proceeding with caution."
        fi
    else
        log "All nodes are Ready."
    fi

    # Show node versions
    info "Current node versions:"
    kubectl get nodes -o custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion,STATUS:.status.conditions[-1:].type 2>/dev/null | tee -a "$LOG_FILE"
fi

# Check PodDisruptionBudgets
log "Checking PodDisruptionBudgets (PDBs)..."
if [[ "$DRY_RUN" == "false" ]]; then
    BLOCKING_PDBS=$(kubectl get pdb --all-namespaces -o json 2>/dev/null | jq -r '.items[] | select(.status.disruptionsAllowed == 0) | "\(.metadata.namespace)/\(.metadata.name) - allowed disruptions: 0"' || true)
    if [[ -n "$BLOCKING_PDBS" ]]; then
        warn "The following PDBs may block node drains during upgrade:"
        echo "$BLOCKING_PDBS" | tee -a "$LOG_FILE"
        if [[ "$ENVIRONMENT" == "prod" ]]; then
            warn "Review PDBs carefully before proceeding with production upgrade."
        fi
    else
        log "No blocking PDBs found."
    fi
fi

# Check for deprecated API usage
log "Checking for deprecated API usage..."
if [[ "$DRY_RUN" == "false" ]]; then
    if command -v kubectl-convert &> /dev/null; then
        info "kubectl-convert is available for API migration."
    else
        warn "kubectl-convert not found. Consider installing it to check for deprecated APIs."
        warn "Install: https://kubernetes.io/docs/tasks/tools/"
    fi
fi

# Check current EKS addon versions
log "Checking current EKS managed addon versions..."
if [[ "$DRY_RUN" == "false" ]]; then
    ADDONS=$(aws eks list-addons --cluster-name "$CLUSTER_NAME" --query 'addons[]' --output text 2>/dev/null || echo "")
    if [[ -n "$ADDONS" ]]; then
        for addon in $ADDONS; do
            ADDON_VERSION=$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon" --query 'addon.addonVersion' --output text 2>/dev/null || echo "unknown")
            info "  ${addon}: ${ADDON_VERSION}"
        done
    else
        info "No EKS managed addons found."
    fi
fi

# Check Helm releases
log "Checking Helm releases..."
if [[ "$DRY_RUN" == "false" ]]; then
    if command -v helm &> /dev/null; then
        info "Installed Helm releases:"
        helm list --all-namespaces --short 2>/dev/null | head -20 | tee -a "$LOG_FILE" || true
    fi
fi

###############################################################################
# Backup Terraform State
###############################################################################

header "Terraform State Backup"

BACKUP_DIR="${PROJECT_ROOT}/.state-backups/${ENVIRONMENT}"
mkdir -p "$BACKUP_DIR"

log "Backing up Terraform state..."
if [[ "$DRY_RUN" == "false" ]]; then
    cd "${TERRAFORM_DIR}/${ENVIRONMENT}"

    # Check if using local or remote state
    if [[ -f "terraform.tfstate" ]]; then
        cp terraform.tfstate "${BACKUP_DIR}/terraform.tfstate.${TIMESTAMP}"
        log "Local state backed up to ${BACKUP_DIR}/terraform.tfstate.${TIMESTAMP}"
    fi

    # Pull remote state backup
    terraform state pull > "${BACKUP_DIR}/terraform.tfstate.remote.${TIMESTAMP}" 2>/dev/null || true
    if [[ -s "${BACKUP_DIR}/terraform.tfstate.remote.${TIMESTAMP}" ]]; then
        log "Remote state backed up to ${BACKUP_DIR}/terraform.tfstate.remote.${TIMESTAMP}"
    else
        warn "Could not pull remote state (may be using local backend)."
        rm -f "${BACKUP_DIR}/terraform.tfstate.remote.${TIMESTAMP}"
    fi
else
    info "[DRY-RUN] Would backup Terraform state to ${BACKUP_DIR}/"
fi

###############################################################################
# Upgrade Control Plane
###############################################################################

header "Upgrading EKS Control Plane: ${CURRENT_VERSION} -> ${TARGET_VERSION}"

if [[ "$ENVIRONMENT" == "prod" ]]; then
    warn "=== PRODUCTION UPGRADE ==="
    warn "This will upgrade the production EKS control plane."
    warn "The API server will remain available during the upgrade (rolling update)."
    warn "The upgrade typically takes 15-30 minutes."
    if ! confirm "Proceed with production control plane upgrade?"; then
        error "Upgrade cancelled by user."
    fi
fi

if [[ "$DRY_RUN" == "false" ]]; then
    log "Initiating control plane upgrade..."
    aws eks update-cluster-version \
        --name "$CLUSTER_NAME" \
        --kubernetes-version "$TARGET_VERSION" \
        2>&1 | tee -a "$LOG_FILE"

    log "Waiting for control plane upgrade to complete (this can take 15-30 minutes)..."
    aws eks wait cluster-active --name "$CLUSTER_NAME" 2>&1 | tee -a "$LOG_FILE"

    NEW_VERSION=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.version' --output text)
    log "Control plane upgraded successfully to version ${NEW_VERSION}"
else
    info "[DRY-RUN] Would run: aws eks update-cluster-version --name ${CLUSTER_NAME} --kubernetes-version ${TARGET_VERSION}"
    info "[DRY-RUN] Would wait for cluster to become active (15-30 minutes)"
fi

###############################################################################
# Upgrade Node Groups
###############################################################################

header "Upgrading Managed Node Groups"

NODE_GROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --query 'nodegroups[]' --output text 2>/dev/null || echo "")

if [[ -z "$NODE_GROUPS" ]]; then
    warn "No managed node groups found. If using self-managed nodes, upgrade them manually."
else
    for ng in $NODE_GROUPS; do
        log "Upgrading node group: ${ng}..."

        NG_VERSION=$(aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" --query 'nodegroup.version' --output text 2>/dev/null || echo "unknown")
        info "  Current version: ${NG_VERSION}"

        if [[ "$NG_VERSION" == "$TARGET_VERSION" ]]; then
            log "  Node group ${ng} is already at version ${TARGET_VERSION}. Skipping."
            continue
        fi

        if [[ "$DRY_RUN" == "false" ]]; then
            # Get the current launch template to determine if we need AMI update
            log "  Initiating node group upgrade for ${ng}..."
            aws eks update-nodegroup-version \
                --cluster-name "$CLUSTER_NAME" \
                --nodegroup-name "$ng" \
                --kubernetes-version "$TARGET_VERSION" \
                2>&1 | tee -a "$LOG_FILE"

            log "  Waiting for node group ${ng} upgrade to complete..."
            log "  (Nodes are replaced in a rolling fashion respecting PDBs and maxUnavailable)"
            aws eks wait nodegroup-active \
                --cluster-name "$CLUSTER_NAME" \
                --nodegroup-name "$ng" \
                2>&1 | tee -a "$LOG_FILE"

            log "  Node group ${ng} upgraded successfully."
        else
            info "  [DRY-RUN] Would upgrade node group ${ng} to ${TARGET_VERSION}"
        fi
    done
fi

###############################################################################
# Upgrade EKS Managed Addons
###############################################################################

header "Upgrading EKS Managed Addons"

# Core EKS addons that need version-compatible updates
EKS_ADDONS=("vpc-cni" "coredns" "kube-proxy")

for addon in "${EKS_ADDONS[@]}"; do
    log "Checking addon: ${addon}..."

    # Check if addon is installed
    ADDON_INSTALLED=$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon" 2>/dev/null && echo "yes" || echo "no")

    if [[ "$ADDON_INSTALLED" == "no" ]]; then
        info "  Addon ${addon} is not installed as an EKS managed addon. Skipping."
        continue
    fi

    # Get compatible versions
    LATEST_VERSION=$(aws eks describe-addon-versions \
        --addon-name "$addon" \
        --kubernetes-version "$TARGET_VERSION" \
        --query 'addons[0].addonVersions[0].addonVersion' \
        --output text 2>/dev/null || echo "unknown")

    CURRENT_ADDON_VERSION=$(aws eks describe-addon \
        --cluster-name "$CLUSTER_NAME" \
        --addon-name "$addon" \
        --query 'addon.addonVersion' \
        --output text 2>/dev/null || echo "unknown")

    info "  Current: ${CURRENT_ADDON_VERSION} -> Latest compatible: ${LATEST_VERSION}"

    if [[ "$CURRENT_ADDON_VERSION" == "$LATEST_VERSION" ]]; then
        log "  Addon ${addon} is already at the latest compatible version."
        continue
    fi

    if [[ "$DRY_RUN" == "false" ]]; then
        log "  Updating ${addon} to ${LATEST_VERSION}..."
        aws eks update-addon \
            --cluster-name "$CLUSTER_NAME" \
            --addon-name "$addon" \
            --addon-version "$LATEST_VERSION" \
            --resolve-conflicts OVERWRITE \
            2>&1 | tee -a "$LOG_FILE"

        log "  Waiting for addon ${addon} update..."
        aws eks wait addon-active \
            --cluster-name "$CLUSTER_NAME" \
            --addon-name "$addon" \
            2>&1 | tee -a "$LOG_FILE"

        log "  Addon ${addon} updated successfully."
    else
        info "  [DRY-RUN] Would update ${addon} from ${CURRENT_ADDON_VERSION} to ${LATEST_VERSION}"
    fi
done

###############################################################################
# Update Terraform Configuration
###############################################################################

header "Terraform Configuration Update"

log "Updating cluster_version in Terraform variables..."
TFVARS_FILE="${TERRAFORM_DIR}/${ENVIRONMENT}/variables.tf"

if [[ "$DRY_RUN" == "false" ]]; then
    # Update the default cluster version in variables.tf
    if grep -q "cluster_version" "$TFVARS_FILE"; then
        sed -i.bak "s/default *= *\"${CURRENT_VERSION}\"/default = \"${TARGET_VERSION}\"/" "$TFVARS_FILE"
        log "Updated cluster_version default to ${TARGET_VERSION} in ${TFVARS_FILE}"
        rm -f "${TFVARS_FILE}.bak"
    else
        warn "Could not find cluster_version in ${TFVARS_FILE}. Update manually."
    fi

    # Run terraform plan to verify
    log "Running terraform plan to verify configuration..."
    cd "${TERRAFORM_DIR}/${ENVIRONMENT}"
    terraform plan -out="${BACKUP_DIR}/upgrade-plan-${TIMESTAMP}.tfplan" 2>&1 | tail -20 | tee -a "$LOG_FILE"
    log "Terraform plan saved to ${BACKUP_DIR}/upgrade-plan-${TIMESTAMP}.tfplan"
else
    info "[DRY-RUN] Would update cluster_version from ${CURRENT_VERSION} to ${TARGET_VERSION} in ${TFVARS_FILE}"
    info "[DRY-RUN] Would run terraform plan to verify"
fi

###############################################################################
# Post-upgrade Validation
###############################################################################

header "Post-upgrade Validation"

if [[ "$DRY_RUN" == "false" ]]; then
    # Verify control plane version
    FINAL_VERSION=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.version' --output text)
    if [[ "$FINAL_VERSION" == "$TARGET_VERSION" ]]; then
        log "Control plane version verified: ${FINAL_VERSION}"
    else
        error "Control plane version mismatch! Expected ${TARGET_VERSION}, got ${FINAL_VERSION}"
    fi

    # Verify cluster status
    CLUSTER_STATUS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.status' --output text)
    if [[ "$CLUSTER_STATUS" == "ACTIVE" ]]; then
        log "Cluster status: ACTIVE"
    else
        error "Cluster status is ${CLUSTER_STATUS}, expected ACTIVE"
    fi

    # Verify node versions
    log "Node versions after upgrade:"
    kubectl get nodes -o custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion,STATUS:.status.conditions[-1:].type 2>/dev/null | tee -a "$LOG_FILE"

    # Check system pods
    log "Checking system pod health..."
    UNHEALTHY_PODS=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v "Running\|Completed" || true)
    if [[ -n "$UNHEALTHY_PODS" ]]; then
        warn "Unhealthy pods in kube-system:"
        echo "$UNHEALTHY_PODS" | tee -a "$LOG_FILE"
    else
        log "All kube-system pods are healthy."
    fi

    # Verify DNS resolution
    log "Testing DNS resolution..."
    kubectl run dns-test --image=busybox:1.36 --restart=Never --rm -it --command -- nslookup kubernetes.default 2>/dev/null | tee -a "$LOG_FILE" || warn "DNS test failed or timed out."

    # Check API server connectivity
    log "Testing API server connectivity..."
    kubectl cluster-info 2>/dev/null | head -3 | tee -a "$LOG_FILE" || warn "Could not get cluster info."
else
    info "[DRY-RUN] Would perform post-upgrade validation:"
    info "  - Verify control plane version"
    info "  - Check node versions"
    info "  - Verify system pod health"
    info "  - Test DNS resolution"
    info "  - Test API server connectivity"
fi

###############################################################################
# Summary
###############################################################################

header "Upgrade Summary"

if [[ "$DRY_RUN" == "true" ]]; then
    info "=== DRY RUN COMPLETE ==="
    info "No changes were made."
    info ""
    info "Planned actions:"
    info "  1. Backup Terraform state"
    info "  2. Upgrade control plane: ${CURRENT_VERSION} -> ${TARGET_VERSION}"
    info "  3. Upgrade node groups: ${NODE_GROUPS:-none found}"
    info "  4. Update EKS addons: ${EKS_ADDONS[*]}"
    info "  5. Update Terraform configuration"
    info "  6. Run post-upgrade validation"
else
    log "=== UPGRADE COMPLETE ==="
    log "Cluster: ${CLUSTER_NAME}"
    log "Version: ${CURRENT_VERSION} -> ${TARGET_VERSION}"
    log "State backup: ${BACKUP_DIR}/"
    log "Full log: ${LOG_FILE}"
    echo ""
    warn "NEXT STEPS:"
    warn "  1. Verify application health and functionality"
    warn "  2. Run integration/smoke tests"
    warn "  3. Monitor metrics and logs for the next 24 hours"
    warn "  4. Commit the updated Terraform variables to git"
    if [[ "$ENVIRONMENT" != "prod" ]]; then
        warn "  5. After validation, proceed with upgrading the next environment"
    fi
fi

echo ""
log "Rollback guidance:"
info "  - EKS control plane CANNOT be downgraded once upgraded"
info "  - Node groups can be rolled back by updating the launch template AMI"
info "  - Addons can be downgraded to previous compatible versions"
info "  - Restore Terraform state from: ${BACKUP_DIR}/"
info "  - For critical issues, create a new cluster at the previous version and migrate"
echo ""
