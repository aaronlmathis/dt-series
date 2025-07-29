# GitHub Actions CI/CD Setup Instructions

This guide provides step-by-step instructions to set up a simplified CI/CD pipeline for deploying infrastructure to Azure using Terraform and Ansible with GitHub Actions.

## Overview

The CI/CD pipeline consists of:
- **PR Validation**: Lint, validate, and dry-run on PRs to `develop` branch
- **Development Deployment**: Auto-deploy on merge to `develop` branch
- **Staging Deployment**: Manual trigger after dev deployment passes
- **Production Deployment**: Manual approval required before deployment

## Prerequisites

- Azure subscription
- GitHub repository
- Azure CLI installed locally
- Terraform CLI installed locally

## Part 1: Azure Service Principal Setup with OIDC

### 1.1 Create Azure Service Principal

```bash
# Login to Azure
az login

# Set your subscription (replace with your subscription ID)
az account set --subscription ${ARM_SUBSCRIPTION_ID}

# Create service principal
az ad sp create-for-rbac --name "github-actions-sp" \
  --role contributor \
  --scopes /subscriptions/${ARM_SUBSCRIPTION_ID}
```

**Save the output** - you'll need `appId`, `tenant`, and `subscription` values.

### 1.2 Configure OIDC Federation

```bash
# Get your GitHub repository details
# Replace: OWNER = your GitHub username/org, REPO = your repository name
GITHUB_OWNER="your-github-username"
GITHUB_REPO="your-repo-name"
APP_ID="your-app-id-from-previous-step"

# Create OIDC credential for main branch (production)
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'$GITHUB_OWNER'/'$GITHUB_REPO':ref:refs/heads/main",
    "description": "GitHub Actions Main Branch",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# Create OIDC credential for develop branch
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-develop",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'$GITHUB_OWNER'/'$GITHUB_REPO':ref:refs/heads/develop",
    "description": "GitHub Actions Develop Branch",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# Create OIDC credential for pull requests
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-pr",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'$GITHUB_OWNER'/'$GITHUB_REPO':pull_request",
    "description": "GitHub Actions Pull Requests",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

### 1.3 Get Required Values

```bash
# Get your tenant ID
az account show --query tenantId --output tsv

# Get your subscription ID
az account show --query id --output tsv

# The App ID is from step 1.1 output (appId field)
```

## Part 2: GitHub Repository Secrets

Navigate to your GitHub repository → Settings → Secrets and variables → Actions

### 2.1 Create Repository Secrets

Add these secrets:

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `AZURE_CLIENT_ID` | `appId` from step 1.1 | Service Principal App ID |
| `AZURE_TENANT_ID` | Output from tenant command | Azure Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Output from subscription command | Azure Subscription ID |
| `SSH_PRIVATE_KEY` | Your SSH private key content | SSH key for Ansible |

### 2.2 Generate SSH Key (if needed)

```bash
# Generate SSH key pair
ssh-keygen -t rsa -b 4096 -f ~/.ssh/azure_vm_key -C "azure-vm-key"

# Display private key (copy this to SSH_PRIVATE_KEY secret)
cat ~/.ssh/azure_vm_key

# Display public key (use this in your VM configuration)
cat ~/.ssh/azure_vm_key.pub
```

## Part 3: Azure Storage for Terraform State

Create storage accounts for each environment to store Terraform state.

### 3.1 Development Environment Storage

```bash
# Create resource group
az group create --name "rg-terraform-state-dev" --location "East US"

# Create storage account (name must be globally unique)
STORAGE_ACCOUNT_NAME="tfstatedev$(date +%s)"
az storage account create \
  --resource-group "rg-terraform-state-dev" \
  --name $STORAGE_ACCOUNT_NAME \
  --sku Standard_LRS \
  --encryption-services blob

# Create storage container
az storage container create \
  --name "tfstate" \
  --account-name $STORAGE_ACCOUNT_NAME

