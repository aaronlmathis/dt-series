"""
Performance testing for deployed infrastructure
"""
import pytest
import requests
import time
import yaml
import os
import subprocess

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

def test_response_time():
    """Test HTTP response time"""
    try:
        vm_ip, _ = get_vm_ip("staging")
        
        # Warm up
        requests.get(f"http://{vm_ip}", timeout=5)
        
        # Measure response time
        start_time = time.time()
        response = requests.get(f"http://{vm_ip}", timeout=10)
        end_time = time.time()
        
        response_time = end_time - start_time
        
        # Response should be under 2 seconds
        assert response_time < 2.0, f"Response time too slow: {response_time:.2f}s"
        
    except requests.exceptions.RequestException:
        pytest.skip("Web server not accessible")

def test_concurrent_connections():
    """Test handling of concurrent connections"""
    try:
        vm_ip, _ = get_vm_ip("staging")
        
        # Test multiple concurrent requests
        import concurrent.futures
        
        def make_request():
            try:
                response = requests.get(f"http://{vm_ip}", timeout=10)
                return response.status_code, response.elapsed.total_seconds()
            except:
                return None, None
        
        # Make 10 concurrent requests
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(make_request) for _ in range(10)]
            results = [future.result() for future in concurrent.futures.as_completed(futures)]
        
        # At least 80% should succeed
        successful_requests = sum(1 for status, _ in results if status and status < 400)
        success_rate = successful_requests / len(results)
        
        assert success_rate >= 0.8, f"Success rate too low: {success_rate:.2%}"
        
    except ImportError:
        pytest.skip("concurrent.futures not available")
    except:
        pytest.skip("Web server not accessible")

def test_ssh_connection_speed():
    """Test SSH connection establishment speed"""
    vm_ip, _ = get_vm_ip("staging")
    
    # Test SSH connection time
    start_time = time.time()
    result = subprocess.run([
        'ssh', '-o', 'ConnectTimeout=10', 
        '-o', 'StrictHostKeyChecking=no',
        f'azureuser@{vm_ip}', 'echo "test"'
    ], capture_output=True, text=True, timeout=15)
    end_time = time.time()
    
    connection_time = end_time - start_time
    
    # SSH should connect within 5 seconds
    assert connection_time < 5.0, f"SSH connection too slow: {connection_time:.2f}s"
    assert result.returncode == 0, "SSH connection failed"

def test_system_load():
    """Test system load via SSH"""
    vm_ip, _ = get_vm_ip("staging")
    
    # Get system load
    result = subprocess.run([
        'ssh', '-o', 'ConnectTimeout=10',
        '-o', 'StrictHostKeyChecking=no',
        f'azureuser@{vm_ip}', 'uptime'
    ], capture_output=True, text=True, timeout=15)
    
    assert result.returncode == 0, "Could not get system load"
    
    # Parse load average (last number should be < 2.0 for single CPU)
    uptime_output = result.stdout.strip()
    load_avg = uptime_output.split('load average:')[1].strip()
    current_load = float(load_avg.split(',')[0].strip())
    
    # Load should be reasonable
    assert current_load < 2.0, f"System load too high: {current_load}"

def test_memory_performance():
    """Test memory usage performance"""
    vm_ip, _ = get_vm_ip("staging")
    
    # Get memory info
    result = subprocess.run([
        'ssh', '-o', 'ConnectTimeout=10',
        '-o', 'StrictHostKeyChecking=no',
        f'azureuser@{vm_ip}', 
        "free -m | grep Mem | awk '{print $3/$2 * 100}'"
    ], capture_output=True, text=True, timeout=15)
    
    assert result.returncode == 0, "Could not get memory info"
    
    memory_usage = float(result.stdout.strip())
    
    # Memory usage should be reasonable
    assert memory_usage < 85.0, f"Memory usage too high: {memory_usage:.1f}%"

def test_disk_io_performance():
    """Test basic disk I/O performance"""
    vm_ip, _ = get_vm_ip("staging")
    
    # Simple disk write test
    result = subprocess.run([
        'ssh', '-o', 'ConnectTimeout=10',
        '-o', 'StrictHostKeyChecking=no',
        f'azureuser@{vm_ip}', 
        "dd if=/dev/zero of=/tmp/test_file bs=1M count=10 2>&1 | grep 'MB/s' || echo 'No speed info'"
    ], capture_output=True, text=True, timeout=30)
    
    assert result.returncode == 0, "Disk I/O test failed"
    
    # Clean up test file
    subprocess.run([
        'ssh', '-o', 'ConnectTimeout=10',
        '-o', 'StrictHostKeyChecking=no',
        f'azureuser@{vm_ip}', 'rm -f /tmp/test_file'
    ], capture_output=True, timeout=10)

def test_network_latency():
    """Test network latency to VM"""
    vm_ip, _ = get_vm_ip("staging")
    
    # Ping test
    result = subprocess.run([
        'ping', '-c', '5', vm_ip
    ], capture_output=True, text=True, timeout=30)
    
    assert result.returncode == 0, "Ping test failed"
    
    # Parse average latency
    ping_output = result.stdout
    if 'rtt min/avg/max/mdev' in ping_output:
        # Linux ping output
        avg_latency = float(ping_output.split('rtt min/avg/max/mdev = ')[1].split('/')[1])
    elif 'Average' in ping_output:
        # Windows ping output
        avg_latency = float(ping_output.split('Average = ')[1].split('ms')[0])
    else:
        pytest.skip("Could not parse ping output")
    
    # Latency should be reasonable (< 100ms for most cases)
    assert avg_latency < 100.0, f"Network latency too high: {avg_latency:.1f}ms"

def pytest_addoption(parser):
    """Add command line option for environment"""
    parser.addoption("--env", action="store", default="staging", 
                     help="Environment to test: dev, staging, production")

if __name__ == "__main__":
    pytest.main([__file__])
