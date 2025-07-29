#!/bin/bash
# Setup Azure backend storage for Terraform state
# This script creates the necessary Azure resources for remote state storage

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[SETUP]${NC} $1"
}

# Configuration
RESOURCE_GROUP_NAME="dt-series-tfstate-rg"
LOCATION="East US"

# Storage account names (must be globally unique)
STORAGE_ACCOUNT_DEV="dtseriestfstatedev$(date +%s | tail -c 5)"
STORAGE_ACCOUNT_STAGING="dtseriestfstatestaging$(date +%s | tail -c 5)"
STORAGE_ACCOUNT_PROD="dtseriestfstateprod$(date +%s | tail -c 5)"

CONTAINER_NAME="tfstate"

print_header "Setting up Azure backend storage for Terraform state"

# Check if Azure CLI is installed and logged in
if ! command -v az >/dev/null 2>&1; then
    print_error "Azure CLI not found. Please install Azure CLI first."
    exit 1
fi

# Check if logged in
if ! az account show >/dev/null 2>&1; then
    print_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

print_info "Azure CLI is available and authenticated"

# Create resource group
print_info "Creating resource group: $RESOURCE_GROUP_NAME"
az group create \
    --name "$RESOURCE_GROUP_NAME" \
    --location "$LOCATION" \
    --tags purpose=terraform-state project=dt-series

# Function to create storage account and container
create_storage_account() {
    local storage_account_name=$1
    local environment=$2
    
    print_info "Creating storage account: $storage_account_name for $environment"
    
    az storage account create \
        --name "$storage_account_name" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --tags environment="$environment" purpose=terraform-state project=dt-series
    
    # Get storage account key
    ACCOUNT_KEY=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --account-name "$storage_account_name" \
        --query '[0].value' -o tsv)
    
    # Create container
    print_info "Creating container: $CONTAINER_NAME in $storage_account_name"
    az storage container create \
        --name "$CONTAINER_NAME" \
        --account-name "$storage_account_name" \
        --account-key "$ACCOUNT_KEY"
    
    print_info "Storage account $storage_account_name created successfully"
    echo "  Storage Account: $storage_account_name"
    echo "  Container: $CONTAINER_NAME"
    echo "  Resource Group: $RESOURCE_GROUP_NAME"
    echo ""
}

# Create storage accounts for each environment
create_storage_account "$STORAGE_ACCOUNT_DEV" "dev"
create_storage_account "$STORAGE_ACCOUNT_STAGING" "staging"
create_storage_account "$STORAGE_ACCOUNT_PROD" "production"

# Update backend configuration files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

print_info "Updating backend configuration files..."

# Update dev backend
cat > "$PROJECT_ROOT/environments/dev/backend.tf" << EOF
terraform {
  backend "azurerm" {
    resource_group_name  = "$RESOURCE_GROUP_NAME"
    storage_account_name = "$STORAGE_ACCOUNT_DEV"
    container_name       = "$CONTAINER_NAME"
    key                  = "dev.terraform.tfstate"
  }
}
EOF

# Update staging backend
cat > "$PROJECT_ROOT/environments/staging/backend.tf" << EOF
terraform {
  backend "azurerm" {
    resource_group_name  = "$RESOURCE_GROUP_NAME"
    storage_account_name = "$STORAGE_ACCOUNT_STAGING"
    container_name       = "$CONTAINER_NAME"
    key                  = "staging.terraform.tfstate"
  }
}
EOF

# Update production backend
cat > "$PROJECT_ROOT/environments/production/backend.tf" << EOF
terraform {
  backend "azurerm" {
    resource_group_name  = "$RESOURCE_GROUP_NAME"
    storage_account_name = "$STORAGE_ACCOUNT_PROD"
    container_name       = "$CONTAINER_NAME"
    key                  = "production.terraform.tfstate"
  }
}
EOF

print_info "Backend configuration files updated"

# Create service principal for GitHub Actions (optional)
print_warning "To use GitHub Actions, you need to create a service principal:"
print_warning "Run the following commands and add the output to GitHub secrets:"
echo ""
echo "az ad sp create-for-rbac --name dt-series-github-actions --role contributor --scopes /subscriptions/\$(az account show --query id -o tsv) --sdk-auth"
echo ""
print_warning "Add the JSON output as AZURE_CREDENTIALS secret in GitHub"
print_warning "Also add these individual secrets:"
echo "  AZURE_CLIENT_ID"
echo "  AZURE_CLIENT_SECRET"
echo "  AZURE_SUBSCRIPTION_ID"
echo "  AZURE_TENANT_ID"

print_header "Backend storage setup completed successfully!"
echo ""
echo "Created storage accounts:"
echo "  Dev: $STORAGE_ACCOUNT_DEV"
echo "  Staging: $STORAGE_ACCOUNT_STAGING"
echo "  Production: $STORAGE_ACCOUNT_PROD"
echo ""
echo "All storage accounts are in resource group: $RESOURCE_GROUP_NAME"
