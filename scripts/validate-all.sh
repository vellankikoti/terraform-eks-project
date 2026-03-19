#!/bin/bash
# ==============================================================================
# validate-all.sh - Run full validation suite across all environments
#
# Checks:
#   1. terraform fmt  - Verify formatting
#   2. terraform validate - Verify HCL syntax and configuration
#   3. tflint - Lint for best practices and common errors
#
# Usage:
#   bash scripts/validate-all.sh
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
log_step()  { printf "\n${BOLD}${CYAN}--- %s ---${RESET}\n\n" "$1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="$PROJECT_ROOT/terraform"
ENVIRONMENTS=(dev staging prod)

ERRORS=0

printf "\n${BOLD}${CYAN}============================================${RESET}\n"
printf "${BOLD}${CYAN} Terraform Validation Suite${RESET}\n"
printf "${BOLD}${CYAN}============================================${RESET}\n"

# --------------------------------------------------------------------------
# Step 1: Format check
# --------------------------------------------------------------------------

log_step "Step 1/3: Terraform Format Check"

if ! command -v terraform &>/dev/null; then
  log_error "terraform is not installed. Run: make setup"
  exit 1
fi

FMT_OUTPUT=$(terraform fmt -check -recursive "$TF_DIR" 2>&1) || true

if [[ -z "$FMT_OUTPUT" ]]; then
  log_ok "All files are properly formatted"
else
  log_error "The following files need formatting:"
  printf "%s\n" "$FMT_OUTPUT" | while read -r file; do
    printf "  ${RED}->  %s${RESET}\n" "$file"
  done
  printf "\n"
  log_info "Run 'make fmt' to fix formatting"
  ERRORS=$((ERRORS + 1))
fi

# --------------------------------------------------------------------------
# Step 2: Terraform validate
# --------------------------------------------------------------------------

log_step "Step 2/3: Terraform Validate"

for env in "${ENVIRONMENTS[@]}"; do
  ENV_DIR="$TF_DIR/environments/$env"

  if [[ ! -d "$ENV_DIR" ]]; then
    log_warn "Environment directory not found: $env (skipping)"
    continue
  fi

  printf "  ${CYAN}Validating ${env}...${RESET} "

  # Initialize with no backend to allow validation without credentials
  INIT_OUTPUT=$(cd "$ENV_DIR" && terraform init -backend=false -input=false 2>&1) || {
    printf "${RED}INIT FAILED${RESET}\n"
    printf "    %s\n" "$INIT_OUTPUT"
    ERRORS=$((ERRORS + 1))
    continue
  }

  VALIDATE_OUTPUT=$(cd "$ENV_DIR" && terraform validate 2>&1) || {
    printf "${RED}FAILED${RESET}\n"
    printf "    %s\n" "$VALIDATE_OUTPUT"
    ERRORS=$((ERRORS + 1))
    continue
  }

  printf "${GREEN}PASSED${RESET}\n"
done

# --------------------------------------------------------------------------
# Step 3: tflint
# --------------------------------------------------------------------------

log_step "Step 3/3: TFLint"

if ! command -v tflint &>/dev/null; then
  log_warn "tflint is not installed -- skipping lint checks"
  log_info "Run 'make setup' to install all tools"
else
  for env in "${ENVIRONMENTS[@]}"; do
    ENV_DIR="$TF_DIR/environments/$env"

    if [[ ! -d "$ENV_DIR" ]]; then
      continue
    fi

    printf "  ${CYAN}Linting ${env}...${RESET} "

    # Initialize tflint plugins
    (cd "$ENV_DIR" && tflint --init 2>/dev/null) || true

    LINT_OUTPUT=$(cd "$ENV_DIR" && tflint 2>&1) || {
      printf "${YELLOW}WARNINGS${RESET}\n"
      printf "    %s\n" "$LINT_OUTPUT"
      continue
    }

    if [[ -z "$LINT_OUTPUT" ]]; then
      printf "${GREEN}PASSED${RESET}\n"
    else
      printf "${YELLOW}WARNINGS${RESET}\n"
      printf "    %s\n" "$LINT_OUTPUT"
    fi
  done
fi

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------

printf "\n${BOLD}${CYAN}============================================${RESET}\n"
printf "${BOLD}${CYAN} Summary${RESET}\n"
printf "${BOLD}${CYAN}============================================${RESET}\n\n"

if [[ $ERRORS -eq 0 ]]; then
  log_ok "All validation checks passed!"
  printf "\n"
  exit 0
else
  log_error "$ERRORS validation check(s) failed"
  printf "\n"
  exit 1
fi
