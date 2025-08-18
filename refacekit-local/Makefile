# RefaceKit Local VICIdial Build System
# Provides convenient targets for installation, testing, and management

.PHONY: help install postinstall update-ip selftest ops-up ops-down ops-test clean

# Default target
help:
	@echo "RefaceKit Local VICIdial Build System"
	@echo "====================================="
	@echo ""
	@echo "Installation targets:"
	@echo "  install      - Install complete VICIdial stack"
	@echo "  postinstall  - Run post-installation verification"
	@echo "  update-ip    - Update server IP configuration"
	@echo ""
	@echo "Testing targets:"
	@echo "  selftest     - Run comprehensive VICIdial tests"
	@echo "  ops-test     - Test ops stack functionality"
	@echo ""
	@echo "Ops stack targets:"
	@echo "  ops-up       - Start ops stack (Docker required)"
	@echo "  ops-down     - Stop ops stack"
	@echo "  ops-logs     - View ops stack logs"
	@echo "  ops-restart  - Restart ops stack"
	@echo ""
	@echo "Maintenance targets:"
	@echo "  clean        - Clean up temporary files"
	@echo "  status       - Show service status"
	@echo "  logs         - Show VICIdial logs"
	@echo ""
	@echo "Prerequisites:"
	@echo "  - Ubuntu 22.04 x86_64"
	@echo "  - Root privileges (use sudo)"
	@echo "  - Internet connection"
	@echo "  - Docker & Docker Compose (for ops stack)"

# Installation targets
install:
	@echo "Installing VICIdial stack..."
	sudo bash install/vici_install_ubuntu22.sh

postinstall:
	@echo "Running post-installation verification..."
	sudo bash install/postinstall_vici.sh

update-ip:
	@echo "Updating server IP configuration..."
	sudo bash scripts/update_server_ip.sh

# Testing targets
selftest:
	@echo "Running VICIdial self-test..."
	sudo bash scripts/selftest.sh

ops-test:
	@echo "Running ops stack smoke test..."
	python3 tests/ops_smoke.py

# Ops stack targets
ops-up:
	@echo "Starting ops stack..."
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "Error: Docker not found. Please install Docker first."; \
		exit 1; \
	fi
	@if ! command -v docker-compose >/dev/null 2>&1; then \
		echo "Error: Docker Compose not found. Please install Docker Compose first."; \
		exit 1; \
	fi
	@mkdir -p ops/exports
	cd ops && docker-compose up -d
	@echo "Ops stack started. Access at http://localhost"

ops-down:
	@echo "Stopping ops stack..."
	cd ops && docker-compose down

ops-logs:
	@echo "Showing ops stack logs..."
	cd ops && docker-compose logs -f

ops-restart:
	@echo "Restarting ops stack..."
	cd ops && docker-compose restart

# Maintenance targets
clean:
	@echo "Cleaning up temporary files..."
	@find . -name "*.pyc" -delete 2>/dev/null || true
	@find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name "*.log" -delete 2>/dev/null || true
	@rm -f ops/exports/vici_export_*.csv 2>/dev/null || true
	@echo "Cleanup complete"

status:
	@echo "=== Service Status ==="
	@echo "Apache2:"
	@systemctl is-active apache2 && echo "  ✓ Running" || echo "  ✗ Not running"
	@echo "MariaDB:"
	@systemctl is-active mariadb && echo "  ✓ Running" || echo "  ✗ Not running"
	@echo "Asterisk:"
	@systemctl is-active asterisk && echo "  ✓ Running" || echo "  ✗ Not running"
	@echo ""
	@echo "=== Ops Stack Status ==="
	@if command -v docker >/dev/null 2>&1 && command -v docker-compose >/dev/null 2>&1; then \
		cd ops && docker-compose ps; \
	else \
		echo "Docker not available"; \
	fi

logs:
	@echo "=== Recent VICIdial Logs ==="
	@echo "Apache Error Log:"
	@tail -n 10 /var/log/apache2/error.log 2>/dev/null || echo "  No Apache logs found"
	@echo ""
	@echo "Asterisk Full Log:"
	@tail -n 10 /var/log/asterisk/full 2>/dev/null || echo "  No Asterisk logs found"
	@echo ""
	@echo "MariaDB Error Log:"
	@tail -n 10 /var/log/mysql/error.log 2>/dev/null || echo "  No MariaDB logs found"

# Quick start target
quickstart: install postinstall selftest
	@echo ""
	@echo "🎉 QuickStart Complete!"
	@echo ""
	@SERVER_IP=$$(ip route get 8.8.8.8 | awk '{print $$7; exit}' 2>/dev/null || echo "localhost"); \
	echo "Admin Interface: http://$$SERVER_IP/vicidial/admin.php"; \
	echo "Username: 6666 | Password: refacekit"; \
	echo ""; \
	echo "Next steps:"; \
	echo "1. Configure SIP phone with extension 1001, password 1001"; \
	echo "2. Start ops stack: make ops-up"; \
	echo "3. Test ops stack: make ops-test"

# Backup target
backup:
	@echo "Creating VICIdial backup..."
	@BACKUP_DIR="vicidial_backup_$$(date +%Y%m%d_%H%M%S)"; \
	mkdir -p "$$BACKUP_DIR"; \
	mysqldump asterisk > "$$BACKUP_DIR/vicidial_database.sql" 2>/dev/null || echo "Database backup failed"; \
	cp -r /etc/asterisk "$$BACKUP_DIR/" 2>/dev/null || echo "Asterisk config backup failed"; \
	cp -r /var/www/html/vicidial "$$BACKUP_DIR/" 2>/dev/null || echo "Web files backup failed"; \
	tar -czf "$$BACKUP_DIR.tar.gz" "$$BACKUP_DIR" && rm -rf "$$BACKUP_DIR"; \
	echo "Backup created: $$BACKUP_DIR.tar.gz"
