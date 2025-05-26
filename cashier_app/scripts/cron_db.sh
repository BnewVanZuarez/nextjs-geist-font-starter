#!/bin/bash

# Database cron job management script
# Usage: ./cron_db.sh [environment] [operation]
# Example: ./cron_db.sh development install

# Set environment
ENV=${1:-development}
echo "Managing database cron jobs for $ENV environment"

# Load environment variables
if [ -f "../.env.$ENV" ]; then
    source "../.env.$ENV"
else
    echo "Error: Environment file .env.$ENV not found"
    exit 1
fi

# Create cron logs directory
CRON_DIR="../logs/cron"
mkdir -p "$CRON_DIR"

# Function to log cron operations
log_cron() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$CRON_DIR/cron.log"
}

# Get absolute path to scripts directory
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to install cron jobs
install_crons() {
    echo "Installing database cron jobs..."
    
    # Create temporary crontab file
    TEMP_CRON=$(mktemp)
    
    # Export current crontab
    crontab -l > "$TEMP_CRON" 2>/dev/null
    
    # Add environment variables
    cat >> "$TEMP_CRON" << EOF
# Environment variables for database cron jobs
SUPABASE_DB_URL="$SUPABASE_DB_URL"
ENV="$ENV"
PATH=/usr/local/bin:/usr/bin:/bin:$PATH
SHELL=/bin/bash

# Database maintenance cron jobs
EOF
    
    # Add maintenance jobs
    cat >> "$TEMP_CRON" << EOF
# Daily backup at 1 AM
0 1 * * * $SCRIPTS_DIR/backup_db.sh $ENV backup >> $CRON_DIR/backup.log 2>&1

# Weekly full maintenance at 2 AM on Sunday
0 2 * * 0 $SCRIPTS_DIR/maintain_db.sh $ENV all >> $CRON_DIR/maintain.log 2>&1

# Daily cleanup at 3 AM
0 3 * * * $SCRIPTS_DIR/cleanup_db.sh $ENV all >> $CRON_DIR/cleanup.log 2>&1

# Hourly monitoring
0 * * * * $SCRIPTS_DIR/monitor_db.sh $ENV all >> $CRON_DIR/monitor.log 2>&1

# Daily optimization at 4 AM
0 4 * * * $SCRIPTS_DIR/optimize_db.sh $ENV all >> $CRON_DIR/optimize.log 2>&1

# Daily security audit at 5 AM
0 5 * * * $SCRIPTS_DIR/secure_db.sh $ENV audit >> $CRON_DIR/security.log 2>&1

# Weekly analytics report at 6 AM on Monday
0 6 * * 1 $SCRIPTS_DIR/analyze_db.sh $ENV report >> $CRON_DIR/analytics.log 2>&1

# Check replication status every 5 minutes
*/5 * * * * $SCRIPTS_DIR/replicate_db.sh $ENV status >> $CRON_DIR/replication.log 2>&1

# Rotate logs weekly at 7 AM on Sunday
0 7 * * 0 find $CRON_DIR -name "*.log" -mtime +7 -exec gzip {} \;
EOF
    
    # Install new crontab
    if crontab "$TEMP_CRON"; then
        log_cron "install" "success" "Cron jobs installed"
        echo "Cron jobs installed successfully"
    else
        log_cron "install" "error" "Failed to install cron jobs"
        echo "Error: Failed to install cron jobs"
        rm "$TEMP_CRON"
        return 1
    fi
    
    # Clean up
    rm "$TEMP_CRON"
}

# Function to remove cron jobs
remove_crons() {
    echo "Removing database cron jobs..."
    
    # Create temporary crontab file
    TEMP_CRON=$(mktemp)
    
    # Export current crontab and remove our jobs
    crontab -l | grep -v "$SCRIPTS_DIR" > "$TEMP_CRON" 2>/dev/null
    
    # Install new crontab
    if crontab "$TEMP_CRON"; then
        log_cron "remove" "success" "Cron jobs removed"
        echo "Cron jobs removed successfully"
    else
        log_cron "remove" "error" "Failed to remove cron jobs"
        echo "Error: Failed to remove cron jobs"
        rm "$TEMP_CRON"
        return 1
    fi
    
    # Clean up
    rm "$TEMP_CRON"
}

# Function to list cron jobs
list_crons() {
    echo "Listing database cron jobs..."
    crontab -l | grep "$SCRIPTS_DIR"
}

# Function to check cron job status
check_status() {
    echo "Checking cron job status..."
    
    # Check if cron daemon is running
    if pgrep cron > /dev/null; then
        echo "Cron daemon: Running"
    else
        echo "Cron daemon: Not running"
    fi
    
    # Check recent cron job executions
    echo -e "\nRecent job executions:"
    for log in "$CRON_DIR"/*.log; do
        if [ -f "$log" ]; then
            echo -e "\n$(basename "$log"):"
            tail -n 5 "$log"
        fi
    done
}

# Function to test cron jobs
test_crons() {
    echo "Testing cron jobs..."
    
    # Test each script with minimal operation
    scripts=(
        "backup_db.sh status"
        "maintain_db.sh status"
        "cleanup_db.sh status"
        "monitor_db.sh status"
        "optimize_db.sh status"
        "secure_db.sh audit"
        "analyze_db.sh status"
        "replicate_db.sh status"
    )
    
    for script in "${scripts[@]}"; do
        echo -e "\nTesting $script..."
        if $SCRIPTS_DIR/$script $ENV > /dev/null 2>&1; then
            echo "✓ Success"
        else
            echo "✗ Failed"
        fi
    done
}

# Function to rotate log files
rotate_logs() {
    echo "Rotating cron job logs..."
    
    find "$CRON_DIR" -name "*.log" -type f | while read -r log; do
        if [ -s "$log" ]; then
            mv "$log" "$log.$(date '+%Y%m%d')"
            gzip "$log.$(date '+%Y%m%d')"
            touch "$log"
        fi
    done
    
    # Clean up old logs (older than 30 days)
    find "$CRON_DIR" -name "*.gz" -type f -mtime +30 -delete
    
    log_cron "rotate" "success" "Log files rotated"
    echo "Log rotation completed"
}

# Process commands
case "${2:-status}" in
    "install")
        install_crons
        ;;
        
    "remove")
        remove_crons
        ;;
        
    "list")
        list_crons
        ;;
        
    "status")
        check_status
        ;;
        
    "test")
        test_crons
        ;;
        
    "rotate")
        rotate_logs
        ;;
        
    *)
        echo "Usage: $0 [environment] [install|remove|list|status|test|rotate]"
        exit 1
        ;;
esac

exit 0
