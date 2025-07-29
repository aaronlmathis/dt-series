# DevOps CI/CD Pipeline Setup Guide

This guide explains how to set up and use the production-ready CI/CD pipeline with GitHub Actions for automated Terraform and Ansible deployments with multi-environment support.

## 🏗️ Architecture Overview

The CI/CD pipeline implements:

- **Multi-Environment Strategy**: Separate dev, staging, and production environments
- **GitOps Workflows**: Pull request-based infrastructure changes
- **Security & Compliance**: Automated security scanning and approval processes
- **Disaster Recovery**: Automated rollback and recovery capabilities
- **Azure OIDC Integration**: Secure authentication without storing credentials

## 🚀 Quick Start

### 1. Prerequisites

- Azure subscription with appropriate permissions
- GitHub repository with Actions enabled
- Azure CLI installed locally
- Terraform and Ansible installed locally

### 2. Initial Setup

1. **Setup Azure Backend Storage** (one-time setup):
   ```bash
   # Login to Azure
   az login
   
   # Run setup script
   make setup-backend
   ```

2. **Create Service Principal for GitHub Actions**:
   ```bash
   # Create service principal with OIDC
   az ad app create --display-name "dt-series-github-actions"
   
   # Get the application ID
   APP_ID=$(az ad app list --display-name "dt-series-github-actions" --query '[0].appId' -o tsv)
   
   # Create service principal
   az ad sp create --id $APP_ID
   
   # Get the object ID
   OBJECT_ID=$(az ad sp list --display-name "dt-series-github-actions" --query '[0].objectId' -o tsv)
   
   # Assign contributor role
   az role assignment create --role contributor --assignee-object-id $OBJECT_ID --assignee-principal-type ServicePrincipal --scope /subscriptions/$(az account show --query id -o tsv)
   
   # Configure federated credentials for GitHub Actions
   az ad app federated-credential create --id $APP_ID --parameters '{
     "name": "GitHubActions",
     "issuer": "https://token.actions.githubusercontent.com",
     "subject": "repo:aaronlmathis/dt-series:ref:refs/heads/main",
     "description": "GitHub Actions OIDC",
     "audiences": ["api://AzureADTokenExchange"]
   }'
   ```

3. **Configure GitHub Secrets**:
   Go to your repository Settings → Secrets and variables → Actions, and add:
   
   - `AZURE_CLIENT_ID`: The application (client) ID
   - `AZURE_TENANT_ID`: Your Azure tenant ID
   - `AZURE_SUBSCRIPTION_ID`: Your Azure subscription ID
   - `SSH_PRIVATE_KEY`: Your SSH private key for VM access

   ```bash
   # Get the required values
   echo "AZURE_CLIENT_ID: $APP_ID"
   echo "AZURE_TENANT_ID: $(az account show --query tenantId -o tsv)"
   echo "AZURE_SUBSCRIPTION_ID: $(az account show --query id -o tsv)"
   ```

### 3. Environment Configuration

Each environment has its own configuration in the `environments/` directory:

- `environments/dev/` - Development environment
- `environments/staging/` - Staging environment  
- `environments/production/` - Production environment

## 🔄 CI/CD Workflows

### Pull Request Validation

**Trigger**: Pull requests to `main` or `develop` branches

**Process**:
1. Security scanning (Trivy, Checkov)
2. Terraform validation for all environments
3. Ansible syntax checking and linting
4. Integration tests
5. PR comment with results

### Development Deployment

**Trigger**: Push to `develop` branch

**Process**:
1. Terraform plan and apply for dev environment
2. Ansible configuration deployment
3. Post-deployment testing
4. Automatic deployment on success

### Staging Deployment

**Trigger**: Successful development deployment

**Process**:
1. Terraform plan and apply for staging environment
2. Ansible configuration deployment
3. Comprehensive testing (deployment, security, performance)
4. Manual approval gate for production

### Production Deployment

**Trigger**: Manual approval after successful staging deployment

**Process**:
1. Manual approval checkpoint
2. Production data backup
3. Terraform plan and apply for production environment
4. Ansible configuration deployment
5. Production smoke tests
6. Deployment notifications

### Disaster Recovery & Rollback

**Trigger**: Manual workflow dispatch

**Features**:
- Rollback to previous successful deployment
- Infrastructure and/or configuration rollback
- Automated backup before rollback
- Validation and testing after rollback

## 🛠️ Local Development

### Using the Enhanced Makefile

```bash
# Deploy to different environments
make dev          # Deploy to development
make staging      # Deploy to staging  
make production   # Deploy to production

# Environment-specific commands
make plan ENV=staging           # Plan for staging
make ssh ENV=production        # SSH to production VM
make test ENV=dev             # Test development deployment

# Validation and testing
make validate-all             # Run all validations
make security-scan           # Run security scans
make test-infrastructure     # Test infrastructure config
```

