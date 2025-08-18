#!/bin/bash
set -euo pipefail

# Update VICIdial server IP configuration
# Detects current IP and updates VICIdial database accordingly

echo "=== Updating VICIdial Server IP ==="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root (use sudo)"
   exit 1
fi

# Detect current server IP
SERVER_IP=$(ip route get 8.8.8.8 | awk '{print $7; exit}' 2>/dev/null || echo "")

if [[ -z "$SERVER_IP" ]]; then
    echo "ERROR: Could not detect server IP address"
    exit 1
fi

echo "Detected server IP: $SERVER_IP"

# Check if VICIdial database exists
if ! mysql -e "USE asterisk" 2>/dev/null; then
    echo "ERROR: VICIdial database 'asterisk' not found"
    exit 1
fi

# Get current server IP from database
CURRENT_DB_IP=$(mysql -s -N -e "SELECT server_ip FROM asterisk.servers WHERE server_id='1'" 2>/dev/null || echo "")

if [[ "$CURRENT_DB_IP" == "$SERVER_IP" ]]; then
    echo "✓ Server IP already up to date in database: $SERVER_IP"
else
    echo "Updating server IP in database from '$CURRENT_DB_IP' to '$SERVER_IP'"
    
    # Update servers table
    mysql asterisk -e "UPDATE servers SET server_ip='$SERVER_IP' WHERE server_id='1';"
    
    # Update phones table
    mysql asterisk -e "UPDATE phones SET server_ip='$SERVER_IP';"
    
    # Update conferences table
    mysql asterisk -e "UPDATE conferences SET server_ip='$SERVER_IP';"
    
    # Update other relevant tables
    mysql asterisk -e "UPDATE vicidial_conferences SET server_ip='$SERVER_IP';"
    
    echo "✓ Database updated with new server IP: $SERVER_IP"
fi

# Restart Asterisk to pick up any configuration changes
if systemctl is-active --quiet asterisk; then
    echo "Restarting Asterisk to apply changes..."
    systemctl restart asterisk
    sleep 3
    
    if systemctl is-active --quiet asterisk; then
        echo "✓ Asterisk restarted successfully"
    else
        echo "ERROR: Asterisk failed to restart"
        exit 1
    fi
fi

# Update the first run file with new IP
if [[ -f "/root/vici_first_run.txt" ]]; then
    sed -i "s|http://[0-9.]*|http://$SERVER_IP|g" /root/vici_first_run.txt
    sed -i "s/Server: [0-9.]*/Server: $SERVER_IP/" /root/vici_first_run.txt
fi

echo ""
echo "=== Server IP Update Complete ==="
echo "New server IP: $SERVER_IP"
echo ""
echo "Updated URLs:"
echo "  Admin: http://$SERVER_IP/vicidial/admin.php"
echo "  Agent: http://$SERVER_IP/agc/vicidial.php"
echo ""
echo "SIP Phone Configuration:"
echo "  Server: $SERVER_IP"
echo "  Extension: 1001"
echo "  Password: 1001"
echo ""

exit 0
