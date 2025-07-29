#!/bin/bash
# Environment deployment script
# Usage: ./deploy-environment.sh [dev|staging|production] [plan|apply|destroy]

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to print colored output
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
    echo -e "${BLUE}[DEPLOY]${NC} $1"
}

# Validate arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <environment> <action>"
    echo "  environment: dev, staging, production"
    echo "  action: plan, apply, destroy"
    exit 1
fi

ENVIRONMENT=$1
ACTION=$2
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/provisioning"
ANSIBLE_DIR="$PROJECT_ROOT/configuration-management"
ENV_DIR="$PROJECT_ROOT/environments/$ENVIRONMENT"

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|production)$ ]]; then
    print_error "Invalid environment: $ENVIRONMENT"
    exit 1
fi

# Validate action
if [[ ! "$ACTION" =~ ^(plan|apply|destroy)$ ]]; then
    print_error "Invalid action: $ACTION"
    exit 1
fi

# Check if environment configuration exists
if [ ! -d "$ENV_DIR" ]; then
    print_error "Environment configuration not found: $ENV_DIR"
    exit 1
fi

print_header "Deploying $ENVIRONMENT environment - Action: $ACTION"

# Function to setup Terraform
setup_terraform() {
    print_info "Setting up Terraform configuration..."
    
    # Copy environment-specific configuration
    cp "$ENV_DIR/terraform.tfvars" "$TERRAFORM_DIR/"
    cp "$ENV_DIR/backend.tf" "$TERRAFORM_DIR/"
    
    # Initialize Terraform
    cd "$TERRAFORM_DIR"
    terraform init
    
    print_info "Terraform setup completed"
}

# Function to run Terraform plan
terraform_plan() {
    print_info "Running Terraform plan..."
    
    cd "$TERRAFORM_DIR"
    
    if [ "$ACTION" == "destroy" ]; then
        terraform plan -destroy -var-file=terraform.tfvars -out=tfplan
    else
        terraform plan -var-file=terraform.tfvars -out=tfplan
    fi
    
    print_info "Terraform plan completed"
}

# Function to run Terraform apply
terraform_apply() {
    print_info "Running Terraform apply..."
    
    cd "$TERRAFORM_DIR"
    terraform apply -auto-approve tfplan
    
    print_info "Terraform apply completed"
}

# Function to setup Ansible inventory
setup_ansible() {
    if [ "$ACTION" == "destroy" ]; then
        print_info "Skipping Ansible setup for destroy action"
        return
    fi
    
    print_info "Setting up Ansible configuration..."
    
    # Get Terraform outputs
    cd "$TERRAFORM_DIR"
    VM_IP=$(terraform output -raw public_ip_address 2>/dev/null || echo "")
    VM_NAME=$(terraform output -raw vm_name 2>/dev/null || echo "")
    
    if [ -z "$VM_IP" ] || [ -z "$VM_NAME" ]; then
        print_error "Could not get VM information from Terraform outputs"
        exit 1
    fi
    
    print_info "VM IP: $VM_IP, VM Name: $VM_NAME"
    
    # Create inventory file
    mkdir -p "$ANSIBLE_DIR/inventory"
    cat > "$ANSIBLE_DIR/inventory/hosts.yml" << EOF
all:
  children:
    azure_vms:
      hosts:
        $VM_NAME:
          ansible_host: $VM_IP
          ansible_user: azureuser
          ansible_ssh_private_key_file: ~/.ssh/id_rsa
          ansible_python_interpreter: /usr/bin/python3
      vars:
        ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
        environment_name: "$ENVIRONMENT"
EOF
    
    # Copy environment-specific Ansible variables
    cp "$ENV_DIR/ansible_vars.yml" "$ANSIBLE_DIR/group_vars/azure_vms.yml"
    
    print_info "Ansible setup completed"
}

# Function to run Ansible deployment
run_ansible() {
    if [ "$ACTION" == "destroy" ]; then
        print_info "Skipping Ansible deployment for destroy action"
        return
    fi
    
    print_info "Running Ansible deployment..."
    
    cd "$ANSIBLE_DIR"
    
    # Install required collections
    ansible-galaxy collection install -r requirements.yml --force
    
    # Wait for VM to be ready
    print_info "Waiting for VM to be ready..."
    for i in {1..10}; do
        if ansible all -m ping -i inventory/hosts.yml >/dev/null 2>&1; then
            print_info "VM is ready!"
            break
        fi
        print_warning "Waiting for VM... (attempt $i/10)"
        sleep 30
    done
    
    # Run the playbook
    ansible-playbook -i inventory/hosts.yml site.yml --ssh-extra-args='-o StrictHostKeyChecking=no' -v
    
    print_info "Ansible deployment completed"
}

# Function to run tests
run_tests() {
    if [ "$ACTION" == "destroy" ]; then
        print_info "Skipping tests for destroy action"
        return
    fi
    
    print_info "Running deployment tests..."
    
    cd "$PROJECT_ROOT"
    
    # Check if pytest is available
    if command -v pytest >/dev/null 2>&1; then
        python -m pytest tests/test_deployment.py -v --env="$ENVIRONMENT" || print_warning "Some tests failed"
    else
        print_warning "pytest not available, skipping tests"
    fi
    
    print_info "Tests completed"
}

# Function to show deployment summary
show_summary() {
    if [ "$ACTION" == "destroy" ]; then
        print_header "Destroy operation completed for $ENVIRONMENT environment"
        return
    fi
    
    print_header "Deployment Summary"
    echo "=================="
    
    cd "$TERRAFORM_DIR"
    if [ -f "terraform.tfstate" ]; then
        echo "Environment: $ENVIRONMENT"
        echo "VM Name: $(terraform output -raw vm_name 2>/dev/null || echo 'N/A')"
        echo "Public IP: $(terraform output -raw public_ip_address 2>/dev/null || echo 'N/A')"
        echo "Resource Group: $(terraform output -raw resource_group_name 2>/dev/null || echo 'N/A')"
        echo "SSH Command: $(terraform output -raw ssh_connection_command 2>/dev/null || echo 'N/A')"
        
        VM_IP=$(terraform output -raw public_ip_address 2>/dev/null || echo "")
        if [ -n "$VM_IP" ]; then
            echo "Web URL: http://$VM_IP"
        fi
    else
        print_warning "No Terraform state found"
    fi
    
    echo ""
    print_info "Deployment completed successfully!"
}

# Main execution flow
main() {
    print_header "Starting deployment process..."
    
    # Check prerequisites
    command -v terraform >/dev/null 2>&1 || { print_error "terraform not found"; exit 1; }
    command -v ansible >/dev/null 2>&1 || { print_error "ansible not found"; exit 1; }
    
    # Setup and run Terraform
    setup_terraform
    terraform_plan
    
    if [ "$ACTION" != "plan" ]; then
        # Additional confirmation for production
        if [ "$ENVIRONMENT" == "production" ] && [ "$ACTION" == "apply" ]; then
            print_warning "You are about to deploy to PRODUCTION!"
            read -p "Are you sure you want to continue? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Deployment cancelled"
                exit 0
            fi
        fi
        
        terraform_apply
        
        if [ "$ACTION" == "apply" ]; then
            setup_ansible
            run_ansible
            run_tests
        fi
    fi
    
    show_summary
}

# Run main function
main "$@"
