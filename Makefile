# =============================================================================
# Terraform State Bootstrap & Multi-Environment Workflow
#
# Environments: dev | test | perf | staging | production
#
# Prerequisites:
#   - Terraform >= 1.10.0
#   - AWS CLI >= 2.0  (aws configure / env vars / IAM role)
#   - GNU Make (macOS: pre-installed)
#
# State locking strategy (dual-lock):
#   All backends set both dynamodb_table and use_lockfile = true.
#   - dynamodb_table: battle-tested DynamoDB locking (current standard)
#   - use_lockfile:   S3-native locking via .tflock file (Terraform >= 1.10, AWS provider >= 5.86)
#   Both are active simultaneously. Once use_lockfile is widely adopted,
#   dynamodb_table can be removed without a state migration.
#
# Quick start (first time):
#   1. make bootstrap-apply            # create S3 + DynamoDB — run once
#   2. make init-all                   # init all 5 environments
#
# Day-to-day:
#   make plan  ENV=dev
#   make apply ENV=dev
#   make plan  ENV=production          # requires extra confirmation on apply
#
# Modules:
#   make test MODULE=networking        # run terraform test for a module
#   make test-all                      # test all modules
# =============================================================================

BOOTSTRAP_DIR   := infra/bootstrap
ENVS_DIR        := infra/envs
AWS_REGION      := us-east-1

# All supported environments (order matters for init-all / plan-all).
ENVS            := dev test perf staging production

# Environments that require an explicit typed confirmation before apply/destroy.
PROTECTED_ENVS  := staging production

# Read outputs from bootstrap local state (populated after bootstrap-apply).
STATE_BUCKET    := $(shell cd $(BOOTSTRAP_DIR) && terraform output -raw state_bucket_name 2>/dev/null)
LOCK_TABLE      := $(shell cd $(BOOTSTRAP_DIR) && terraform output -raw lock_table_name  2>/dev/null)

ENV             ?=

# ─── Helpers ──────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}'

# Ensure ENV is set and is a recognised environment.
require-env:
	@test -n "$(ENV)" \
		|| (echo "ERROR: ENV is required. Usage: make <target> ENV=<name>"; exit 1)
	@echo " $(ENVS) " | grep -qw "$(ENV)" \
		|| (echo "ERROR: '$(ENV)' is not a valid environment. Choose from: $(ENVS)"; exit 1)

# Extra confirmation gate for protected environments (staging / production).
require-confirmation:
	@if echo " $(PROTECTED_ENVS) " | grep -qw "$(ENV)"; then \
		echo ""; \
		echo "  *** PROTECTED ENVIRONMENT: $(ENV) ***"; \
		echo ""; \
		read -p "  Type '$(ENV)' to confirm: " confirm \
			&& [ "$$confirm" = "$(ENV)" ] \
			|| (echo "Aborted."; exit 1); \
	fi

# ─── Bootstrap ────────────────────────────────────────────────────────────────

.PHONY: bootstrap-init
bootstrap-init: ## terraform init for bootstrap (local backend)
	cd $(BOOTSTRAP_DIR) && terraform init

.PHONY: bootstrap-plan
bootstrap-plan: ## terraform plan for bootstrap
	cd $(BOOTSTRAP_DIR) && terraform plan

.PHONY: bootstrap-apply
bootstrap-apply: ## Create S3 bucket + DynamoDB lock table (run once)
	cd $(BOOTSTRAP_DIR) && terraform apply
	@echo ""
	@echo "Bootstrap complete. Remote state backend is ready:"
	@echo "  S3 bucket  : $$(cd $(BOOTSTRAP_DIR) && terraform output -raw state_bucket_name)"
	@echo "  DynamoDB   : $$(cd $(BOOTSTRAP_DIR) && terraform output -raw lock_table_name)"
	@echo ""
	@echo "IMPORTANT: Back up $(BOOTSTRAP_DIR)/terraform.tfstate to a secure location (e.g. 1Password)."

.PHONY: bootstrap-output
bootstrap-output: ## Show bootstrap outputs (bucket name, table name, ARNs)
	cd $(BOOTSTRAP_DIR) && terraform output

# ─── Single-environment targets ───────────────────────────────────────────────

.PHONY: init
init: require-env ## terraform init for one environment  (ENV=<name>)
	cd $(ENVS_DIR)/$(ENV) && terraform init

