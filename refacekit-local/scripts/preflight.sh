#!/bin/bash
set -euo pipefail

# Preflight checks for VICIdial installation on Ubuntu 22.04
# Verifies system requirements and prerequisites

echo "=== VICIdial Preflight Checks ==="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root (use sudo)"
   exit 1
fi

# Check Ubuntu version
if ! grep -q "Ubuntu 22.04" /etc/os-release; then
    echo "ERROR: This script requires Ubuntu 22.04"
    echo "Current OS:"
    cat /etc/os-release | grep PRETTY_NAME
    exit 1
fi

echo "✓ Ubuntu 22.04 detected"

# Check architecture
ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" ]]; then
    echo "ERROR: This script requires x86_64 architecture, found: $ARCH"
    exit 1
fi

echo "✓ x86_64 architecture confirmed"

# Check RAM (minimum 2GB)
RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
RAM_GB=$((RAM_KB / 1024 / 1024))

if [[ $RAM_GB -lt 2 ]]; then
    echo "ERROR: Minimum 2GB RAM required, found: ${RAM_GB}GB"
    exit 1
fi

echo "✓ RAM check passed: ${RAM_GB}GB available"

# Check disk space (minimum 20GB free)
DISK_FREE_GB=$(df / | tail -1 | awk '{print int($4/1024/1024)}')

if [[ $DISK_FREE_GB -lt 20 ]]; then
    echo "ERROR: Minimum 20GB free disk space required, found: ${DISK_FREE_GB}GB"
    exit 1
fi

echo "✓ Disk space check passed: ${DISK_FREE_GB}GB free"

# Check critical ports are available
PORTS_TO_CHECK=(80 5060 5061 8088 8089)
PORTS_IN_USE=()

for port in "${PORTS_TO_CHECK[@]}"; do
    if netstat -tuln 2>/dev/null | grep -q ":${port} " || ss -tuln 2>/dev/null | grep -q ":${port} "; then
        PORTS_IN_USE+=($port)
    fi
done

if [[ ${#PORTS_IN_USE[@]} -gt 0 ]]; then
    echo "ERROR: The following required ports are already in use:"
    printf '%s\n' "${PORTS_IN_USE[@]}"
    echo "Please stop services using these ports before continuing"
    exit 1
fi

echo "✓ Required ports (80, 5060, 5061, 8088, 8089) are available"

# Update package list
echo "Updating package list..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

# Install base packages if missing
BASE_PACKAGES=(
    curl
    ca-certificates
    ntp
    git
    subversion
    build-essential
    wget
    gnupg
    lsb-release
    software-properties-common
)

MISSING_PACKAGES=()
for pkg in "${BASE_PACKAGES[@]}"; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        MISSING_PACKAGES+=($pkg)
    fi
done

if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
    echo "Installing missing base packages: ${MISSING_PACKAGES[*]}"
    apt-get install -y "${MISSING_PACKAGES[@]}"
fi

echo "✓ Base packages installed"

# Check network connectivity
if ! curl -s --connect-timeout 10 https://www.google.com > /dev/null; then
    echo "ERROR: No internet connectivity detected"
    exit 1
fi

echo "✓ Internet connectivity confirmed"

# Check if VICIdial is already installed
if [[ -d "/usr/src/astguiclient" ]] && [[ -d "/var/www/html/vicidial" ]]; then
    echo "⚠ WARNING: VICIdial appears to already be installed"
    echo "  - /usr/src/astguiclient exists"
    echo "  - /var/www/html/vicidial exists"
    echo "  Installation script will attempt to update/reconfigure"
fi

# Check if Asterisk is already running
if systemctl is-active --quiet asterisk 2>/dev/null; then
    echo "⚠ WARNING: Asterisk service is already running"
    echo "  Installation will stop and reconfigure it"
fi

echo ""
echo "=== Preflight Summary ==="
echo "✓ Ubuntu 22.04 x86_64"
echo "✓ ${RAM_GB}GB RAM (≥2GB required)"
echo "✓ ${DISK_FREE_GB}GB free disk space (≥20GB required)"
echo "✓ Required ports available"
echo "✓ Base packages ready"
echo "✓ Internet connectivity"
echo ""
echo "System is ready for VICIdial installation!"
echo "Run: sudo bash install/vici_install_ubuntu22.sh"
echo ""

exit 0
