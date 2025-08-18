#!/bin/bash
set -euo pipefail

# VICIdial Self-Test Script
# Comprehensive testing of VICIdial installation and ops stack

echo "=== VICIdial Self-Test ==="

FAILED_TESTS=()
PASSED_TESTS=()

# Function to run a test and track results
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo "Testing: $test_name"
    
    if eval "$test_command" &>/dev/null; then
        echo "✓ $test_name"
        PASSED_TESTS+=("$test_name")
    else
        echo "✗ $test_name"
        FAILED_TESTS+=("$test_name")
    fi
}

# Test 1: Service Status
echo "=== Service Status Tests ==="

run_test "Apache2 service running" "systemctl is-active --quiet apache2"
run_test "MariaDB service running" "systemctl is-active --quiet mariadb"
run_test "Asterisk service running" "systemctl is-active --quiet asterisk"

# Test 2: Asterisk Tests
echo ""
echo "=== Asterisk Tests ==="

run_test "Asterisk version contains 18" "asterisk -V 2>/dev/null | grep -q 'Asterisk 18'"
run_test "PJSIP module loaded" "asterisk -rx 'module show like pjsip' | grep -q 'res_pjsip.so'"
run_test "ConfBridge module loaded" "asterisk -rx 'module show like confbridge' | grep -q 'app_confbridge.so'"
run_test "PJSIP endpoints accessible" "asterisk -rx 'pjsip show endpoints' >/dev/null 2>&1"

# Test 3: Web Interface Tests
echo ""
echo "=== Web Interface Tests ==="

run_test "VICIdial admin page accessible" "curl -s --connect-timeout 10 'http://localhost/vicidial/admin.php' | grep -q 'ViciDial'"
run_test "VICIdial agent page accessible" "curl -s --connect-timeout 10 'http://localhost/agc/vicidial.php' | grep -q -i 'vicidial'"

# Test 4: Database Tests
echo ""
echo "=== Database Tests ==="

run_test "MariaDB connection works" "mysql -e 'SELECT 1' >/dev/null 2>&1"
run_test "VICIdial database exists" "mysql -e 'USE asterisk' >/dev/null 2>&1"
run_test "VICIdial users table has data" "test \$(mysql -s -N -e 'SELECT COUNT(*) FROM asterisk.vicidial_users' 2>/dev/null || echo 0) -gt 0"
run_test "VICIdial phones table has data" "test \$(mysql -s -N -e 'SELECT COUNT(*) FROM asterisk.phones' 2>/dev/null || echo 0) -gt 0"

# Test 5: File System Tests
echo ""
echo "=== File System Tests ==="

run_test "VICIdial web directory exists" "test -d /var/www/html/vicidial"
run_test "VICIdial AGC directory exists" "test -d /var/www/html/agc"
run_test "Asterisk sounds directory exists" "test -d /var/lib/asterisk/sounds"
run_test "Asterisk spool directory exists" "test -d /var/spool/asterisk"
run_test "VICIdial source directory exists" "test -d /usr/src/astguiclient/trunk"

# Test 6: Configuration Tests
echo ""
echo "=== Configuration Tests ==="

run_test "Asterisk PJSIP config exists" "test -f /etc/asterisk/pjsip.d/pjsip-vici-sample.conf"
run_test "Asterisk extensions config exists" "test -f /etc/asterisk/extensions.d/extensions-vici-sample.conf"
run_test "Apache VICIdial site enabled" "apache2ctl -S 2>/dev/null | grep -q vicidial"

# Test 7: Cron Jobs Tests
echo ""
echo "=== Cron Jobs Tests ==="

run_test "VICIdial cron jobs installed" "crontab -l | grep -q astguiclient"

# Test 8: Network Tests
echo ""
echo "=== Network Tests ==="

run_test "Port 80 (Apache) listening" "netstat -tuln 2>/dev/null | grep -q ':80 ' || ss -tuln 2>/dev/null | grep -q ':80 '"
run_test "Port 5060 (Asterisk SIP) listening" "netstat -tuln 2>/dev/null | grep -q ':5060 ' || ss -tuln 2>/dev/null | grep -q ':5060 '"

# Test 9: Sample Data Tests
echo ""
echo "=== Sample Data Tests ==="

# Check if admin user exists
ADMIN_COUNT=$(mysql -s -N -e "SELECT COUNT(*) FROM asterisk.vicidial_users WHERE user='6666'" 2>/dev/null || echo "0")
run_test "Admin user 6666 exists" "test $ADMIN_COUNT -gt 0"

# Check if sample phone exists
PHONE_COUNT=$(mysql -s -N -e "SELECT COUNT(*) FROM asterisk.phones WHERE extension='1001'" 2>/dev/null || echo "0")
run_test "Sample phone 1001 exists" "test $PHONE_COUNT -gt 0"

# Summary
echo ""
echo "=== Test Summary ==="
echo "Passed: ${#PASSED_TESTS[@]}"
echo "Failed: ${#FAILED_TESTS[@]}"

if [[ ${#FAILED_TESTS[@]} -eq 0 ]]; then
    echo ""
    echo "🎉 All tests passed! VICIdial is working correctly."
    echo ""
    echo "=== Access Information ==="
    SERVER_IP=$(ip route get 8.8.8.8 | awk '{print $7; exit}' 2>/dev/null || echo "localhost")
    echo "Admin Interface: http://$SERVER_IP/vicidial/admin.php"
    echo "Agent Interface: http://$SERVER_IP/agc/vicidial.php"
    echo "Username: 6666 | Password: refacekit"
    echo ""
    echo "SIP Phone Configuration:"
    echo "Extension: 1001 | Password: 1001 | Server: $SERVER_IP"
    echo ""
    exit 0
else
    echo ""
    echo "❌ Some tests failed:"
    for test in "${FAILED_TESTS[@]}"; do
        echo "  - $test"
    done
    echo ""
    echo "Please check the installation and try again."
    echo "Run individual components manually to debug issues."
    echo ""
    exit 1
fi
