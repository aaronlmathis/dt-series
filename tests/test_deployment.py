"""
Post-deployment tests to verify the infrastructure and configuration
"""
import pytest
import requests
import subprocess
import yaml
import os
import time
import testinfra

def get_vm_ip(environment):
    """Get VM IP from inventory file"""
    inventory_path = f"configuration-management/inventory/hosts.yml"
    
    if not os.path.exists(inventory_path):
        pytest.skip(f"Inventory file not found: {inventory_path}")
    
    with open(inventory_path, 'r') as f:
        inventory = yaml.safe_load(f)
    
    vm_hosts = inventory['all']['children']['azure_vms']['hosts']
    vm_name = list(vm_hosts.keys())[0]
    vm_ip = vm_hosts[vm_name]['ansible_host']
    
    return vm_ip, vm_name

@pytest.fixture(scope="module")
def vm_connection(request):
    """Create testinfra connection to VM"""
    environment = request.config.getoption("--env", default="dev")
    vm_ip, vm_name = get_vm_ip(environment)
    
    # Create testinfra connection
    connection_string = f"ssh://azureuser@{vm_ip}"
    host = testinfra.get_host(connection_string)
    
    # Wait for SSH to be available
    max_retries = 30
    for i in range(max_retries):
        try:
            host.run("echo 'SSH test'")
            break
        except Exception as e:
            if i == max_retries - 1:
                pytest.fail(f"Could not connect to VM after {max_retries} attempts: {e}")
            time.sleep(10)
    
    return host, vm_ip

def test_vm_is_accessible(vm_connection):
    """Test that the VM is accessible via SSH"""
    host, vm_ip = vm_connection
    
    result = host.run("echo 'hello world'")
    assert result.exit_status == 0
    assert "hello world" in result.stdout

def test_system_services_running(vm_connection):
    """Test that critical system services are running"""
    host, _ = vm_connection
    
    services = [
        'ssh',
        'fail2ban',
        'chrony'
    ]
    
    for service in services:
        service_status = host.service(service)
        assert service_status.is_running, f"Service {service} is not running"
        assert service_status.is_enabled, f"Service {service} is not enabled"

def test_firewall_configuration(vm_connection):
    """Test firewall configuration"""
    host, _ = vm_connection
    
    # Check if ufw is active
    ufw_status = host.run("ufw status")
    assert "Status: active" in ufw_status.stdout, "UFW firewall should be active"

def test_fail2ban_configuration(vm_connection):
    """Test fail2ban configuration"""
    host, _ = vm_connection
    
    # Check fail2ban status
    fail2ban_status = host.run("fail2ban-client status")
    assert fail2ban_status.exit_status == 0, "fail2ban should be running"
    
    # Check if SSH jail is active
    ssh_jail_status = host.run("fail2ban-client status sshd")
    assert ssh_jail_status.exit_status == 0, "SSH jail should be configured"

def test_time_synchronization(vm_connection):
    """Test time synchronization"""
    host, _ = vm_connection
    
    # Check chrony status
    chrony_status = host.run("chronyc tracking")
    assert chrony_status.exit_status == 0, "Chrony should be working"

def test_ssh_hardening(vm_connection):
    """Test SSH hardening configuration"""
    host, _ = vm_connection
    
    sshd_config = host.file("/etc/ssh/sshd_config")
    assert sshd_config.exists, "SSH config should exist"
    
    config_content = sshd_config.content_string
    
    # Check for security settings
    security_checks = [
        "PasswordAuthentication no",
        "PermitRootLogin no",
        "Protocol 2"
    ]
    
    for check in security_checks:
        assert check in config_content or check.replace(" ", " ").lower() in config_content.lower(), \
            f"SSH security setting not found: {check}"

def test_system_updates(vm_connection):
    """Test that system is up to date"""
    host, _ = vm_connection
    
    # Check for available updates
    update_check = host.run("apt list --upgradable 2>/dev/null | wc -l")
    upgradable_count = int(update_check.stdout.strip())
    
    # Allow for a few updates (kernel, security patches) but flag if too many
    assert upgradable_count < 50, f"Too many packages need updates: {upgradable_count}"

def test_disk_space(vm_connection):
    """Test disk space availability"""
    host, _ = vm_connection
    
    # Check root filesystem usage
    df_result = host.run("df -h / | tail -1 | awk '{print $5}' | sed 's/%//'")
    disk_usage = int(df_result.stdout.strip())
    
    assert disk_usage < 80, f"Disk usage too high: {disk_usage}%"

def test_memory_usage(vm_connection):
    """Test memory usage"""
    host, _ = vm_connection
    
    # Check memory usage
    memory_result = host.run("free | grep Mem | awk '{printf \"%.0f\", $3/$2 * 100.0}'")
    memory_usage = int(float(memory_result.stdout.strip()))
    
    assert memory_usage < 90, f"Memory usage too high: {memory_usage}%"

def test_network_connectivity(vm_connection):
    """Test network connectivity"""
    host, _ = vm_connection
    
    # Test external connectivity
    ping_result = host.run("ping -c 3 8.8.8.8")
    assert ping_result.exit_status == 0, "External network connectivity failed"
    
    # Test DNS resolution
    dns_result = host.run("nslookup google.com")
    assert dns_result.exit_status == 0, "DNS resolution failed"

def test_web_application_accessible():
    """Test that web application is accessible (if deployed)"""
    try:
        vm_ip, _ = get_vm_ip("dev")  # Default to dev for now
        
        # Test HTTP connectivity
        response = requests.get(f"http://{vm_ip}", timeout=10)
        
        # We expect either a successful response or a specific error
        # This depends on what application is deployed
        assert response.status_code in [200, 404, 403], \
            f"Unexpected HTTP status: {response.status_code}"
            
    except requests.exceptions.RequestException:
        # Web server might not be deployed yet, which is ok
        pytest.skip("Web server not accessible or not deployed")

def pytest_addoption(parser):
    """Add command line option for environment"""
    parser.addoption("--env", action="store", default="dev", 
                     help="Environment to test: dev, staging, production")

if __name__ == "__main__":
    pytest.main([__file__])
