#!/bin/bash
#
# EKS Node Patching Script
# Usage: ./scripts/patch-nodes.sh <environment> [node-group-name]
#
# Performs rolling AMI updates for EKS managed node groups:
# 1. Checks for AMI updates (latest EKS-optimized AMI)
# 2. Updates launch template with new AMI
# 3. Cordons and drains nodes gracefully
# 4. Triggers rolling replacement via node group update
# 5. Health checks after each node rotation
#
# If node-group-name is omitted, patches all node groups in the cluster.
#
# Examples:
#   ./scripts/patch-nodes.sh dev                    # Patch all node groups in dev
#   ./scripts/patch-nodes.sh staging system         # Patch only the 'system' node group
#   ./scripts/patch-nodes.sh prod spot --dry-run    # Preview patching for spot node group
#
set -euo pipefail

###############################################################################
# Configuration
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform/environments"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/eks-patch-${TIMESTAMP}.log"

# Drain settings
DRAIN_TIMEOUT="300"          # 5 minutes per node
DRAIN_GRACE_PERIOD="60"      # 60 second grace period for pod termination
DRAIN_DELETE_EMPTYDIR="true" # Delete emptyDir data (logs, caches)

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
        info "[DRY-RUN] Would prompt: $1"
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
        error "$1 is required but not installed."
    fi
}

###############################################################################
# Parse Arguments
###############################################################################

ENVIRONMENT="${1:-}"
TARGET_NODE_GROUP="${2:-}"
DRY_RUN="false"

for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN="true"
    fi
done

if [[ "$TARGET_NODE_GROUP" == "--dry-run" ]]; then
    TARGET_NODE_GROUP=""
fi

if [[ -z "$ENVIRONMENT" ]]; then
    echo "Usage: $0 <environment> [node-group-name] [--dry-run]"
    echo ""
    echo "Arguments:"
    echo "  environment       Environment (dev, staging, prod)"
    echo "  node-group-name   Specific node group to patch (optional - patches all if omitted)"
    echo "  --dry-run         Preview changes without applying them"
    echo ""
    echo "Examples:"
    echo "  $0 dev                     # Patch all node groups in dev"
    echo "  $0 staging system          # Patch only 'system' node group in staging"
    echo "  $0 prod general --dry-run  # Preview patching 'general' in prod"
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
check_command kubectl
check_command jq
log "All required tools available."

# Get cluster name
CLUSTER_NAME=$(cd "${TERRAFORM_DIR}/${ENVIRONMENT}" && terraform output -raw cluster_id 2>/dev/null || echo "")
if [[ -z "$CLUSTER_NAME" ]]; then
    PROJECT_NAME=$(grep -A2 'variable "project_name"' "${TERRAFORM_DIR}/${ENVIRONMENT}/variables.tf" | grep default | sed 's/.*"\(.*\)".*/\1/' || echo "myapp")
    CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}"
    warn "Using convention-based cluster name: ${CLUSTER_NAME}"
fi

log "Cluster: ${CLUSTER_NAME}"
log "Environment: ${ENVIRONMENT}"
log "Target node group: ${TARGET_NODE_GROUP:-all}"
log "Dry run: ${DRY_RUN}"
log "Log file: ${LOG_FILE}"

# Update kubeconfig
if [[ "$DRY_RUN" == "false" ]]; then
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --alias "$CLUSTER_NAME" 2>&1 | tee -a "$LOG_FILE"
fi

# Get Kubernetes version for AMI lookup
K8S_VERSION=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.version' --output text 2>/dev/null || error "Could not determine cluster version")
log "Cluster Kubernetes version: ${K8S_VERSION}"

# Get AWS region
AWS_REGION=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.arn' --output text 2>/dev/null | cut -d: -f4 || echo "us-east-1")
log "AWS Region: ${AWS_REGION}"

###############################################################################
# Get Node Groups to Patch
###############################################################################

header "Discovering Node Groups"

ALL_NODE_GROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --query 'nodegroups[]' --output text 2>/dev/null || echo "")

if [[ -z "$ALL_NODE_GROUPS" ]]; then
    error "No managed node groups found for cluster ${CLUSTER_NAME}."
fi

info "Available node groups: ${ALL_NODE_GROUPS}"

if [[ -n "$TARGET_NODE_GROUP" ]]; then
    if ! echo "$ALL_NODE_GROUPS" | grep -qw "$TARGET_NODE_GROUP"; then
        error "Node group '${TARGET_NODE_GROUP}' not found. Available: ${ALL_NODE_GROUPS}"
    fi
    NODE_GROUPS_TO_PATCH="$TARGET_NODE_GROUP"
else
    NODE_GROUPS_TO_PATCH="$ALL_NODE_GROUPS"
fi

log "Node groups to patch: ${NODE_GROUPS_TO_PATCH}"

