#!/bin/bash
set -euo pipefail

# VICIdial Installation Script for Ubuntu 22.04
# Installs complete VICIdial stack with Asterisk 18 + PJSIP

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== VICIdial Installation for Ubuntu 22.04 ==="
echo "Project root: $PROJECT_ROOT"

# Run preflight checks first
echo "Running preflight checks..."
bash "$PROJECT_ROOT/scripts/preflight.sh"

# Set non-interactive mode
export DEBIAN_FRONTEND=noninteractive

# Install system dependencies
echo "Installing system dependencies..."
apt-get update -qq

SYSTEM_PACKAGES=(
    apache2
    mariadb-server
    php
    php-mysql
    php-cli
    php-gd
    php-curl
    php-mbstring
    php-xml
    php-zip
    sox
    lame
    ffmpeg
    screen
    ntp
    uuid
    uuid-dev
    libedit-dev
    libjansson-dev
    libxml2-dev
    libsqlite3-dev
    libncurses5-dev
    libnewt-dev
    unixodbc-dev
    libssl-dev
    libmp3lame-dev
    libcurl4-openssl-dev
    libspeex-dev
    libspeexdsp-dev
    libgsm1-dev
    libogg-dev
    libvorbis-dev
    libicu-dev
    libical-dev
    libsrtp2-dev
    libspandsp-dev
    libtiff-dev
    autoconf
    automake
    libtool
    pkg-config
    make
    gcc
    g++
    bison
    flex
    patch
)

echo "Installing packages: ${SYSTEM_PACKAGES[*]}"
apt-get install -y "${SYSTEM_PACKAGES[@]}"

# Configure MariaDB
echo "Configuring MariaDB..."
systemctl start mariadb
systemctl enable mariadb

# Copy MySQL configuration
cp "$PROJECT_ROOT/config/mysql/my.cnf" /etc/mysql/conf.d/vicidial.cnf
systemctl restart mariadb

# Secure MariaDB installation (automated)
mysql -e "DELETE FROM mysql.user WHERE User='';"
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -e "DROP DATABASE IF EXISTS test;"
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mysql -e "FLUSH PRIVILEGES;"

# Create asterisk database
mysql -e "CREATE DATABASE IF NOT EXISTS asterisk CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "GRANT ALL PRIVILEGES ON asterisk.* TO 'root'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

echo "✓ MariaDB configured"

# Install Asterisk 18
ASTERISK_VERSION="18.20.0"
ASTERISK_DIR="/usr/src/asterisk-${ASTERISK_VERSION}"

if [[ ! -f "/usr/sbin/asterisk" ]] || ! /usr/sbin/asterisk -V 2>/dev/null | grep -q "Asterisk 18"; then
    echo "Installing Asterisk ${ASTERISK_VERSION}..."
    
    cd /usr/src
    
    # Download and verify Asterisk
    if [[ ! -f "asterisk-${ASTERISK_VERSION}.tar.gz" ]]; then
        wget "https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_VERSION}.tar.gz"
    fi
    
    # Extract if not already done
    if [[ ! -d "$ASTERISK_DIR" ]]; then
        tar -xzf "asterisk-${ASTERISK_VERSION}.tar.gz"
    fi
    
    cd "$ASTERISK_DIR"
    
    # Install MP3 support
    contrib/scripts/get_mp3_source.sh
    
    # Configure Asterisk
    ./configure --with-pjproject-bundled --with-jansson-bundled
    
    # Enable required modules using menuselect
    make menuselect.makeopts
    
    # Enable format_mp3, app_confbridge, res_pjsip, chan_pjsip
    menuselect/menuselect --enable format_mp3 --enable app_confbridge --enable res_pjsip --enable chan_pjsip menuselect.makeopts
    
    # Build and install
    make -j$(nproc)
    make install
    make samples
    make config
    
    echo "✓ Asterisk ${ASTERISK_VERSION} installed"
else
    echo "✓ Asterisk 18 already installed"
fi

# Configure Asterisk
echo "Configuring Asterisk..."

# Copy logger configuration
cp "$PROJECT_ROOT/config/asterisk/logger.conf" /etc/asterisk/

# Create pjsip.d directory and configure includes
mkdir -p /etc/asterisk/pjsip.d
if ! grep -q "pjsip.d" /etc/asterisk/pjsip.conf; then
    echo "#include pjsip.d/*.conf" >> /etc/asterisk/pjsip.conf
fi

# Copy PJSIP configuration
cp "$PROJECT_ROOT/config/asterisk/pjsip-vici-sample.conf" /etc/asterisk/pjsip.d/