# Get storage account key
az storage account keys list \
  --resource-group "rg-terraform-state-dev" \
  --account-name $STORAGE_ACCOUNT_NAME \
  --query '[0].value' -o tsv
```

### 3.2 Staging Environment Storage

```bash
# Create resource group
az group create --name "rg-terraform-state-staging" --location "East US"

# Create storage account (name must be globally unique)
STORAGE_ACCOUNT_NAME="tfstatestaging$(date +%s)"
az storage account create \
  --resource-group "rg-terraform-state-staging" \
  --name $STORAGE_ACCOUNT_NAME \
  --sku Standard_LRS \
  --encryption-services blob

# Create storage container
az storage container create \
  --name "tfstate" \
  --account-name $STORAGE_ACCOUNT_NAME

# Get storage account key
az storage account keys list \
  --resource-group "rg-terraform-state-staging" \
  --account-name $STORAGE_ACCOUNT_NAME \
  --query '[0].value' -o tsv
```

### 3.3 Production Environment Storage

```bash
# Create resource group
az group create --name "rg-terraform-state-production" --location "East US"

# Create storage account (name must be globally unique)
STORAGE_ACCOUNT_NAME="tfstateprod$(date +%s)"
az storage account create \
  --resource-group "rg-terraform-state-production" \
  --name $STORAGE_ACCOUNT_NAME \
  --sku Standard_LRS \
  --encryption-services blob

# Create storage container
az storage container create \
  --name "tfstate" \
  --account-name $STORAGE_ACCOUNT_NAME

# Get storage account key
az storage account keys list \
  --resource-group "rg-terraform-state-production" \
  --account-name $STORAGE_ACCOUNT_NAME \
  --query '[0].value' -o tsv
```

## Part 4: Update Environment Configuration Files

Update your environment-specific backend configuration files with the storage account information:

### 4.1 Update `environments/dev/backend.tf`

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state-dev"
    storage_account_name = "your-dev-storage-account-name"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
  }
}
```

### 4.2 Update `environments/staging/backend.tf`

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state-staging"
    storage_account_name = "your-staging-storage-account-name"
    container_name       = "tfstate"
    key                  = "staging.terraform.tfstate"
  }
}
```

### 4.3 Update `environments/production/backend.tf`

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state-production"
    storage_account_name = "your-production-storage-account-name"
    container_name       = "tfstate"
    key                  = "production.terraform.tfstate"
  }
}
```

## Part 5: GitHub Environments Setup

Create GitHub environments for deployment protection.

### 5.1 Navigate to Repository Settings

Go to: Repository → Settings → Environments

### 5.2 Create Environments

Create these environments:

1. **development**
   - No protection rules needed

2. **staging**  
   - No protection rules needed

3. **production**
   - ✅ Required reviewers: Add yourself or team members
   - ✅ Wait timer: 0 minutes (or set a delay if desired)

## Part 6: Test the Pipeline

### 6.1 Test PR Validation

```bash
# Create a feature branch
git checkout -b feature/test-cicd

# Make a small change to trigger validation
echo "# Test change" >> README.md
git add README.md
git commit -m "Test: trigger PR validation"
git push origin feature/test-cicd

# Create PR to develop branch
# This should trigger the PR validation workflow
```

### 6.2 Test Development Deployment

```bash
# Merge PR to develop branch
# This should trigger the development deployment workflow
```

### 6.3 Test Staging Deployment

1. After dev deployment succeeds, manually trigger staging:
   - Go to Actions tab in GitHub
   - Select "Deploy to Staging" workflow
   - Click "Run workflow"

### 6.4 Test Production Deployment

1. After staging deployment succeeds:
   - Go to Actions tab in GitHub
   - Select "Deploy to Production" workflow
   - Click "Run workflow"
   - Approve the deployment when prompted

## Part 7: Workflow Behavior

### 7.1 PR to Develop Branch
- ✅ Terraform/Ansible linting and validation
- ✅ Terraform plan (dev environment)
- ✅ Ansible check mode (dry run)
- ✅ Integration tests (configuration validation)

