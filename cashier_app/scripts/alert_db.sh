#!/bin/bash

# Database alerting script
# Usage: ./alert_db.sh [environment] [operation]
# Example: ./alert_db.sh development check

# Set environment
ENV=${1:-development}
echo "Managing database alerts for $ENV environment"

# Load environment variables
if [ -f "../.env.$ENV" ]; then
    source "../.env.$ENV"
else
    echo "Error: Environment file .env.$ENV not found"
    exit 1
fi

# Create alerts directory
ALERT_DIR="../logs/alerts"
mkdir -p "$ALERT_DIR"

# Function to log alerts
log_alert() {
    local severity=$1
    local category=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $severity - $category: $message" >> "$ALERT_DIR/alerts.log"
}

# Function to send notification
send_notification() {
    local severity=$1
    local subject=$2
    local message=$3
    
    # Log the alert
    log_alert "$severity" "notification" "$message"
    
    # If webhook URL is configured, send to Slack/Discord
    if [ ! -z "$WEBHOOK_URL" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"[$ENV][$severity] $subject: $message\"}" \
            "$WEBHOOK_URL"
    fi
    
    # If email is configured, send email
    if [ ! -z "$ALERT_EMAIL" ]; then
        echo "$message" | mail -s "[$ENV][$severity] Database Alert: $subject" "$ALERT_EMAIL"
    fi
}

# Function to check database health
check_health() {
    echo "Checking database health..."
    
    # Check connection
    if ! psql "$SUPABASE_DB_URL" -c "SELECT 1;" > /dev/null 2>&1; then
        send_notification "CRITICAL" "Connection Failed" "Unable to connect to database"
        return 1
    fi
    
    # Check disk space
    local db_size=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT pg_size_pretty(pg_database_size(current_database()));
    ")
    
    local disk_usage=$(df -h | grep /dev/sda1 | awk '{print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 90 ]; then
        send_notification "WARNING" "Disk Space" "Database disk usage is at ${disk_usage}%"
    fi
    
    # Check connection count
    local max_connections=$(psql "$SUPABASE_DB_URL" -t -c "SHOW max_connections;")
    local current_connections=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT count(*) FROM pg_stat_activity;
    ")
    
    local connection_ratio=$((current_connections * 100 / max_connections))
    if [ "$connection_ratio" -gt 80 ]; then
        send_notification "WARNING" "Connections" "Database connection usage is at ${connection_ratio}%"
    fi
    
    # Check long-running queries
    local long_queries=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT count(*) FROM pg_stat_activity 
        WHERE state = 'active' 
        AND (now() - query_start) > interval '5 minutes';
    ")
    
    if [ "$long_queries" -gt 0 ]; then
        send_notification "WARNING" "Long Queries" "$long_queries queries running longer than 5 minutes"
    fi
    
    # Check replication lag
    local replication_lag=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::INT 
        FROM pg_stat_replication;
    ")
    
    if [ ! -z "$replication_lag" ] && [ "$replication_lag" -gt 300 ]; then
        send_notification "WARNING" "Replication" "Replication lag is ${replication_lag} seconds"
    fi
}

# Function to check performance issues
check_performance() {
    echo "Checking database performance..."
    
    # Check cache hit ratio
    local cache_hit=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT round(100 * sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read))::numeric, 2)
        FROM pg_statio_user_tables;
    ")
    
    if (( $(echo "$cache_hit < 90" | bc -l) )); then
        send_notification "WARNING" "Cache" "Cache hit ratio is ${cache_hit}%"
    fi
    
    # Check index usage
    psql "$SUPABASE_DB_URL" -t -c "
        SELECT schemaname, tablename, indexrelname, idx_scan
        FROM pg_stat_user_indexes
        WHERE idx_scan = 0
        AND idx_scan < 50
    " | while read -r line; do
        if [ ! -z "$line" ]; then
            send_notification "INFO" "Indexes" "Unused index found: $line"
        fi
    done
    
    # Check table bloat
    psql "$SUPABASE_DB_URL" -t -c "
        SELECT schemaname, tablename, n_dead_tup
        FROM pg_stat_user_tables
        WHERE n_dead_tup > 10000;
    " | while read -r line; do
        if [ ! -z "$line" ]; then
            send_notification "WARNING" "Bloat" "Table bloat detected: $line"
        fi
    done
}

