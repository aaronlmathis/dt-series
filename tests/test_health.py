"""
Production health checks and security verification. 
These tests ensure the production environment is secure, stable, and compliant with best practices.
"""
import os
import subprocess
import pytest


# ── Helpers ────────────────────────────────────────────────────────────────────
def get_vm_ip() -> str:
    """Return the VM IP from the workflow’s environment; skip tests if absent."""
    vm_ip = os.environ.get("VM_IP")
    if not vm_ip:
        pytest.skip("VM_IP environment variable not set")
    return vm_ip


def ssh_command(host: str, command: str) -> subprocess.CompletedProcess:
    """Run a command on the remote host via SSH and return the CompletedProcess."""
    try:
        return subprocess.run(
            [
                "ssh",
                "-o", "ConnectTimeout=10",
                "-o", "StrictHostKeyChecking=no",
                f"azureuser@{host}",
                command,
            ],
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"SSH command failed: {exc}")  # surfaces stderr in pytest output


# ── Tests ──────────────────────────────────────────────────────────────────────
def test_vm_health_status():
    """Basic VM health (uptime / mem / root disk)."""
    vm_ip = get_vm_ip()
    result = ssh_command(vm_ip, "uptime && free -m && df -h /")
    assert "load average" in result.stdout, "uptime output missing"
    assert "Mem:" in result.stdout, "memory info missing"
    assert "/" in result.stdout, "disk info missing"
    print("[PASS] VM health checks passed")


def test_critical_services_status():
    """Ensure critical services are active (Ubuntu defaults + hardening)."""
    vm_ip = get_vm_ip()
    critical_services = ["ssh", "fail2ban", "ufw", "chronyd", "rsyslog"]
    for svc in critical_services:
        result = ssh_command(vm_ip, f"systemctl is-active {svc}")
        assert "active" in result.stdout, f"service {svc} is not running"
        print(f"[PASS] {svc} is active")


def test_network_connectivity():
    """Verify outbound connectivity and DNS resolution."""
    vm_ip = get_vm_ip()
    # External reachability
    result = ssh_command(vm_ip, "ping -c 2 8.8.8.8")
    assert result.returncode == 0, "ICMP to 8.8.8.8 failed"
    # DNS resolution
    result = ssh_command(vm_ip, "nslookup google.com")
    assert result.returncode == 0, "DNS resolution failed"
    print("[PASS] network connectivity + DNS OK")


def test_security_baseline():
    """Quick security sanity checks for running processes and open ports."""
    vm_ip = get_vm_ip()

    # No stray netcat variants
    result = ssh_command(vm_ip, "pgrep -fa '(nc|netcat|ncat)' || true")
    assert result.stdout.strip() == "", "netcat/nc processes detected"

    # No unexpected listening sockets (non‑localhost)
    result = ssh_command(vm_ip, "ss -tuln | grep -vE '(^State|127\\.0\\.0\\.1|::1)'")
    assert result.stdout.strip() == "", "unexpected listening sockets found"
    print("[PASS] baseline security checks passed")


def test_log_analysis():
    """Ensure logs exist and no recent critical errors."""
    vm_ip = get_vm_ip()

    # Recent failed SSH logins < 5
    result = ssh_command(vm_ip, "grep -c 'Failed password' /var/log/auth.log || true")
    failed = int(result.stdout.strip() or 0)
    assert failed < 5, f"{failed} recent failed SSH logins"

    # System logs present
    result = ssh_command(vm_ip, "test -f /var/log/syslog -o -f /var/log/messages")
    assert result.returncode == 0, "system logs missing"

    # No priority=err logs in last hour
    result = ssh_command(vm_ip, "journalctl --since '-1h' --priority err || true")
    assert result.stdout.strip() == "", "critical errors in journal"
    print("[PASS] log analysis clean")
