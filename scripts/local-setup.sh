#!/bin/bash
# Quick setup script for local development environment

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

print_header "DT-Series Local Development Setup"

# Check prerequisites
print_info "Checking prerequisites..."

# Check if running in project directory
if [ ! -f "Makefile" ] || [ ! -d ".github" ]; then
    print_error "Please run this script from the project root directory"
    exit 1
fi

# Check required tools
MISSING_TOOLS=()

if ! command -v terraform >/dev/null 2>&1; then
    MISSING_TOOLS+=("terraform")
fi

if ! command -v ansible >/dev/null 2>&1; then
    MISSING_TOOLS+=("ansible")
fi

if ! command -v az >/dev/null 2>&1; then
    MISSING_TOOLS+=("azure-cli")
fi

if ! command -v python3 >/dev/null 2>&1; then
    MISSING_TOOLS+=("python3")
fi

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    print_error "Missing required tools: ${MISSING_TOOLS[*]}"
    echo ""
    echo "Please install the missing tools:"
    echo "  - Terraform: https://developer.hashicorp.com/terraform/downloads"
    echo "  - Ansible: pip install ansible"
    echo "  - Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    echo "  - Python 3: https://www.python.org/downloads/"
    exit 1
fi

print_info "✓ All required tools found"

# Check SSH key
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
if [ ! -f "$SSH_KEY_PATH" ]; then
    print_warning "SSH key not found at $SSH_KEY_PATH"
    read -p "Would you like to generate a new SSH key? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N ""
        print_info "SSH key generated at $SSH_KEY_PATH"
    else
        print_warning "Please ensure SSH key exists at $SSH_KEY_PATH before deploying"
    fi
else
    print_info "✓ SSH key found at $SSH_KEY_PATH"
fi

# Install Python test dependencies
print_info "Installing Python test dependencies..."
if command -v pip3 >/dev/null 2>&1; then
    pip3 install -r tests/requirements.txt --user
    print_info "✓ Python dependencies installed"
else
    print_warning "pip3 not found, skipping Python dependencies"
fi

# Check Azure login
print_info "Checking Azure authentication..."
if az account show >/dev/null 2>&1; then
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    print_info "✓ Logged in to Azure subscription: $SUBSCRIPTION_NAME"
else
    print_warning "Not logged in to Azure"
    read -p "Would you like to login to Azure now? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        az login
        print_info "✓ Azure login completed"
    else
        print_warning "Please run 'az login' before deploying infrastructure"
    fi
fi

# Setup environment configurations
print_info "Validating environment configurations..."
for env in dev staging production; do
    if [ -f "environments/$env/terraform.tfvars" ] && [ -f "environments/$env/backend.tf" ] && [ -f "environments/$env/ansible_vars.yml" ]; then
        print_info "✓ $env environment configuration found"
    else
        print_error "Missing configuration files for $env environment"
        exit 1
    fi
done

# Make scripts executable
print_info "Making scripts executable..."
chmod +x scripts/*.sh
print_info "✓ Scripts are now executable"

# Test Makefile
print_info "Testing Makefile..."
if make help >/dev/null 2>&1; then
    print_info "✓ Makefile working correctly"
else
    print_error "Makefile test failed"
    exit 1
fi

# Show next steps
print_header "Setup completed successfully!"
echo ""
echo "Next steps:"
echo ""
echo "1. Setup Azure backend storage (one-time):"
echo "   ${BLUE}make setup-backend${NC}"
echo ""
echo "2. Deploy to development environment:"
echo "   ${BLUE}make dev${NC}"
echo ""
echo "3. Check deployment status:"
echo "   ${BLUE}make status ENV=dev${NC}"
echo ""
echo "4. SSH to the VM:"
echo "   ${BLUE}make ssh ENV=dev${NC}"
echo ""
echo "For CI/CD setup with GitHub Actions, see:"
echo "   ${BLUE}CICD_SETUP.md${NC}"
echo ""
echo "Available commands:"
echo "   ${BLUE}make help${NC}               - Show all available commands"
echo "   ${BLUE}make validate-all${NC}       - Validate all configurations"
echo "   ${BLUE}make test-infrastructure${NC} - Run infrastructure tests"
echo ""
print_info "Happy coding! 🚀"