# Function to check security issues
check_security() {
    echo "Checking security issues..."
    
    # Check failed login attempts
    local failed_logins=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT count(*) FROM pg_stat_activity 
        WHERE backend_type = 'client backend'
        AND state = 'active'
        AND query LIKE '%failed%login%';
    ")
    
    if [ "$failed_logins" -gt 10 ]; then
        send_notification "CRITICAL" "Security" "High number of failed login attempts: $failed_logins"
    fi
    
    # Check superuser connections
    local superuser_connections=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT count(*) FROM pg_stat_activity 
        WHERE usename IN (
            SELECT rolname FROM pg_roles WHERE rolsuper
        );
    ")
    
    if [ "$superuser_connections" -gt 0 ]; then
        send_notification "WARNING" "Security" "Active superuser connections: $superuser_connections"
    fi
    
    # Check SSL usage
    local non_ssl_connections=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT count(*) FROM pg_stat_activity 
        WHERE ssl = false;
    ")
    
    if [ "$non_ssl_connections" -gt 0 ]; then
        send_notification "WARNING" "Security" "Non-SSL connections detected: $non_ssl_connections"
    fi
}

# Function to check backup status
check_backups() {
    echo "Checking backup status..."
    
    # Check last backup time
    local last_backup=$(find "../backups" -name "backup_${ENV}_*.sql.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1)
    
    if [ -z "$last_backup" ]; then
        send_notification "CRITICAL" "Backup" "No backups found"
    else
        local backup_time=$(echo "$last_backup" | cut -d' ' -f1)
        local current_time=$(date +%s)
        local backup_age=$(( (current_time - ${backup_time%.*}) / 3600 ))
        
        if [ "$backup_age" -gt 24 ]; then
            send_notification "WARNING" "Backup" "Last backup is $backup_age hours old"
        fi
    fi
    
    # Check backup size trends
    local backup_sizes=$(find "../backups" -name "backup_${ENV}_*.sql.gz" -type f -printf '%s\n' | sort -n)
    local last_size=$(echo "$backup_sizes" | tail -1)
    local prev_size=$(echo "$backup_sizes" | tail -2 | head -1)
    
    if [ ! -z "$last_size" ] && [ ! -z "$prev_size" ]; then
        local size_diff=$((last_size - prev_size))
        local size_diff_percent=$((size_diff * 100 / prev_size))
        
        if [ "$size_diff_percent" -gt 50 ]; then
            send_notification "WARNING" "Backup" "Backup size changed by ${size_diff_percent}%"
        fi
    fi
}

# Function to generate alert report
generate_report() {
    local report_file="$ALERT_DIR/alert_report_$(date '+%Y%m%d_%H%M%S').txt"
    
    {
        echo "Database Alert Report"
        echo "===================="
        echo "Environment: $ENV"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo
        
        echo "1. Health Check"
        echo "--------------"
        check_health
        echo
        
        echo "2. Performance Check"
        echo "------------------"
        check_performance
        echo
        
        echo "3. Security Check"
        echo "---------------"
        check_security
        echo
        
        echo "4. Backup Check"
        echo "-------------"
        check_backups
        
    } > "$report_file"
    
    echo "Report generated: $report_file"
}

# Process commands
case "${2:-check}" in
    "health")
        check_health
        ;;
        
    "performance")
        check_performance
        ;;
        
    "security")
        check_security
        ;;
        
    "backups")
        check_backups
        ;;
        
    "check")
        check_health
        check_performance
        check_security
        check_backups
        ;;
        
    "report")
        generate_report
        ;;
        
    *)
        echo "Usage: $0 [environment] [health|performance|security|backups|check|report]"
        exit 1
        ;;
esac

exit 0