### 7.2 Merge to Develop Branch
- ✅ Deploy infrastructure to dev environment
- ✅ Run Ansible configuration
- ✅ Smoke tests (`test_smoke.py`) - VM connectivity, SSH, services, firewall
- ✅ **Automatically triggers staging deployment on success**

### 7.3 Staging Deployment (Automatic After Dev Success)
- ✅ **Automatically triggered** when dev deployment succeeds
- ✅ Deploy infrastructure to staging environment  
- ✅ Run Ansible configuration
- ✅ Security tests (`test_security.py`) - hardening, firewall, fail2ban, permissions
- ✅ Create approval request for production

### 7.4 Production Deployment (Manual Approval Required)
- ⚠️ **Manual approval required**
- ✅ Deploy infrastructure to production environment
- ✅ Run Ansible configuration  
- ✅ Health checks (`test_health.py`) - system health, services, monitoring
- ✅ Security verification (`test_security.py`) - production security validation
- ✅ Notify deployment status via GitHub issues

## Part 8: Test Files Overview

The repository includes comprehensive pytest test suites:

### 8.1 Integration Tests (`test_infrastructure.py`)
- **Used in**: PR validation
- **Purpose**: Validate environment configurations
- **Tests**: Config file existence, variable formats, environment isolation

### 8.2 Smoke Tests (`test_smoke.py`)  
- **Used in**: Development deployment
- **Purpose**: Basic connectivity and service validation
- **Tests**: VM ping, SSH connectivity, service status, firewall rules

### 8.3 Security Tests (`test_security.py`)
- **Used in**: Staging and production deployments
- **Purpose**: Comprehensive security validation
- **Tests**: SSH hardening, firewall rules, fail2ban, file permissions, user accounts

### 8.4 Health Tests (`test_health.py`)
- **Used in**: Production deployment
- **Purpose**: Production health and performance validation  
- **Tests**: System health, service status, monitoring, compliance, performance

### 8.5 Running Tests Locally

```bash
# Install test dependencies
pip install pytest testinfra pyyaml

# Run all tests
cd tests
python -m pytest -v

# Run specific test suites
python -m pytest test_infrastructure.py -v
python -m pytest test_smoke.py -v
python -m pytest test_security.py -v --env=staging
python -m pytest test_health.py -v
```

## Part 9: Troubleshooting

### 8.1 Common Issues

**OIDC Authentication Failures:**
```bash
# Verify federated credentials exist
az ad app federated-credential list --id $APP_ID
```

**Terraform State Issues:**
```bash
# Verify storage account access
az storage account keys list --resource-group "rg-terraform-state-dev" --account-name "your-storage-account"
```

**SSH Connection Issues:**
- Verify SSH_PRIVATE_KEY secret is correctly formatted
- Ensure corresponding public key is configured in VM

### 8.2 Manual Cleanup

If you need to destroy environments:

```bash
# Login and set subscription
az login
az account set --subscription "your-subscription-id"

# Navigate to provisioning directory
cd provisioning

# Copy environment config
cp ../environments/dev/terraform.tfvars .
cp ../environments/dev/backend.tf .

# Initialize and destroy
terraform init
terraform destroy -var-file=terraform.tfvars
```

## Part 9: Next Steps

After basic setup works:

1. **Customize Tests**: Update test files in `tests/` directory for your specific needs
2. **Add Notifications**: Configure Slack/Teams webhooks for deployment notifications  
3. **Security Scanning**: Add additional security tools like Checkov or TfSec
4. **Monitoring**: Set up Azure Monitor alerts for deployed infrastructure
5. **Backup Strategy**: Implement automated backup procedures for production

## Summary

This simplified pipeline provides:
- ✅ Automated validation on PRs
- ✅ Automated dev deployments
- ✅ Controlled staging deployments  
- ✅ Manual approval for production
- ✅ Basic testing at each stage
- ✅ Infrastructure as Code with proper state management

The pipeline is intentionally simple while providing essential safety mechanisms for production deployments.
