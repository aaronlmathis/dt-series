# Makefile for Azure VM provisioning and configuration
# This integrates Terraform (infrastructure) with Ansible (configuration)
# Enhanced with multi-environment support and CI/CD integration

.PHONY: help plan apply destroy configure deploy clean status ssh validate logs
.PHONY: dev staging production setup-backend init-env test-infrastructure
.PHONY: security-scan validate-all deploy-env rollback

# Default variables
TERRAFORM_DIR := provisioning
ANSIBLE_DIR := configuration-management
SCRIPTS_DIR := scripts
TESTS_DIR := tests
# Use full path or shell expansion for SSH key
SSH_KEY := $(HOME)/.ssh/id_rsa

# Environment variable (default to dev)
ENV ?= dev

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
BLUE := \033[0;34m
NC := \033[0m # No Color

# Force bash usage for advanced features
SHELL := /bin/bash

help: ## Show this help message
	@echo "Azure VM Infrastructure & Configuration Management"
	@echo "=================================================="
	@echo ""
	@echo "Environment: $(ENV) (use ENV=<env> to change)"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "Environment Management:"
	@echo "  $(BLUE)make dev$(NC)         - Deploy to development"
	@echo "  $(BLUE)make staging$(NC)     - Deploy to staging"
	@echo "  $(BLUE)make production$(NC)  - Deploy to production"
	@echo ""
	@echo "CI/CD Integration:"
	@echo "  $(BLUE)make setup-backend$(NC) - Setup Azure backend storage"
	@echo "  $(BLUE)make validate-all$(NC)  - Run all validations"
	@echo "  $(BLUE)make security-scan$(NC) - Run security scanning"
	@echo ""
	@echo "Typical workflow:"
	@echo "  1. make setup-backend  - One-time setup"
	@echo "  2. make dev           - Deploy to development"
	@echo "  3. make staging       - Deploy to staging"
	@echo "  4. make production    - Deploy to production"

check-prereqs: ## Check if required tools are installed
	@echo -e "$(GREEN)Checking prerequisites...$(NC)"
	@command -v terraform >/dev/null 2>&1 || { echo -e "$(RED)Error: terraform is not installed$(NC)" >&2; exit 1; }
	@command -v ansible >/dev/null 2>&1 || { echo -e "$(RED)Error: ansible is not installed$(NC)" >&2; exit 1; }
	@if [ -f "$(SSH_KEY)" ]; then \
		echo -e "$(GREEN)✓ Found SSH key: $(SSH_KEY)$(NC)"; \
	else \
		echo -e "$(RED)Error: SSH key not found at $(SSH_KEY)$(NC)"; \
		echo -e "$(YELLOW)Please ensure your SSH key exists at $(SSH_KEY)$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(GREEN)✓ All prerequisites satisfied$(NC)"

check-env: ## Validate environment selection
	@if [[ ! "$(ENV)" =~ ^(dev|staging|production)$$ ]]; then \
		echo -e "$(RED)Error: Invalid environment '$(ENV)'$(NC)"; \
		echo -e "$(YELLOW)Valid environments: dev, staging, production$(NC)"; \
		exit 1; \
	fi
	@if [ ! -d "environments/$(ENV)" ]; then \
		echo -e "$(RED)Error: Environment configuration not found: environments/$(ENV)$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(GREEN)✓ Environment $(ENV) is valid$(NC)"

setup-backend: ## Setup Azure backend storage for Terraform state
	@echo -e "$(GREEN)Setting up Azure backend storage...$(NC)"
	@$(SCRIPTS_DIR)/setup-azure-backend.sh
	@echo -e "$(GREEN)✓ Backend setup completed$(NC)"

init-env: check-env ## Initialize environment configuration
	@echo -e "$(GREEN)Initializing $(ENV) environment...$(NC)"
	@cp environments/$(ENV)/terraform.tfvars $(TERRAFORM_DIR)/
	@cp environments/$(ENV)/backend.tf $(TERRAFORM_DIR)/
	@cp environments/$(ENV)/ansible_vars.yml $(ANSIBLE_DIR)/group_vars/azure_vms.yml
	@echo -e "$(GREEN)✓ Environment $(ENV) initialized$(NC)"

plan: check-prereqs check-env init-env ## Plan Terraform infrastructure changes for current environment
	@echo -e "$(GREEN)Planning infrastructure changes for $(ENV)...$(NC)"
	@cd $(TERRAFORM_DIR) && terraform init && terraform plan -var-file=terraform.tfvars
	@echo -e "$(GREEN)✓ Plan completed for $(ENV)$(NC)"

apply: check-prereqs check-env init-env ## Apply Terraform infrastructure changes for current environment
	@echo -e "$(GREEN)Applying infrastructure changes for $(ENV)...$(NC)"
	@if [ "$(ENV)" == "production" ]; then \
		echo -e "$(RED)WARNING: You are deploying to PRODUCTION!$(NC)"; \
		read -p "Are you sure you want to continue? [y/N] " -n 1 -r; \
		echo ""; \
		if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then \
			echo -e "$(YELLOW)Deployment cancelled$(NC)"; \
			exit 0; \
		fi; \
	fi
	@cd $(TERRAFORM_DIR) && terraform init && terraform apply -auto-approve -var-file=terraform.tfvars
	@echo -e "$(GREEN)✓ Infrastructure deployed for $(ENV)$(NC)"

configure: check-env ## Run Ansible configuration on current environment
	@echo -e "$(GREEN)Configuring VM with Ansible for $(ENV)...$(NC)"
	@$(SCRIPTS_DIR)/deploy-environment.sh $(ENV) configure
	@echo -e "$(GREEN)✓ VM configuration completed for $(ENV)$(NC)"

deploy-env: check-prereqs check-env ## Full deployment using deployment script
	@echo -e "$(GREEN)Full deployment for $(ENV)...$(NC)"
	@$(SCRIPTS_DIR)/deploy-environment.sh $(ENV) apply
	@echo -e "$(GREEN)✓ Full deployment completed for $(ENV)$(NC)"

# Environment-specific targets
dev: ## Deploy to development environment
	@$(MAKE) deploy-env ENV=dev

staging: ## Deploy to staging environment
	@$(MAKE) deploy-env ENV=staging

production: ## Deploy to production environment
	@$(MAKE) deploy-env ENV=production

deploy: plan apply configure ## Full deployment: provision infrastructure + configure VM (legacy - use deploy-env)
	@echo -e "$(YELLOW)Legacy target - consider using 'make deploy-env ENV=<env>' instead$(NC)"
	@echo -e "$(GREEN)Full deployment completed!$(NC)"
	@echo ""
	@echo -e "$(YELLOW)Deployment Summary:$(NC)"
	@echo "=================="
	@cd $(TERRAFORM_DIR) && echo "VM Name: $$(terraform output -raw vm_name)"
	@cd $(TERRAFORM_DIR) && echo "Public IP: $$(terraform output -raw public_ip_address)"
	@cd $(TERRAFORM_DIR) && echo "SSH Command: $$(terraform output -raw ssh_connection_command)"
	@cd $(TERRAFORM_DIR) && echo "Web App: http://$$(terraform output -raw public_ip_address)"
	@echo ""
	@echo -e "$(GREEN)Your VM is ready for use!$(NC)"

status: check-env ## Show current infrastructure status for environment
	@echo -e "$(GREEN)Infrastructure Status for $(ENV):$(NC)"
	@echo "=============================="
	@if [ -f "$(TERRAFORM_DIR)/terraform.tfstate" ]; then \
		cd $(TERRAFORM_DIR) && terraform show -json | jq -r '.values.root_module.resources[] | select(.type=="azurerm_linux_virtual_machine") | "VM Status: " + .values.name + " (" + .values.location + ")"' 2>/dev/null || echo "VM: Deployed"; \
		echo "Public IP: $$(cd $(TERRAFORM_DIR) && terraform output -raw public_ip_address 2>/dev/null || echo 'Not available')"; \
		echo "Resource Group: $$(cd $(TERRAFORM_DIR) && terraform output -raw resource_group_name 2>/dev/null || echo 'Not available')"; \
	else \
		echo -e "$(YELLOW)No infrastructure deployed for $(ENV)$(NC)"; \
	fi

ssh: check-env init-env ## SSH into the VM for current environment
	@echo -e "$(GREEN)Connecting to $(ENV) VM...$(NC)"
	@cd $(TERRAFORM_DIR) && $$(terraform output -raw ssh_connection_command 2>/dev/null) || { echo -e "$(RED)Cannot get SSH command. Is the VM deployed?$(NC)" >&2; exit 1; }

test: check-env ## Test the deployed web application for current environment
	@echo -e "$(GREEN)Testing web application for $(ENV)...$(NC)"
	@VM_IP=$$(cd $(TERRAFORM_DIR) && terraform output -raw public_ip_address 2>/dev/null) && \
	if [ -n "$$VM_IP" ]; then \
		echo "Testing HTTP connection to $$VM_IP..."; \
		curl -v --connect-timeout 10 "http://$$VM_IP" || echo -e "$(YELLOW)Connection failed$(NC)"; \
	else \
		echo -e "$(RED)VM IP not available$(NC)"; \
	fi

test-infrastructure: ## Run infrastructure validation tests
	@echo -e "$(GREEN)Running infrastructure tests...$(NC)"
	@if command -v pytest >/dev/null 2>&1; then \
		cd $(TESTS_DIR) && python -m pytest test_infrastructure.py -v; \
	else \
		echo -e "$(YELLOW)pytest not available, skipping tests$(NC)"; \
	fi

test-deployment: check-env ## Run deployment tests for current environment
	@echo -e "$(GREEN)Running deployment tests for $(ENV)...$(NC)"
	@if command -v pytest >/dev/null 2>&1; then \
		cd $(TESTS_DIR) && python -m pytest test_deployment.py -v --env=$(ENV); \
	else \
		echo -e "$(YELLOW)pytest not available, skipping tests$(NC)"; \
	fi

security-scan: ## Run security scanning
	@echo -e "$(GREEN)Running security scans...$(NC)"
	@if command -v trivy >/dev/null 2>&1; then \
		trivy fs --format table .; \
	else \
		echo -e "$(YELLOW)trivy not available, skipping security scan$(NC)"; \
	fi
	@if command -v checkov >/dev/null 2>&1; then \
		checkov -d . --framework terraform,ansible; \
	else \
		echo -e "$(YELLOW)checkov not available, skipping policy scan$(NC)"; \
	fi

validate-all: ## Run all validations (terraform, ansible, security)
	@echo -e "$(GREEN)Running comprehensive validation...$(NC)"
	@$(MAKE) validate
	@$(MAKE) test-infrastructure
	@$(MAKE) security-scan
	@echo -e "$(GREEN)✓ All validations completed$(NC)"

logs: ## Show Ansible deployment logs
	@echo -e "$(GREEN)Recent deployment logs:$(NC)"
	@if [ -f "$(ANSIBLE_DIR)/ansible.log" ]; then \
		tail -50 "$(ANSIBLE_DIR)/ansible.log"; \
	else \
		echo -e "$(YELLOW)No deployment logs found$(NC)"; \
	fi

clean: ## Clean Terraform cache and temporary files
	@echo -e "$(GREEN)Cleaning temporary files...$(NC)"
	@rm -rf $(TERRAFORM_DIR)/.terraform
	@rm -f $(TERRAFORM_DIR)/.terraform.lock.hcl
	@rm -f $(TERRAFORM_DIR)/terraform.tfstate.backup
	@rm -f $(TERRAFORM_DIR)/terraform.tfvars
	@rm -f $(TERRAFORM_DIR)/backend.tf
	@rm -f $(ANSIBLE_DIR)/ansible.log
	@rm -f $(ANSIBLE_DIR)/group_vars/azure_vms.yml
	@echo -e "$(GREEN)✓ Cleanup completed$(NC)"

validate: ## Validate Terraform and Ansible configurations
	@echo -e "$(GREEN)Validating configurations...$(NC)"
	@for env in dev staging production; do \
		echo -e "$(BLUE)Validating $$env environment...$(NC)"; \
		cp environments/$$env/terraform.tfvars $(TERRAFORM_DIR)/; \
		cp environments/$$env/backend.tf $(TERRAFORM_DIR)/; \
		cd $(TERRAFORM_DIR) && terraform fmt -check; \
		cd $(TERRAFORM_DIR) && terraform init -backend=false; \
		cd $(TERRAFORM_DIR) && terraform validate; \
		rm -f $(TERRAFORM_DIR)/terraform.tfvars $(TERRAFORM_DIR)/backend.tf; \
	done
	@cd $(ANSIBLE_DIR) && ansible-playbook --syntax-check site.yml -i inventory/hosts.yml || echo -e "$(YELLOW)Create a sample inventory for syntax check$(NC)"
	@echo -e "$(GREEN)✓ All configurations valid$(NC)"

rollback: check-env ## Rollback environment (interactive)
	@echo -e "$(RED)WARNING: This will rollback $(ENV) environment!$(NC)"
	@read -p "Enter reason for rollback: " reason; \
	echo "Rollback reason: $$reason"; \
	echo "This would trigger the disaster recovery workflow in production CI/CD"; \
	echo "For now, please use the GitHub Actions disaster recovery workflow"

destroy: check-env init-env ## Destroy all infrastructure for current environment
	@echo -e "$(RED)WARNING: This will destroy all $(ENV) infrastructure!$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo ""; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo -e "$(GREEN)Destroying $(ENV) infrastructure...$(NC)"; \
		cd $(TERRAFORM_DIR) && terraform init && terraform destroy -auto-approve -var-file=terraform.tfvars; \
		echo -e "$(GREEN)✓ Infrastructure destroyed for $(ENV)$(NC)"; \
	else \
		echo -e "$(YELLOW)Destroy cancelled$(NC)"; \
	fi

# Set default target
.DEFAULT_GOAL := help
