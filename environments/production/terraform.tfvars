 # Production Environment Configuration
resource_group_name = "dt-series-prod-rg"
environment = "production"
location = "East US 2"  # Different region for production
vm_name = "dt-series-prod-vm"
vm_size = "Standard_B4ms"  # Larger instance for production
admin_username = "azureuser"
ssh_allowed_cidr = "10.0.0.0/8"  # Restrictive access
vnet_name = "dt-series-prod-vnet"
vnet_address_space = "10.2.0.0/16"
subnet_name = "dt-series-prod-subnet"
subnet_prefix = "10.2.1.0/24"
budget_amount = 200
budget_threshold_percentage = 60
alert_emails = ["ops-team@example.com", "alerts@example.com"]
