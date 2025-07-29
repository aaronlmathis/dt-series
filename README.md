# Azure VM Infrastructure Automation with Enterprise CI/CD

A production-ready infrastructure automation project demonstrating enterprise DevOps practices with Terraform, Ansible, and GitHub Actions for deploying hardened Azure VMs across multiple environments.

## 🏗️ Project Overview

This project showcases a complete DevOps automation pipeline featuring:

- **Infrastructure as Code** with Terraform
- **Configuration Management** with Ansible
- **Multi-Environment Strategy** (dev, staging, production)
- **Production-Ready CI/CD** with GitHub Actions
- **Security & Compliance** automation
- **GitOps Workflows** with approval processes
- **Disaster Recovery** and rollback capabilities

## 🚀 Quick Start

### Prerequisites

- Azure subscription with appropriate permissions
- GitHub repository with Actions enabled
- Local development tools: Terraform, Ansible, Azure CLI

### Initial Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/aaronlmathis/dt-series.git
   cd dt-series
   ```

2. **Setup Azure backend storage**:
   ```bash
   az login
   make setup-backend
   ```

3. **Configure GitHub secrets** (see [CI/CD Setup Guide](CICD_SETUP.md))

4. **Deploy to development**:
   ```bash
   make dev
   ```

## 📁 Project Structure

```
├── .github/workflows/          # GitHub Actions CI/CD workflows
│   ├── pr-validation.yml       # Pull request validation
│   ├── deploy-dev.yml          # Development deployment
│   ├── deploy-staging.yml      # Staging deployment
│   ├── deploy-production.yml   # Production deployment
│   ├── disaster-recovery.yml   # Rollback and recovery
│   └── environment-promotion.yml
├── configuration-management/   # Ansible configuration
│   ├── site.yml               # Main playbook
│   ├── group_vars/            # Variable definitions
│   ├── inventory/             # Dynamic inventory
│   ├── roles/                 # Ansible roles
│   │   ├── system-hardening/
│   │   ├── firewall/
│   │   ├── ssh-hardening/
│   │   ├── fail2ban/
│   │   ├── time-sync/
│   │   ├── azure-monitor/
│   │   └── cron-jobs/
│   └── requirements.yml       # Ansible collections
├── environments/              # Environment-specific configurations
│   ├── dev/
│   ├── staging/
│   └── production/
├── provisioning/              # Terraform infrastructure
│   ├── main.tf               # Main infrastructure
│   ├── variables.tf          # Variable definitions
│   ├── outputs.tf            # Output values
│   └── locals.tf             # Local values
├── scripts/                   # Utility scripts
│   ├── deploy-environment.sh  # Environment deployment
│   └── setup-azure-backend.sh
├── tests/                     # Automated tests
│   ├── test_infrastructure.py
│   ├── test_deployment.py
│   ├── test_security.py
│   ├── test_performance.py
│   └── test_production.py
├── Makefile                   # Enhanced automation
└── CICD_SETUP.md             # Detailed setup guide
```

## 🎯 Multi-Environment Strategy

### Development Environment
- **Purpose**: Feature development and testing
- **Deployment**: Automatic on `develop` branch push
- **Resources**: Cost-optimized (Standard_B1s)
- **Security**: Relaxed for development productivity

### Staging Environment
- **Purpose**: Pre-production validation
- **Deployment**: Automatic after successful dev deployment
- **Resources**: Production-equivalent (Standard_B2s)
- **Security**: Production-like settings

### Production Environment
- **Purpose**: Live production workloads
- **Deployment**: Manual approval required
- **Resources**: Performance-optimized (Standard_B4ms)
- **Security**: Strict hardening and monitoring

## 🔄 CI/CD Workflows

### GitOps Process

1. **Pull Request Validation**:
   - Security scanning (Trivy, Checkov)
   - Terraform validation across all environments
   - Ansible linting and syntax checking
   - Integration tests

2. **Development Deployment**:
   - Triggered by push to `develop` branch
   - Automated infrastructure provisioning
   - Configuration management with Ansible
   - Post-deployment testing

3. **Staging Promotion**:
   - Triggered by successful dev deployment
   - Comprehensive testing suite
   - Performance validation
   - Security compliance checks

4. **Production Deployment**:
   - Manual approval required
   - Pre-deployment backup
   - Blue-green deployment capability
   - Smoke tests and monitoring

5. **Disaster Recovery**:
   - One-click rollback capability
   - Automated backup and restore
   - Multi-level rollback (config/infrastructure/full)

## 🛠️ Local Development

### Using the Enhanced Makefile

```bash
# Environment deployment
make dev              # Deploy to development
make staging          # Deploy to staging
make production       # Deploy to production

# Environment-specific operations
make plan ENV=staging          # Plan changes for staging
make ssh ENV=production       # SSH to production VM
make status ENV=dev          # Check dev environment status