### Using Deployment Scripts

```bash
# Full deployment with script
./scripts/deploy-environment.sh dev apply
./scripts/deploy-environment.sh staging plan
./scripts/deploy-environment.sh production destroy
```

## 🔒 Security Features

### Automated Security Scanning

- **Trivy**: Vulnerability scanning for infrastructure as code
- **Checkov**: Policy and compliance checking
- **Ansible Lint**: Ansible best practices validation

### Infrastructure Security

- SSH key-based authentication only
- Fail2ban intrusion prevention
- UFW firewall configuration
- System hardening with CIS benchmarks
- Network security groups with minimal access

### CI/CD Security

- Azure OIDC for secure authentication
- Environment-specific approvals
- Secret management through GitHub Secrets
- Audit trail of all deployments

## 📊 Testing Strategy

### Infrastructure Tests (`tests/test_infrastructure.py`)

- Environment configuration validation
- Security settings verification
- Multi-environment isolation checks

### Deployment Tests (`tests/test_deployment.py`)

- VM accessibility and service health
- Security configuration validation
- Performance baseline checks

### Security Tests (`tests/test_security.py`)

- SSH hardening verification
- Firewall and network security
- User account and permission audits

### Performance Tests (`tests/test_performance.py`)

- Response time validation
- Load and stress testing
- Resource utilization monitoring

## 🎯 Environment Management

### Development Environment

- **Purpose**: Feature development and testing
- **Access**: More permissive security settings
- **Resources**: Smaller VM sizes for cost efficiency
- **Deployment**: Automatic on `develop` branch push

### Staging Environment

- **Purpose**: Pre-production testing and validation
- **Access**: Production-like security settings
- **Resources**: Production-equivalent resources
- **Deployment**: Automatic after dev deployment success

### Production Environment

- **Purpose**: Live production workloads
- **Access**: Strict security settings
- **Resources**: Optimized for performance and reliability
- **Deployment**: Manual approval required

## 🚨 Disaster Recovery

### Rollback Procedures

1. **Manual Rollback via GitHub Actions**:
   - Go to Actions → Disaster Recovery & Rollback
   - Select environment and rollback type
   - Provide rollback reason
   - Approve execution

2. **Emergency Rollback**:
   ```bash
   # Local emergency rollback
   make rollback ENV=production
   ```

### Backup Strategy

- Automated pre-deployment backups
- Terraform state backup
- Configuration backup
- Application data backup (if applicable)

## 📈 Monitoring and Alerting

### Built-in Monitoring

- Azure Monitor integration
- System health checks
- Performance monitoring
- Security event logging

### Deployment Monitoring

- GitHub Actions workflow status
- Deployment success/failure notifications
- Test result reporting
- Security scan results

## 🔧 Troubleshooting

### Common Issues

1. **Azure Authentication Errors**:
   - Verify OIDC configuration
   - Check GitHub secrets
   - Validate service principal permissions

2. **Terraform State Issues**:
   - Verify backend storage configuration
   - Check state file permissions
   - Validate storage account access

3. **Ansible Connection Issues**:
   - Verify SSH key configuration
   - Check VM network security groups
   - Validate inventory file generation

### Debug Commands

```bash
# Check environment configuration
make check-env ENV=staging

# Validate all configurations
make validate-all

# Run specific tests
make test-deployment ENV=dev

# Check infrastructure status
make status ENV=production
```

## 📝 Best Practices

### Development Workflow

1. Create feature branch from `develop`
2. Make infrastructure/configuration changes
3. Test locally with `make dev`
4. Create pull request to `develop`
5. Review automated validation results
6. Merge after approval
7. Monitor automatic deployment to dev
8. Promote to staging when ready
9. Manual approval for production deployment

### Security Practices

1. Regular security scans
2. Principle of least privilege
3. Environment-specific access controls
4. Audit trail maintenance
5. Regular backup testing

### Operational Practices

1. Monitor deployment metrics
2. Regular infrastructure reviews
3. Performance baseline maintenance
4. Disaster recovery testing
5. Documentation updates

## 📞 Support

For issues or questions:

1. Check the troubleshooting section
2. Review GitHub Actions logs
3. Validate environment configurations
4. Test with local deployment scripts

## 🔄 Continuous Improvement

The CI/CD pipeline is designed to evolve with your needs:

- Add new environments as required
- Integrate additional security tools
- Expand testing coverage
- Enhance monitoring capabilities
- Implement advanced deployment strategies