.PHONY: plan
plan: require-env ## terraform plan for one environment  (ENV=<name>)
	cd $(ENVS_DIR)/$(ENV) && terraform plan -var-file=terraform.tfvars

.PHONY: apply
apply: require-env require-confirmation ## terraform apply  (ENV=<name>; staging/production ask for confirmation)
	cd $(ENVS_DIR)/$(ENV) && terraform apply -var-file=terraform.tfvars

.PHONY: destroy
destroy: require-env require-confirmation ## terraform destroy  (ENV=<name>; always asks for confirmation)
	@echo "WARNING: About to destroy all resources in ENV=$(ENV)."
	@read -p "Type 'yes' to proceed: " yn && [ "$$yn" = "yes" ] \
		|| (echo "Aborted."; exit 1)
	cd $(ENVS_DIR)/$(ENV) && terraform destroy -var-file=terraform.tfvars

.PHONY: validate
validate: require-env ## terraform validate for one environment
	cd $(ENVS_DIR)/$(ENV) && terraform validate

.PHONY: state-list
state-list: require-env ## List resources in remote state for one environment
	cd $(ENVS_DIR)/$(ENV) && terraform state list

# ─── Bulk targets (all environments) ─────────────────────────────────────────

.PHONY: init-all
init-all: ## terraform init for all environments
	@for env in $(ENVS); do \
		echo ""; \
		echo "==> init: $$env"; \
		cd $(CURDIR)/$(ENVS_DIR)/$$env && terraform init -input=false; \
	done

.PHONY: validate-all
validate-all: ## terraform validate for all environments
	@for env in $(ENVS); do \
		echo ""; \
		echo "==> validate: $$env"; \
		cd $(CURDIR)/$(ENVS_DIR)/$$env && terraform validate; \
	done

.PHONY: plan-all
plan-all: ## terraform plan for all environments (read-only, safe to run in CI)
	@for env in $(ENVS); do \
		echo ""; \
		echo "==> plan: $$env"; \
		cd $(CURDIR)/$(ENVS_DIR)/$$env && terraform plan -var-file=terraform.tfvars; \
	done

# ─── Utilities ────────────────────────────────────────────────────────────────

.PHONY: fmt
fmt: ## Run terraform fmt recursively across all infra
	terraform fmt -recursive infra/

.PHONY: fmt-check
fmt-check: ## Check formatting without writing changes (use in CI)
	terraform fmt -recursive -check infra/

# ─── Module testing ───────────────────────────────────────────────────────────

MODULE          ?=

.PHONY: test
test: ## Run terraform test for a module  (MODULE=<name>, e.g. MODULE=networking)
	@test -n "$(MODULE)" \
		|| (echo "ERROR: MODULE is required. Usage: make test MODULE=<name>"; exit 1)
	@test -d "infra/modules/$(MODULE)" \
		|| (echo "ERROR: Module 'infra/modules/$(MODULE)' not found."; exit 1)
	cd infra/modules/$(MODULE) && terraform test

.PHONY: test-all
test-all: ## Run terraform test for all modules that have a tests/ directory
	@found=0; \
	for mod in $$(ls infra/modules/); do \
		if [ -d "infra/modules/$$mod/tests" ]; then \
			found=1; \
			echo ""; \
			echo "==> test: $$mod"; \
			cd $(CURDIR)/infra/modules/$$mod && terraform test; \
		fi; \
	done; \
	[ $$found -eq 1 ] || echo "No modules with tests/ directory found."

.PHONY: lock-check
lock-check: ## Show any active state locks in DynamoDB
	@test -n "$(LOCK_TABLE)" || (echo "ERROR: Run 'make bootstrap-apply' first."; exit 1)
	aws dynamodb scan \
		--table-name $(LOCK_TABLE) \
		--region $(AWS_REGION) \
		--query "Items[*].{LockID:LockID.S,Info:Info.S}" \
		--output table

.PHONY: lock-release
lock-release: ## Force-release a stuck DynamoDB lock (use with caution)
	@test -n "$(LOCK_TABLE)" || (echo "ERROR: Run 'make bootstrap-apply' first."; exit 1)
	@read -p "Enter LockID to delete: " lid && \
		aws dynamodb delete-item \
			--table-name $(LOCK_TABLE) \
			--region $(AWS_REGION) \
			--key "{\"LockID\":{\"S\":\"$$lid\"}}"
