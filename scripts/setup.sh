#!/bin/bash
# ==============================================================================
# setup.sh - Bootstrap script for Terraform EKS project
#
# Installs and verifies all required tools:
#   terraform, kubectl, helm, awscli, tflint, tfsec, checkov, pre-commit,
#   terraform-docs, infracost
#
# Usage:
#   bash scripts/setup.sh
# ==============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

log_info()  { printf "${CYAN}[INFO]${RESET}  %s\n" "$1"; }
log_ok()    { printf "${GREEN}[OK]${RESET}    %s\n" "$1"; }
log_warn()  { printf "${YELLOW}[WARN]${RESET}  %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${RESET} %s\n" "$1"; }

# Detect OS
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Darwin) PLATFORM="darwin" ;;
  Linux)  PLATFORM="linux" ;;
  *)      log_error "Unsupported OS: $OS"; exit 1 ;;
esac

case "$ARCH" in
  x86_64)  ARCH_LABEL="amd64" ;;
  arm64|aarch64) ARCH_LABEL="arm64" ;;
  *)       log_error "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# --------------------------------------------------------------------------
# Tool check / install functions
# --------------------------------------------------------------------------

check_command() {
  local cmd="$1"
  local name="${2:-$cmd}"
  if command -v "$cmd" &>/dev/null; then
    local version
    version=$("$cmd" version 2>/dev/null | head -1 || "$cmd" --version 2>/dev/null | head -1 || echo "installed")
    log_ok "$name is installed: $version"
    return 0
  else
    log_warn "$name is NOT installed"
    return 1
  fi
}

install_terraform() {
  local version="1.6.6"
  log_info "Installing Terraform v${version}..."
  if [[ "$PLATFORM" == "darwin" ]]; then
    brew tap hashicorp/tap 2>/dev/null || true
    brew install hashicorp/tap/terraform
  else
    curl -fsSL "https://releases.hashicorp.com/terraform/${version}/terraform_${version}_${PLATFORM}_${ARCH_LABEL}.zip" -o /tmp/terraform.zip
    unzip -o /tmp/terraform.zip -d /tmp/
    sudo mv /tmp/terraform /usr/local/bin/terraform
    rm -f /tmp/terraform.zip
  fi
}

install_kubectl() {
  log_info "Installing kubectl..."
  if [[ "$PLATFORM" == "darwin" ]]; then
    brew install kubectl
  else
    local version
    version=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
    curl -fsSL "https://dl.k8s.io/release/${version}/bin/${PLATFORM}/${ARCH_LABEL}/kubectl" -o /tmp/kubectl
    sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
    rm -f /tmp/kubectl
  fi
}

install_helm() {
  log_info "Installing Helm..."
  if [[ "$PLATFORM" == "darwin" ]]; then
    brew install helm
  else
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi
}

install_awscli() {
  log_info "Installing AWS CLI v2..."
  if [[ "$PLATFORM" == "darwin" ]]; then
    brew install awscli
  else
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscliv2.zip
    unzip -o /tmp/awscliv2.zip -d /tmp/
    sudo /tmp/aws/install --update
    rm -rf /tmp/aws /tmp/awscliv2.zip
  fi
}

install_tflint() {
  log_info "Installing tflint..."
  if [[ "$PLATFORM" == "darwin" ]]; then
    brew install tflint
  else
    curl -fsSL https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
  fi
}

install_tfsec() {
  log_info "Installing tfsec..."
  if [[ "$PLATFORM" == "darwin" ]]; then
    brew install tfsec
  else
    curl -fsSL "https://github.com/aquasecurity/tfsec/releases/latest/download/tfsec-${PLATFORM}-${ARCH_LABEL}" -o /tmp/tfsec
    sudo install -o root -g root -m 0755 /tmp/tfsec /usr/local/bin/tfsec
    rm -f /tmp/tfsec
  fi
}

install_checkov() {
  log_info "Installing checkov..."
  pip3 install --upgrade checkov
}

install_precommit() {
  log_info "Installing pre-commit..."
  pip3 install --upgrade pre-commit
}

install_terraform_docs() {
  log_info "Installing terraform-docs..."
  if [[ "$PLATFORM" == "darwin" ]]; then
    brew install terraform-docs
  else
    curl -fsSL "https://terraform-docs.io/dl/v0.17.0/terraform-docs-v0.17.0-${PLATFORM}-${ARCH_LABEL}.tar.gz" -o /tmp/terraform-docs.tar.gz
    tar -xzf /tmp/terraform-docs.tar.gz -C /tmp/
    sudo mv /tmp/terraform-docs /usr/local/bin/terraform-docs
    rm -f /tmp/terraform-docs.tar.gz
  fi
}

install_infracost() {
  log_info "Installing infracost..."
  if [[ "$PLATFORM" == "darwin" ]]; then
    brew install infracost
  else
    curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh
  fi
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

printf "\n${CYAN}============================================${RESET}\n"
printf "${CYAN} Terraform EKS Project - Tool Setup${RESET}\n"
printf "${CYAN}============================================${RESET}\n\n"

printf "Platform: ${PLATFORM}/${ARCH_LABEL}\n\n"

TOOLS=(
  "terraform:install_terraform"
  "kubectl:install_kubectl"
  "helm:install_helm"
  "aws:install_awscli"
  "tflint:install_tflint"
  "tfsec:install_tfsec"
  "checkov:install_checkov"
  "pre-commit:install_precommit"
  "terraform-docs:install_terraform_docs"
  "infracost:install_infracost"
)

MISSING=()

log_info "Checking installed tools..."
printf "\n"

for entry in "${TOOLS[@]}"; do
  cmd="${entry%%:*}"
  installer="${entry##*:}"
  if ! check_command "$cmd"; then
    MISSING+=("$cmd:$installer")
  fi
done

printf "\n"

if [[ ${#MISSING[@]} -eq 0 ]]; then
  log_ok "All tools are already installed!"
else
  log_warn "${#MISSING[@]} tool(s) missing. Installing..."
  printf "\n"

  for entry in "${MISSING[@]}"; do
    cmd="${entry%%:*}"
    installer="${entry##*:}"
    $installer
    printf "\n"
  done

  # Verify everything is now installed
  printf "\n"
  log_info "Verifying installations..."
  printf "\n"
  ALL_OK=true
  for entry in "${TOOLS[@]}"; do
    cmd="${entry%%:*}"
    if ! check_command "$cmd"; then
      ALL_OK=false
    fi
  done

  if $ALL_OK; then
    log_ok "All tools installed successfully!"
  else
    log_error "Some tools could not be installed. Check the output above."
    exit 1
  fi
fi

# Install pre-commit hooks if .pre-commit-config.yaml exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [[ -f "$PROJECT_ROOT/.pre-commit-config.yaml" ]]; then
  printf "\n"
  log_info "Installing pre-commit hooks..."
  cd "$PROJECT_ROOT" && pre-commit install
  log_ok "Pre-commit hooks installed"
fi

printf "\n${GREEN}Setup complete!${RESET}\n\n"
