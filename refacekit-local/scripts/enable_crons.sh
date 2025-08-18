#!/bin/bash
set -euo pipefail

# Enable VICIdial cron jobs
# Installs necessary cron jobs for VICIdial maintenance

echo "=== Enabling VICIdial Cron Jobs ==="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root (use sudo)"
   exit 1
fi

# Check if VICIdial is installed
if [[ ! -d "/usr/src/astguiclient/trunk" ]]; then
    echo "ERROR: VICIdial not found. Run installation first."
    exit 1
fi

# VICIdial cron jobs to install
CRON_JOBS=(
    "* * * * * /usr/share/astguiclient/AST_update.pl --debug"
    "* * * * * /usr/share/astguiclient/AST_VDauto_dial.pl --debug"
    "1 1 * * * /usr/share/astguiclient/AST_DB_optimize.pl --debug"
    "2 1 * * * /usr/share/astguiclient/AST_cleanup_agent_log.pl --debug"
    "* * * * * /usr/share/astguiclient/AST_VDremote_agents.pl --debug"
    "* * * * * /usr/share/astguiclient/AST_flush_DBqueue.pl --debug"
    "10 1 * * * /usr/share/astguiclient/AST_CRON_audio_1_move_mix.pl --debug"
    "20 1 * * * /usr/share/astguiclient/AST_CRON_audio_2_compress.pl --debug"
    "30 1 * * * /usr/share/astguiclient/AST_CRON_audio_3_ftp.pl --debug"
)

# Get current crontab
CURRENT_CRON=$(crontab -l 2>/dev/null || echo "")

# Check which jobs need to be added
JOBS_TO_ADD=()
for job in "${CRON_JOBS[@]}"; do
    # Extract the script name from the job
    SCRIPT_NAME=$(echo "$job" | grep -o '/usr/share/astguiclient/[^[:space:]]*' | head -1)
    
    if ! echo "$CURRENT_CRON" | grep -q "$SCRIPT_NAME"; then
        JOBS_TO_ADD+=("$job")
    fi
done

if [[ ${#JOBS_TO_ADD[@]} -eq 0 ]]; then
    echo "✓ All VICIdial cron jobs already installed"
else
    echo "Installing ${#JOBS_TO_ADD[@]} new cron jobs..."
    
    # Create temporary cron file
    TEMP_CRON=$(mktemp)
    
    # Add existing cron jobs
    if [[ -n "$CURRENT_CRON" ]]; then
        echo "$CURRENT_CRON" > "$TEMP_CRON"
    fi
    
    # Add new jobs
    for job in "${JOBS_TO_ADD[@]}"; do
        echo "$job" >> "$TEMP_CRON"
        echo "  Added: $job"
    done
    
    # Install new crontab
    crontab "$TEMP_CRON"
    rm "$TEMP_CRON"
    
    echo "✓ VICIdial cron jobs installed"
fi

# Ensure cron service is running
if ! systemctl is-active --quiet cron; then
    echo "Starting cron service..."
    systemctl start cron
    systemctl enable cron
fi

echo "✓ Cron service is running"

# Create log directory for VICIdial scripts
mkdir -p /var/log/astguiclient
chown www-data:www-data /var/log/astguiclient

# Verify cron jobs are installed
echo ""
echo "=== Installed VICIdial Cron Jobs ==="
crontab -l | grep astguiclient || echo "No VICIdial cron jobs found"

echo ""
echo "VICIdial cron jobs enabled successfully!"

exit 0