# Create extensions.d directory and configure includes
mkdir -p /etc/asterisk/extensions.d
if ! grep -q "extensions.d" /etc/asterisk/extensions.conf; then
    echo "#include extensions.d/*.conf" >> /etc/asterisk/extensions.conf
fi

# Copy extensions configuration
cp "$PROJECT_ROOT/config/asterisk/extensions-vici-sample.conf" /etc/asterisk/extensions.d/

# Set proper permissions
chown -R asterisk:asterisk /etc/asterisk/
chown -R asterisk:asterisk /var/lib/asterisk/
chown -R asterisk:asterisk /var/log/asterisk/
chown -R asterisk:asterisk /var/spool/asterisk/

echo "✓ Asterisk configured"

# Install VICIdial from SVN
echo "Installing VICIdial from SVN..."

if [[ ! -d "/usr/src/astguiclient/trunk" ]]; then
    mkdir -p /usr/src/astguiclient
    cd /usr/src/astguiclient
    svn checkout svn://svn.eflo.net:43690/agc_2-X/trunk
else
    echo "✓ VICIdial source already exists, updating..."
    cd /usr/src/astguiclient/trunk
    svn update
fi

# Install VICIdial database schema
echo "Installing VICIdial database schema..."
cd /usr/src/astguiclient/trunk/extras

# Run database creation scripts in order
mysql asterisk < MySQL_AST_CREATE_tables.sql
mysql asterisk < first_server_install.sql
mysql asterisk < sip-iax_phones.sql

echo "✓ VICIdial database schema installed"

# Install VICIdial web interface
echo "Installing VICIdial web interface..."

# Create web directories
mkdir -p /var/www/html/vicidial
mkdir -p /var/www/html/agc

# Copy web files
cp -r /usr/src/astguiclient/trunk/www/* /var/www/html/vicidial/
cp -r /usr/src/astguiclient/trunk/www/* /var/www/html/agc/

# Set proper permissions
chown -R www-data:www-data /var/www/html/vicidial/
chown -R www-data:www-data /var/www/html/agc/
chmod -R 755 /var/www/html/vicidial/
chmod -R 755 /var/www/html/agc/

echo "✓ VICIdial web interface installed"

# Configure Apache
echo "Configuring Apache..."

# Copy Apache configuration
cp "$PROJECT_ROOT/config/apache/vicidial.conf" /etc/apache2/sites-available/

# Enable site and modules
a2ensite vicidial
a2enmod rewrite
a2enmod ssl

# Restart Apache
systemctl restart apache2
systemctl enable apache2

echo "✓ Apache configured"

# Create admin user and phone
echo "Creating admin user and phone..."
mysql asterisk < "$PROJECT_ROOT/scripts/create_admin_and_phone.sql"

echo "✓ Admin user and phone created"

# Update server IP
echo "Updating server IP configuration..."
bash "$PROJECT_ROOT/scripts/update_server_ip.sh"

# Enable cron jobs
echo "Enabling VICIdial cron jobs..."
bash "$PROJECT_ROOT/scripts/enable_crons.sh"

# Start services
echo "Starting services..."
systemctl start asterisk
systemctl enable asterisk
systemctl start apache2
systemctl enable apache2
systemctl start mariadb
systemctl enable mariadb

# Create installation marker
SERVER_IP=$(ip route get 8.8.8.8 | awk '{print $7; exit}')
cat > /root/vici_first_run.txt << EOF
VICIdial Installation Complete!

Admin Interface: http://${SERVER_IP}/vicidial/admin.php
Agent Interface: http://${SERVER_IP}/agc/vicidial.php

Default Admin Credentials:
Username: 6666
Password: refacekit

Default Phone:
Extension: 1001
Password: 1001
Server: ${SERVER_IP}

Next Steps:
1. Run: sudo bash install/postinstall_vici.sh
2. Configure your SIP phone with extension 1001
3. Access admin interface to configure campaigns

Installation completed at: $(date)
EOF

echo ""
echo "=== VICIdial Installation Complete ==="
echo "✓ Asterisk 18 with PJSIP and ConfBridge"
echo "✓ MariaDB configured"
echo "✓ Apache web server"
echo "✓ VICIdial web interface"
echo "✓ Admin user and sample phone created"
echo "✓ Cron jobs enabled"
echo ""
echo "Admin URL: http://${SERVER_IP}/vicidial/admin.php"
echo "Username: 6666 | Password: refacekit"
echo ""
echo "Run postinstall script: sudo bash install/postinstall_vici.sh"
echo ""

exit 0
