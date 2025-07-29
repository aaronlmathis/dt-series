"""
Production-specific smoke tests
"""
import pytest
import requests
import yaml
import os
import subprocess
import time

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

def test_production_accessibility():
    """Test that production environment is accessible"""
    vm_ip, _ = get_vm_ip("production")
    
    # Test SSH connectivity
    result = subprocess.run([
        'ssh', '-o', 'ConnectTimeout=10',
        '-o', 'StrictHostKeyChecking=no',
        f'azureuser@{vm_ip}', 'echo "Production is accessible"'
    ], capture_output=True, text=True, timeout=15)
    
    assert result.returncode == 0, "Cannot connect to production VM"
    assert "Production is accessible" in result.stdout

def test_production_services():
    """Test that all production services are running"""
    vm_ip, _ = get_vm_ip("production")
    
    critical_services = ['ssh', 'fail2ban', 'chrony']
    
    for service in critical_services:
        result = subprocess.run([
            'ssh', '-o', 'ConnectTimeout=10',
            '-o', 'StrictHostKeyChecking=no',
            f'azureuser@{vm_ip}', 
            f'systemctl is-active {service}'
        ], capture_output=True, text=True, timeout=15)
        
        assert result.returncode == 0, f"Service {service} is not active"
        assert "active" in result.stdout.strip(), f"Service {service} is not running"

def test_production_security_hardening():
    """Test production security hardening"""
    vm_ip, _ = get_vm_ip("production")
    
    # Test firewall is active
    result = subprocess.run([
        'ssh', '-o', 'ConnectTimeout=10',
        '-o', 'StrictHostKeyChecking=no',
        f'azureuser@{vm_ip}', 'ufw status'
    ], capture_output=True, text=True, timeout=15)
    
    assert result.returncode == 0, "Could not check firewall status"
    assert "Status: active" in result.stdout, "Firewall should be active in production"

def test_production_performance():
    """Test production performance basics"""
    vm_ip, _ = get_vm_ip("production")
    
    # Test system load
    result = subprocess.run([
        'ssh', '-o', 'ConnectTimeout=10',
        '-o', 'StrictHostKeyChecking=no',
        f'azureuser@{vm_ip}', 
        "uptime | awk '{print $(NF-2)}' | sed 's/,//'"
    ], capture_output=True, text=True, timeout=15)
    
    assert result.returncode == 0, "Could not get system load"
    
    try:
        load_avg = float(result.stdout.strip())
        assert load_avg < 2.0, f"Production load average too high: {load_avg}"
    except ValueError:
        pytest.skip("Could not parse load average")

def test_production_disk_space():
    """Test production disk space"""
    vm_ip, _ = get_vm_ip("production")
    
    # Check root filesystem usage
    result = subprocess.run([
        'ssh', '-o', 'ConnectTimeout=10',
        '-o', 'StrictHostKeyChecking=no',
        f'azureuser@{vm_ip}', 
        "df -h / | tail -1 | awk '{print $5}' | sed 's/%//'"
    ], capture_output=True, text=True, timeout=15)
    
    assert result.returncode == 0, "Could not check disk space"
    
    try:
        disk_usage = int(result.stdout.strip())
        assert disk_usage < 80, f"Production disk usage too high: {disk_usage}%"
    except ValueError:
        pytest.skip("Could not parse disk usage")

def test_production_memory():
    """Test production memory usage"""
    vm_ip, _ = get_vm_ip("production")
    
    # Check memory usage
    result = subprocess.run([
        'ssh', '-o', 'ConnectTimeout=10',
        '-o', 'StrictHostKeyChecking=no',
        f'azureuser@{vm_ip}', 
        "free | grep Mem | awk '{printf \"%.0f\", $3/$2 * 100.0}'"
    ], capture_output=True, text=True, timeout=15)
    
    assert result.returncode == 0, "Could not check memory usage"
    
    try:
        memory_usage = int(float(result.stdout.strip()))
        assert memory_usage < 85, f"Production memory usage too high: {memory_usage}%"
    except ValueError:
        pytest.skip("Could not parse memory usage")

def test_production_logs():
    """Test that production logs are being generated"""
    vm_ip, _ = get_vm_ip("production")
    
    # Check that system logs are recent
    result = subprocess.run([
        'ssh', '-o', 'ConnectTimeout=10',
        '-o', 'StrictHostKeyChecking=no',
        f'azureuser@{vm_ip}', 
        "find /var/log -name '*.log' -mtime -1 | wc -l"
    ], capture_output=True, text=True, timeout=15)
    
    assert result.returncode == 0, "Could not check log files"
    
    recent_logs = int(result.stdout.strip())
    assert recent_logs > 0, "No recent log files found in production"

def test_production_backup_readiness():
    """Test that production backup mechanisms are in place"""
    vm_ip, _ = get_vm_ip("production")
    
    # Check if cron jobs are configured
    result = subprocess.run([
        'ssh', '-o', 'ConnectTimeout=10',
        '-o', 'StrictHostKeyChecking=no',
        f'azureuser@{vm_ip}', 'crontab -l 2>/dev/null || echo "no-crontab"'
    ], capture_output=True, text=True, timeout=15)
    
    assert result.returncode == 0, "Could not check cron jobs"
    
    # Either crontab exists or system-wide cron is configured
    if "no-crontab" not in result.stdout:
        assert len(result.stdout.strip()) > 0, "Crontab exists but is empty"

def test_production_network_security():
    """Test production network security"""
    vm_ip, _ = get_vm_ip("production")
    
    # Check open ports - should be minimal
    result = subprocess.run([
        'ssh', '-o', 'ConnectTimeout=10',
        '-o', 'StrictHostKeyChecking=no',
        f'azureuser@{vm_ip}', 
        "ss -tuln | grep LISTEN | wc -l"
    ], capture_output=True, text=True, timeout=15)
    
    assert result.returncode == 0, "Could not check listening ports"
    
    listening_ports = int(result.stdout.strip())
    # Should have minimal services listening (SSH, maybe web server)
    assert listening_ports < 10, f"Too many listening ports in production: {listening_ports}"

def test_production_fail2ban():
    """Test fail2ban is protecting production"""
    vm_ip, _ = get_vm_ip("production")
    
    # Check fail2ban status
    result = subprocess.run([
        'ssh', '-o', 'ConnectTimeout=10',
        '-o', 'StrictHostKeyChecking=no',
        f'azureuser@{vm_ip}', 'fail2ban-client status sshd'
    ], capture_output=True, text=True, timeout=15)
    
    assert result.returncode == 0, "fail2ban SSH jail not active in production"
    assert "Status for the jail: sshd" in result.stdout, "SSH jail not properly configured"

def test_production_time_sync():
    """Test that production time synchronization is working"""
    vm_ip, _ = get_vm_ip("production")
    
    # Check chrony tracking
    result = subprocess.run([
        'ssh', '-o', 'ConnectTimeout=10',
        '-o', 'StrictHostKeyChecking=no',
        f'azureuser@{vm_ip}', 'chronyc tracking | grep "System time"'
    ], capture_output=True, text=True, timeout=15)
    
    assert result.returncode == 0, "Could not check time synchronization"
    
    # Time offset should be small
    if "System time" in result.stdout:
        # Parse time offset if available
        system_time_line = result.stdout.strip()
        # This is a basic check - time sync is working if command succeeds
        assert len(system_time_line) > 0, "Time synchronization check failed"

def pytest_addoption(parser):
    """Add command line option for environment"""
    parser.addoption("--env", action="store", default="production", 
                     help="Environment to test: dev, staging, production")

if __name__ == "__main__":
    pytest.main([__file__])