# Testing and validation
make validate-all            # Validate all configurations
make security-scan          # Run security scans
make test-deployment ENV=dev # Test specific environment
```

### Using Deployment Scripts

```bash
# Full deployment
./scripts/deploy-environment.sh dev apply

# Plan only
./scripts/deploy-environment.sh staging plan

# Destroy environment
./scripts/deploy-environment.sh dev destroy
```

## 🔒 Security Features

### Infrastructure Security
- **Network Security**: NSGs with minimal required access
- **SSH Hardening**: Key-based authentication, fail2ban protection
- **System Hardening**: CIS benchmark compliance
- **Firewall**: UFW with restrictive default policies
- **Monitoring**: Azure Monitor integration

### CI/CD Security
- **OIDC Authentication**: No stored credentials in GitHub
- **Environment Protection**: Manual approvals for production
- **Secret Management**: GitHub Secrets for sensitive data
- **Security Scanning**: Automated vulnerability detection
- **Audit Trail**: Complete deployment history

## 📊 Testing Strategy

### Automated Testing
- **Infrastructure Tests**: Configuration validation
- **Deployment Tests**: Service health and connectivity
- **Security Tests**: Compliance and hardening verification
- **Performance Tests**: Load and response time validation
- **Production Smoke Tests**: Critical functionality verification

### Test Execution
```bash
# Run all tests
make test-infrastructure
make test-deployment ENV=staging
make test-security ENV=production

# Or use pytest directly
cd tests
python -m pytest test_deployment.py -v --env=dev
```

## 🚨 Disaster Recovery

### Rollback Capabilities

1. **GitHub Actions Workflow**:
   - Navigate to Actions → "Disaster Recovery & Rollback"
   - Select environment and rollback type
   - Provide justification and execute

2. **Local Emergency Rollback**:
   ```bash
   make rollback ENV=production
   ```

### Backup Strategy
- Automated pre-deployment backups
- Terraform state preservation
- Configuration snapshots
- Application data backup (when applicable)

## 📈 Monitoring and Observability

### Built-in Monitoring
- Azure Monitor integration for system metrics
- Security event logging and alerting
- Performance baseline monitoring
- Deployment status tracking

### Operational Insights
- Real-time infrastructure health
- Security compliance dashboards
- Deployment success metrics
- Cost optimization tracking

## 🔧 Troubleshooting

### Common Issues

1. **Azure Authentication**:
   ```bash
   # Verify OIDC setup
   az ad app list --display-name "dt-series-github-actions"
   ```

2. **Terraform State**:
   ```bash
   # Check backend configuration
   make check-env ENV=staging
   ```

3. **Ansible Connectivity**:
   ```bash
   # Test VM connectivity
   make ssh ENV=dev
   ```

### Debug Commands
```bash
# Comprehensive validation
make validate-all

# Environment-specific status
make status ENV=production

# View deployment logs
make logs
```

## 📚 Documentation

- **[CI/CD Setup Guide](CICD_SETUP.md)**: Comprehensive setup instructions

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch from `develop`
3. Make your changes
4. Test locally with `make dev`
5. Create a pull request
6. Automated validation will run
7. Merge after approval

## 📝 Best Practices

### Development Workflow
- Feature branches from `develop`
- Local testing before PR
- Comprehensive PR descriptions
- Code review requirements
- Automated validation gates

### Security Practices
- Regular security scans
- Least privilege access
- Environment isolation
- Audit trail maintenance
- Incident response procedures

### Operational Excellence
- Infrastructure as Code principles
- Automated testing at all levels
- Continuous monitoring
- Regular backup testing
- Documentation maintenance

## 🏆 Enterprise Features

This project demonstrates enterprise-grade DevOps practices:

- **Multi-environment strategy** with proper promotion workflows
- **Infrastructure as Code** with Terraform for reproducible deployments
- **Configuration Management** with Ansible for consistent server setup
- **CI/CD automation** with GitHub Actions and approval workflows
- **Security-first approach** with automated scanning and hardening
- **Disaster recovery** capabilities with automated rollback
- **Monitoring and observability** for operational excellence
- **GitOps workflows** for audit trails and collaboration

## 🚀 Next Steps

Explore advanced features:

1. **Blue-Green Deployments**: Zero-downtime deployments
2. **Canary Releases**: Gradual rollout strategies
3. **Infrastructure Drift Detection**: Automated compliance monitoring
4. **Cost Optimization**: Automated resource scaling
5. **Advanced Monitoring**: Custom dashboards and alerting

## 📞 Support

For questions or issues:

1. Check the [CI/CD Setup Guide](CICD_SETUP.md)
2. Review troubleshooting sections
3. Examine GitHub Actions logs
4. Validate environment configurations

---

**Built with ❤️ for enterprise DevOps excellence**
# Test change