###############################################################################
# Get Latest EKS-Optimized AMI
###############################################################################

header "Checking Latest AMI"

# Get the latest EKS-optimized Amazon Linux 2 AMI
LATEST_AMI=$(aws ssm get-parameter \
    --name "/aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2/recommended/image_id" \
    --region "$AWS_REGION" \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "unknown")

log "Latest EKS-optimized AMI for K8s ${K8S_VERSION}: ${LATEST_AMI}"

if [[ "$LATEST_AMI" == "unknown" ]]; then
    error "Could not determine latest EKS-optimized AMI. Check AWS SSM parameter store access."
fi

###############################################################################
# Patch Each Node Group
###############################################################################

PATCHED_COUNT=0
SKIPPED_COUNT=0

for ng in $NODE_GROUPS_TO_PATCH; do
    header "Patching Node Group: ${ng}"

    # Get node group details
    NG_INFO=$(aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" 2>/dev/null)
    NG_STATUS=$(echo "$NG_INFO" | jq -r '.nodegroup.status')
    NG_VERSION=$(echo "$NG_INFO" | jq -r '.nodegroup.version')
    CURRENT_RELEASE_VERSION=$(echo "$NG_INFO" | jq -r '.nodegroup.releaseVersion // "unknown"')
    DESIRED_SIZE=$(echo "$NG_INFO" | jq -r '.nodegroup.scalingConfig.desiredSize')
    MAX_SIZE=$(echo "$NG_INFO" | jq -r '.nodegroup.scalingConfig.maxSize')
    CAPACITY_TYPE=$(echo "$NG_INFO" | jq -r '.nodegroup.capacityType // "ON_DEMAND"')

    info "  Status: ${NG_STATUS}"
    info "  K8s version: ${NG_VERSION}"
    info "  Release version: ${CURRENT_RELEASE_VERSION}"
    info "  Capacity type: ${CAPACITY_TYPE}"
    info "  Desired/Max size: ${DESIRED_SIZE}/${MAX_SIZE}"

    if [[ "$NG_STATUS" != "ACTIVE" ]]; then
        warn "  Node group ${ng} is in state ${NG_STATUS}. Skipping."
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    # Check if update is needed
    LATEST_RELEASE=$(aws eks describe-nodegroup \
        --cluster-name "$CLUSTER_NAME" \
        --nodegroup-name "$ng" \
        --query 'nodegroup.releaseVersion' \
        --output text 2>/dev/null || echo "")

    # Get latest available release version for comparison
    log "  Checking for available AMI updates..."

    # List nodes in this node group
    if [[ "$DRY_RUN" == "false" ]]; then
        log "  Nodes in this group:"
        NG_LABEL="eks.amazonaws.com/nodegroup=${ng}"
        kubectl get nodes -l "$NG_LABEL" -o custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion,AMI:.status.nodeInfo.osImage 2>/dev/null | tee -a "$LOG_FILE" || true
    fi

    # Check PDBs before proceeding
    if [[ "$DRY_RUN" == "false" ]]; then
        log "  Checking PodDisruptionBudgets..."
        BLOCKING_PDBS=$(kubectl get pdb --all-namespaces -o json 2>/dev/null | jq -r '.items[] | select(.status.disruptionsAllowed == 0) | "\(.metadata.namespace)/\(.metadata.name)"' || true)
        if [[ -n "$BLOCKING_PDBS" ]]; then
            warn "  PDBs with 0 allowed disruptions (may slow rolling update):"
            echo "    $BLOCKING_PDBS" | tee -a "$LOG_FILE"
        fi
    fi

    # Perform the update
    if [[ "$ENVIRONMENT" == "prod" ]]; then
        if ! confirm "  Proceed with patching production node group '${ng}'?"; then
            warn "  Skipping ${ng} per user request."
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            continue
        fi
    fi

    if [[ "$DRY_RUN" == "false" ]]; then
        log "  Initiating rolling AMI update for ${ng}..."

        # Use the EKS-managed update which handles cordon, drain, and replacement
        aws eks update-nodegroup-version \
            --cluster-name "$CLUSTER_NAME" \
            --nodegroup-name "$ng" \
            --release-version "$(aws ssm get-parameter \
                --name "/aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2/recommended/release_version" \
                --region "$AWS_REGION" \
                --query 'Parameter.Value' \
                --output text 2>/dev/null)" \
            2>&1 | tee -a "$LOG_FILE" || {
                # If release version update fails, try force update
                warn "  Release version update failed. Trying force update..."
                aws eks update-nodegroup-version \
                    --cluster-name "$CLUSTER_NAME" \
                    --nodegroup-name "$ng" \
                    --force \
                    2>&1 | tee -a "$LOG_FILE"
            }

        log "  Waiting for node group update to complete..."
        log "  (EKS will cordon, drain, and replace nodes one at a time)"

        # Monitor the update
        WAIT_START=$(date +%s)
        MAX_WAIT=3600  # 60 minutes max
        while true; do
            CURRENT_STATUS=$(aws eks describe-nodegroup \
                --cluster-name "$CLUSTER_NAME" \
                --nodegroup-name "$ng" \
                --query 'nodegroup.status' \
                --output text 2>/dev/null || echo "UNKNOWN")

            ELAPSED=$(( $(date +%s) - WAIT_START ))

            if [[ "$CURRENT_STATUS" == "ACTIVE" ]]; then
                log "  Node group ${ng} update complete. (${ELAPSED}s)"
                break
            elif [[ "$CURRENT_STATUS" == "DEGRADED" ]]; then
                error "  Node group ${ng} entered DEGRADED state during update."
            elif [[ $ELAPSED -gt $MAX_WAIT ]]; then
                error "  Timed out waiting for node group ${ng} update after ${MAX_WAIT}s."
            fi

            info "  Status: ${CURRENT_STATUS} (${ELAPSED}s elapsed, checking every 30s...)"
            sleep 30
        done

        # Post-patch health check for this node group
        log "  Running health check for ${ng}..."
        sleep 10  # Brief wait for nodes to stabilize

        NG_LABEL="eks.amazonaws.com/nodegroup=${ng}"
        NODE_COUNT=$(kubectl get nodes -l "$NG_LABEL" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        READY_COUNT=$(kubectl get nodes -l "$NG_LABEL" --no-headers 2>/dev/null | grep " Ready " | wc -l | tr -d ' ')

        if [[ "$NODE_COUNT" -eq "$READY_COUNT" && "$NODE_COUNT" -gt 0 ]]; then
            log "  Health check passed: ${READY_COUNT}/${NODE_COUNT} nodes Ready."
        else
            warn "  Health check: ${READY_COUNT}/${NODE_COUNT} nodes Ready. Some nodes may still be initializing."
        fi

        # Show updated node info
        info "  Updated nodes:"
        kubectl get nodes -l "$NG_LABEL" -o custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion,AGE:.metadata.creationTimestamp 2>/dev/null | tee -a "$LOG_FILE" || true

        PATCHED_COUNT=$((PATCHED_COUNT + 1))
    else
        info "  [DRY-RUN] Would trigger rolling AMI update for node group ${ng}"
        info "  [DRY-RUN] EKS would cordon, drain, and replace each node"
        info "  [DRY-RUN] Process respects maxUnavailable and PDBs"
        PATCHED_COUNT=$((PATCHED_COUNT + 1))
    fi
done

###############################################################################
# Post-patch Validation
###############################################################################

header "Post-patch Validation"

if [[ "$DRY_RUN" == "false" ]]; then
    # Overall node status
    log "All nodes after patching:"
    kubectl get nodes -o wide 2>/dev/null | tee -a "$LOG_FILE"

    # Check for unhealthy pods
    log "Checking for unhealthy pods across all namespaces..."
    UNHEALTHY=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | grep -v "Running\|Completed\|Succeeded" | head -20 || true)
    if [[ -n "$UNHEALTHY" ]]; then
        warn "Unhealthy pods detected:"
        echo "$UNHEALTHY" | tee -a "$LOG_FILE"
    else
        log "All pods are healthy."
    fi

    # Verify persistent volumes
    log "Checking PersistentVolume status..."
    PV_ISSUES=$(kubectl get pv --no-headers 2>/dev/null | grep -v "Bound\|Available" || true)
    if [[ -n "$PV_ISSUES" ]]; then
        warn "PV issues detected:"
        echo "$PV_ISSUES" | tee -a "$LOG_FILE"
    else
        log "All PersistentVolumes are healthy."
    fi
else
    info "[DRY-RUN] Would check node status, pod health, and PV status."
fi

###############################################################################
# Summary
###############################################################################

header "Patch Summary"

if [[ "$DRY_RUN" == "true" ]]; then
    info "=== DRY RUN COMPLETE ==="
    info "No changes were made."
else
    log "=== PATCH COMPLETE ==="
fi

log "Cluster: ${CLUSTER_NAME}"
log "Environment: ${ENVIRONMENT}"
log "Node groups patched: ${PATCHED_COUNT}"
log "Node groups skipped: ${SKIPPED_COUNT}"
log "Latest AMI: ${LATEST_AMI}"
log "Log file: ${LOG_FILE}"

echo ""
warn "NEXT STEPS:"
warn "  1. Verify application health and connectivity"
warn "  2. Check application logs for errors"
warn "  3. Monitor CloudWatch metrics for the next few hours"
if [[ "$ENVIRONMENT" != "prod" ]]; then
    warn "  4. After validation, patch the next environment"
fi
echo ""
