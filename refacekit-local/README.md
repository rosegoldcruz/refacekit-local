# RefaceKit Local VICIdial

Complete, idempotent VICIdial installation for Ubuntu 22.04 with integrated ops stack for CSV processing and lead management.

## Quick Start

```bash
# Install VICIdial (requires sudo)
sudo make install

# Run post-installation verification
sudo make postinstall

# Test the installation
sudo make selftest

# Start ops stack for CSV processing
make ops-up

# Test ops stack
make ops-test
```

## What You Get

### VICIdial Stack
- **Asterisk 18** with PJSIP, ConfBridge, and MP3 support
- **Apache** web server with optimized VICIdial configuration
- **MariaDB** database with VICIdial schema
- **VICIdial** admin and agent interfaces
- **Sample data**: Admin user (6666/refacekit) and phone (1001/1001)
- **Cron jobs** for VICIdial maintenance

### Ops Stack
- **FastAPI** service for CSV ingestion and processing
- **Redis** job queue for background processing
- **Worker** service for CSV→VICIdial format conversion
- **Nginx** reverse proxy
- **Docker Compose** orchestration

## Access Information

After successful installation:

### VICIdial Interfaces
- **Admin Interface**: `http://<server-ip>/vicidial/admin.php`
- **Agent Interface**: `http://<server-ip>/agc/vicidial.php`
- **Username**: `6666`
- **Password**: `refacekit`

### SIP Phone Configuration
- **Extension**: `1001`
- **Password**: `1001`
- **Server**: `<server-ip>`
- **Protocol**: PJSIP (port 5060)

## Prerequisites

- **OS**: Ubuntu 22.04 LTS (x86_64)
- **RAM**: Minimum 2GB, recommended 4GB+
- **Disk**: Minimum 20GB free space
- **Network**: Internet connection for package downloads
- **Privileges**: Root access (sudo)
- **Docker**: Required for ops stack (optional for VICIdial)

## Installation Commands

### Core Installation
```bash
sudo make install          # Install VICIdial stack
sudo make postinstall      # Verify installation
sudo make update-ip        # Update server IP settings
sudo make quickstart       # install + postinstall + selftest
```

### Testing
```bash
sudo make selftest         # Test VICIdial installation
make ops-test             # Test ops stack (requires ops-up)
```

### Ops Stack Management
```bash
make ops-up               # Start ops stack
make ops-down             # Stop ops stack
make ops-restart          # Restart ops stack
make ops-logs             # View ops stack logs
```

### Maintenance
```bash
make status               # Show service status
make logs                 # Show recent logs
make clean                # Clean temporary files
make backup               # Create backup
```

## Security Notes

### Default Credentials
**Change these immediately in production:**
- VICIdial admin: `6666/refacekit`
- SIP phone: `1001/1001`

### Network Security
- Database bound to localhost only
- Apache configured with security headers
- SIP traffic on standard ports (5060/5061)
- Ops stack isolated in Docker network

## Support

### Log Locations
- **Asterisk**: `/var/log/asterisk/full`
- **Apache**: `/var/log/apache2/error.log`
- **MariaDB**: `/var/log/mysql/error.log`
- **VICIdial**: `/var/log/astguiclient/`

### Useful Commands
```bash
# VICIdial status
sudo make status

# View all logs
sudo make logs

# Test everything
sudo make selftest

# Clean and restart
make clean && sudo systemctl restart asterisk apache2 mariadb
```

## License

This project is provided as-is for educational and development purposes. VICIdial is licensed under the Affero GPL. Please ensure compliance with all applicable licenses in production use.
