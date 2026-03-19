#!/bin/bash
# ==============================================================================
# cost-estimate.sh - Run infracost cost estimation for all environments
#
# Requires:
#   - infracost CLI installed (https://www.infracost.io/)
#   - INFRACOST_API_KEY environment variable set
#
# Usage:
#   bash scripts/cost-estimate.sh
#   bash scripts/cost-estimate.sh dev          # single environment
# ==============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log_info()  { printf "${CYAN}[INFO]${RESET}  %s\n" "$1"; }
log_ok()    { printf "${GREEN}[OK]${RESET}    %s\n" "$1"; }
log_warn()  { printf "${YELLOW}[WARN]${RESET}  %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${RESET} %s\n" "$1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="$PROJECT_ROOT/terraform"

# Environments to estimate (accept optional argument)
if [[ $# -gt 0 ]]; then
  ENVIRONMENTS=("$@")
else
  ENVIRONMENTS=(dev staging prod)
fi

# --------------------------------------------------------------------------
# Preflight checks
# --------------------------------------------------------------------------

if ! command -v infracost &>/dev/null; then
  log_error "infracost is not installed. Run: make setup"
  exit 1
fi

if [[ -z "${INFRACOST_API_KEY:-}" ]]; then
  log_warn "INFRACOST_API_KEY is not set."
  log_info "Get a free API key at https://www.infracost.io/docs/"
  log_info "Then run: export INFRACOST_API_KEY=<your-key>"
  log_info ""
  log_info "Attempting to continue (may fail if not already authenticated)..."
fi

# --------------------------------------------------------------------------
# Run cost estimation per environment
# --------------------------------------------------------------------------

printf "\n${BOLD}${CYAN}============================================${RESET}\n"
printf "${BOLD}${CYAN} Infracost - Cost Estimation${RESET}\n"
printf "${BOLD}${CYAN}============================================${RESET}\n\n"

BREAKDOWN_FILES=()
TMPDIR_COST=$(mktemp -d)
trap "rm -rf $TMPDIR_COST" EXIT

for env in "${ENVIRONMENTS[@]}"; do
  ENV_DIR="$TF_DIR/environments/$env"

  if [[ ! -d "$ENV_DIR" ]]; then
    log_warn "Environment directory not found: $ENV_DIR (skipping)"
    continue
  fi

  log_info "Estimating costs for: $env"

  OUTPUT_FILE="$TMPDIR_COST/${env}.json"

  infracost breakdown \
    --path "$ENV_DIR" \
    --format json \
    --out-file "$OUTPUT_FILE" \
    2>/dev/null || {
      log_warn "Cost estimation failed for $env (backend may not be configured)"
      continue
    }

  BREAKDOWN_FILES+=("$OUTPUT_FILE")

  # Show individual environment summary
  printf "\n${BOLD}--- $env ---${RESET}\n"
  infracost output \
    --path "$OUTPUT_FILE" \
    --format table \
    2>/dev/null || true
  printf "\n"
done

# --------------------------------------------------------------------------
# Combined summary (if multiple environments were estimated)
# --------------------------------------------------------------------------

if [[ ${#BREAKDOWN_FILES[@]} -gt 1 ]]; then
  printf "\n${BOLD}${CYAN}============================================${RESET}\n"
  printf "${BOLD}${CYAN} Combined Cost Summary${RESET}\n"
  printf "${BOLD}${CYAN}============================================${RESET}\n\n"

  # Build --path arguments
  PATH_ARGS=()
  for f in "${BREAKDOWN_FILES[@]}"; do
    PATH_ARGS+=(--path "$f")
  done

  infracost output \
    "${PATH_ARGS[@]}" \
    --format table \
    2>/dev/null || log_warn "Could not generate combined summary"
fi

printf "\n"
log_ok "Cost estimation complete"
printf "\n"
