#!/bin/bash
set -euo pipefail

# VICIdial Post-Installation Verification and Setup
# Performs sanity checks and final configuration

echo "=== VICIdial Post-Installation Verification ==="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root (use sudo)"
   exit 1
fi

# Verify Asterisk installation and version
echo "Checking Asterisk installation..."

if ! command -v asterisk &> /dev/null; then
    echo "ERROR: Asterisk not found in PATH"
    exit 1
fi

ASTERISK_VERSION=$(asterisk -V 2>/dev/null | head -1)
if ! echo "$ASTERISK_VERSION" | grep -q "Asterisk 18"; then
    echo "ERROR: Expected Asterisk 18, found: $ASTERISK_VERSION"
    exit 1
fi

echo "✓ Asterisk version: $ASTERISK_VERSION"

# Check if Asterisk is running
if ! systemctl is-active --quiet asterisk; then
    echo "Starting Asterisk..."
    systemctl start asterisk
    sleep 3
fi

# Verify PJSIP module is loaded
echo "Checking PJSIP module..."
if ! asterisk -rx "module show like pjsip" | grep -q "res_pjsip.so"; then
    echo "ERROR: PJSIP module not loaded"
    exit 1
fi

echo "✓ PJSIP module loaded"

# Verify ConfBridge module is loaded
echo "Checking ConfBridge module..."
if ! asterisk -rx "module show like confbridge" | grep -q "app_confbridge.so"; then
    echo "ERROR: ConfBridge module not loaded"
    exit 1
fi

echo "✓ ConfBridge module loaded"

# Verify format_mp3 module is loaded
echo "Checking MP3 format module..."
if ! asterisk -rx "module show like format_mp3" | grep -q "format_mp3.so"; then
    echo "WARNING: MP3 format module not loaded (optional)"
else
    echo "✓ MP3 format module loaded"
fi

# Test PJSIP endpoints
echo "Checking PJSIP endpoints..."
if ! asterisk -rx "pjsip show endpoints" &> /dev/null; then
    echo "ERROR: Cannot query PJSIP endpoints"
    exit 1
fi

echo "✓ PJSIP endpoints accessible"

# Verify Apache is running and serving VICIdial
echo "Checking Apache and VICIdial web interface..."

if ! systemctl is-active --quiet apache2; then
    echo "Starting Apache..."
    systemctl start apache2
    sleep 2
fi

# Test VICIdial admin page
SERVER_IP=$(ip route get 8.8.8.8 | awk '{print $7; exit}')
ADMIN_URL="http://localhost/vicidial/admin.php"

if ! curl -s --connect-timeout 10 "$ADMIN_URL" | grep -q "ViciDial"; then
    echo "ERROR: VICIdial admin interface not accessible"
    echo "Tried URL: $ADMIN_URL"
    exit 1
fi

echo "✓ VICIdial admin interface accessible"

# Verify MariaDB is running and database exists
echo "Checking MariaDB and VICIdial database..."

if ! systemctl is-active --quiet mariadb; then
    echo "Starting MariaDB..."
    systemctl start mariadb
    sleep 2
fi

# Check if vicidial_users table exists and has data
USER_COUNT=$(mysql -s -N -e "SELECT COUNT(*) FROM asterisk.vicidial_users" 2>/dev/null || echo "0")

if [[ "$USER_COUNT" -eq 0 ]]; then
    echo "ERROR: No users found in vicidial_users table"
    exit 1
fi

echo "✓ VICIdial database contains $USER_COUNT users"

# Create necessary directories and set permissions
echo "Setting up directories and permissions..."

# Create audio directories
mkdir -p /var/lib/asterisk/sounds/vicidial
mkdir -p /var/lib/asterisk/sounds/custom
mkdir -p /var/spool/asterisk/monitor
mkdir -p /var/spool/asterisk/outgoing

# Set proper ownership
chown -R asterisk:asterisk /var/lib/asterisk/
chown -R asterisk:asterisk /var/spool/asterisk/
chown -R asterisk:asterisk /var/log/asterisk/

# Create test audio file
if [[ ! -f "/var/lib/asterisk/sounds/vicidial/test.wav" ]]; then
    # Create a simple test tone
    sox -n -r 8000 -c 1 /var/lib/asterisk/sounds/vicidial/test.wav synth 3 sine 440 2>/dev/null || echo "Warning: Could not create test audio file (sox not available)"
    if [[ -f "/var/lib/asterisk/sounds/vicidial/test.wav" ]]; then
        chown asterisk:asterisk /var/lib/asterisk/sounds/vicidial/test.wav
    fi
fi

echo "✓ Directories and permissions configured"

# Verify cron jobs are installed
echo "Checking VICIdial cron jobs..."

if ! crontab -l | grep -q "AST_update.pl"; then
    echo "WARNING: VICIdial cron jobs may not be properly installed"
    echo "Run: bash scripts/enable_crons.sh"
else
    echo "✓ VICIdial cron jobs installed"
fi

# Final service status check
echo "Checking service status..."

SERVICES=(asterisk apache2 mariadb)
for service in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$service"; then
        echo "✓ $service is running"
    else
        echo "ERROR: $service is not running"
        exit 1
    fi
done

# Display final summary
echo ""
echo "=== Post-Installation Summary ==="
echo "✓ Asterisk 18 with PJSIP and ConfBridge running"
echo "✓ VICIdial web interface accessible"
echo "✓ Database configured with users"
echo "✓ All services running"
echo "✓ Directories and permissions set"
echo ""
echo "=== Access Information ==="
echo "Admin Interface: http://${SERVER_IP}/vicidial/admin.php"
echo "Agent Interface: http://${SERVER_IP}/agc/vicidial.php"
echo ""
echo "Default Credentials:"
echo "  Username: 6666"
echo "  Password: refacekit"
echo ""
echo "Sample Phone:"
echo "  Extension: 1001"
echo "  Password: 1001"
echo "  Server: ${SERVER_IP}"
echo ""
echo "=== Next Steps ==="
echo "1. Configure your SIP phone with extension 1001"
echo "2. Login to admin interface to set up campaigns"
echo "3. Run selftest: sudo bash scripts/selftest.sh"
echo "4. Start ops stack: make ops-up"
echo ""
echo "VICIdial is ready for use!"

exit 0
