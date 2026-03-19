# ==============================================================================
# Terraform EKS Project - Makefile
# ==============================================================================
#
# Usage:
#   make help          Show all available targets
#   make plan-dev      Plan the dev environment
#   make apply-dev     Apply the dev environment
#
# ==============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Colors for terminal output
RED    := \033[0;31m
GREEN  := \033[0;32m
YELLOW := \033[0;33m
BLUE   := \033[0;34m
CYAN   := \033[0;36m
RESET  := \033[0m

# Paths
TF_DIR        := terraform
ENVIRONMENTS  := dev staging prod
SCRIPTS_DIR   := scripts

# ==============================================================================
# Helper Functions
# ==============================================================================

define log_info
	@printf "$(CYAN)[INFO]$(RESET)  %s\n" "$(1)"
endef

define log_ok
	@printf "$(GREEN)[OK]$(RESET)    %s\n" "$(1)"
endef

define log_warn
	@printf "$(YELLOW)[WARN]$(RESET)  %s\n" "$(1)"
endef

define log_error
	@printf "$(RED)[ERROR]$(RESET) %s\n" "$(1)"
endef

# ==============================================================================
# Init Targets
# ==============================================================================

.PHONY: init-dev
init-dev: ## Initialize the dev environment
	$(call log_info,Initializing dev environment...)
	@cd $(TF_DIR)/environments/dev && terraform init
	$(call log_ok,Dev environment initialized)

.PHONY: init-staging
init-staging: ## Initialize the staging environment
	$(call log_info,Initializing staging environment...)
	@cd $(TF_DIR)/environments/staging && terraform init
	$(call log_ok,Staging environment initialized)

.PHONY: init-prod
init-prod: ## Initialize the prod environment
	$(call log_info,Initializing prod environment...)
	@cd $(TF_DIR)/environments/prod && terraform init
	$(call log_ok,Prod environment initialized)

.PHONY: init-all
init-all: init-dev init-staging init-prod ## Initialize all environments

# ==============================================================================
# Plan Targets
# ==============================================================================

.PHONY: plan-dev
plan-dev: ## Plan the dev environment
	$(call log_info,Planning dev environment...)
	@cd $(TF_DIR)/environments/dev && terraform plan -out=tfplan
	$(call log_ok,Dev plan complete. Review the output above.)

.PHONY: plan-staging
plan-staging: ## Plan the staging environment
	$(call log_info,Planning staging environment...)
	@cd $(TF_DIR)/environments/staging && terraform plan -out=tfplan
	$(call log_ok,Staging plan complete. Review the output above.)

.PHONY: plan-prod
plan-prod: ## Plan the prod environment
	$(call log_warn,Planning PRODUCTION environment -- review carefully!)
	@cd $(TF_DIR)/environments/prod && terraform plan -out=tfplan
	$(call log_ok,Prod plan complete. Review the output above.)

# ==============================================================================
# Apply Targets
# ==============================================================================

.PHONY: apply-dev
apply-dev: ## Apply the dev environment
	$(call log_info,Applying dev environment...)
	@cd $(TF_DIR)/environments/dev && terraform apply
	$(call log_ok,Dev apply complete)

.PHONY: apply-staging
apply-staging: ## Apply the staging environment
	$(call log_warn,Applying STAGING environment...)
	@cd $(TF_DIR)/environments/staging && terraform apply
	$(call log_ok,Staging apply complete)

.PHONY: apply-prod
apply-prod: ## Apply the PRODUCTION environment (requires confirmation)
	$(call log_error,You are about to apply to PRODUCTION!)
	@printf "$(RED)Type 'yes-apply-prod' to continue: $(RESET)" && \
		read confirm && \
		if [ "$$confirm" = "yes-apply-prod" ]; then \
			cd $(TF_DIR)/environments/prod && terraform apply; \
		else \
			printf "$(YELLOW)Aborted.$(RESET)\n"; \
			exit 1; \
		fi
	$(call log_ok,Prod apply complete)

# ==============================================================================
# Destroy Targets
# ==============================================================================

.PHONY: destroy-dev
destroy-dev: ## Destroy the dev environment
	$(call log_warn,Destroying dev environment...)
	@cd $(TF_DIR)/environments/dev && terraform destroy
	$(call log_ok,Dev environment destroyed)

.PHONY: destroy-staging
destroy-staging: ## Destroy the staging environment
	$(call log_warn,Destroying staging environment...)
	@cd $(TF_DIR)/environments/staging && terraform destroy
	$(call log_ok,Staging environment destroyed)

.PHONY: destroy-prod
destroy-prod: ## Destroy the PRODUCTION environment (requires confirmation)
	$(call log_error,You are about to DESTROY PRODUCTION!)
	@printf "$(RED)Type 'yes-destroy-prod' to continue: $(RESET)" && \
		read confirm && \
		if [ "$$confirm" = "yes-destroy-prod" ]; then \
			cd $(TF_DIR)/environments/prod && terraform destroy; \
		else \
			printf "$(YELLOW)Aborted.$(RESET)\n"; \
			exit 1; \
		fi

# ==============================================================================
# Quality & Security Targets
# ==============================================================================

.PHONY: fmt
fmt: ## Format all Terraform files
	$(call log_info,Formatting Terraform files...)
	@terraform fmt -recursive $(TF_DIR)/
	$(call log_ok,Formatting complete)

.PHONY: validate
validate: ## Validate all environments (no backend required)
	$(call log_info,Validating all environments...)
	@for env in $(ENVIRONMENTS); do \
		printf "$(CYAN)  -> Validating $$env...$(RESET)\n"; \
		cd $(TF_DIR)/environments/$$env && terraform init -backend=false -input=false > /dev/null 2>&1 && terraform validate && cd - > /dev/null; \
	done
	$(call log_ok,All environments valid)

.PHONY: lint
lint: ## Run tflint on all environments
	$(call log_info,Running tflint...)
	@for env in $(ENVIRONMENTS); do \
		printf "$(CYAN)  -> Linting $$env...$(RESET)\n"; \
		cd $(TF_DIR)/environments/$$env && tflint --init > /dev/null 2>&1 && tflint && cd - > /dev/null; \
	done
	$(call log_ok,Lint complete)

.PHONY: security-scan
security-scan: ## Run tfsec and checkov security scans
	$(call log_info,Running tfsec...)
	@tfsec $(TF_DIR)/ || true
	@printf "\n"
	$(call log_info,Running checkov...)
	@checkov -d $(TF_DIR)/ --framework terraform --compact --quiet || true
	$(call log_ok,Security scan complete)

.PHONY: cost-estimate
cost-estimate: ## Run infracost cost estimation for all environments
	$(call log_info,Running cost estimation...)
	@bash $(SCRIPTS_DIR)/cost-estimate.sh
	$(call log_ok,Cost estimation complete)

.PHONY: docs
docs: ## Generate terraform-docs for all modules
	$(call log_info,Generating documentation...)
	@find $(TF_DIR)/modules -mindepth 1 -maxdepth 1 -type d -exec sh -c \
		'for dir; do \
			printf "$(CYAN)  -> Documenting $$(basename $$dir)...$(RESET)\n"; \
			terraform-docs markdown table "$$dir" --output-file README.md --output-mode inject 2>/dev/null || \
			terraform-docs markdown table "$$dir" > "$$dir/README.md"; \
		done' _ {} +
	@find $(TF_DIR)/modules -mindepth 2 -maxdepth 2 -type d -exec sh -c \
		'for dir; do \
			printf "$(CYAN)  -> Documenting $$(basename $$(dirname $$dir))/$$(basename $$dir)...$(RESET)\n"; \
			terraform-docs markdown table "$$dir" --output-file README.md --output-mode inject 2>/dev/null || \
			terraform-docs markdown table "$$dir" > "$$dir/README.md"; \
		done' _ {} +
	$(call log_ok,Documentation generated)

# ==============================================================================
# Utility Targets
# ==============================================================================

.PHONY: clean
clean: ## Remove .terraform directories and plan files
	$(call log_info,Cleaning up...)
	@find $(TF_DIR) -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find $(TF_DIR) -type f -name "tfplan" -delete 2>/dev/null || true
	@find $(TF_DIR) -type f -name "*.tfstate.backup" -delete 2>/dev/null || true
	@find $(TF_DIR) -type f -name "plan_output.txt" -delete 2>/dev/null || true
	$(call log_ok,Cleanup complete)

.PHONY: setup
setup: ## Install required tools (terraform, kubectl, helm, etc.)
	$(call log_info,Running setup script...)
	@bash $(SCRIPTS_DIR)/setup.sh

.PHONY: validate-all
validate-all: ## Run full validation suite (fmt + validate + lint)
	$(call log_info,Running full validation suite...)
	@bash $(SCRIPTS_DIR)/validate-all.sh

.PHONY: pre-commit-install
pre-commit-install: ## Install pre-commit hooks
	$(call log_info,Installing pre-commit hooks...)
	@pre-commit install
	$(call log_ok,Pre-commit hooks installed)

.PHONY: pre-commit-run
pre-commit-run: ## Run all pre-commit hooks on all files
	$(call log_info,Running pre-commit hooks...)
	@pre-commit run --all-files

# ==============================================================================
# Help
# ==============================================================================

.PHONY: help
help: ## Show this help message
	@printf "\n$(BLUE)Terraform EKS Project$(RESET)\n"
	@printf "$(BLUE)=====================$(RESET)\n\n"
	@printf "$(YELLOW)Available targets:$(RESET)\n\n"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'
	@printf "\n"
