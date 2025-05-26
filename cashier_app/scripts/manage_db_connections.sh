#!/bin/bash

# Database connection management script
# Usage: ./manage_db_connections.sh [environment] [operation]
# Example: ./manage_db_connections.sh development configure-pool

# Set environment
ENV=${1:-development}
echo "Managing database connections for $ENV environment"

# Load environment variables
if [ -f "../.env.$ENV" ]; then
    source "../.env.$ENV"
else
    echo "Error: Environment file .env.$ENV not found"
    exit 1
fi

# Create connection management logs directory
CONN_DIR="../logs/connections"
mkdir -p "$CONN_DIR"

# Function to log connection management operations
log_connection() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$CONN_DIR/connections.log"
}

# Function to configure connection pooling
configure_pool() {
    echo "Configuring connection pooling..."
    
    # Calculate optimal pool settings based on available resources
    local max_connections=$(psql "$SUPABASE_DB_URL" -t -c "SHOW max_connections;")
    local cpu_cores=$(nproc)
    local total_memory=$(free -g | awk '/^Mem:/{print $2}')
    
    # Calculate pool size (25% of max_connections)
    local pool_size=$((max_connections / 4))
    
    # Calculate minimum spare connections (10% of pool_size)
    local min_spare=$((pool_size / 10))
    
    # Calculate maximum spare connections (20% of pool_size)
    local max_spare=$((pool_size / 5))
    
    # Configure PgBouncer
    cat > "/etc/pgbouncer/pgbouncer.ini" << EOF
[databases]
* = host=localhost port=5432

[pgbouncer]
listen_port = 6432
listen_addr = *
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
admin_users = postgres
pool_mode = transaction
max_client_conn = $max_connections
default_pool_size = $pool_size
min_pool_size = $min_spare
reserve_pool_size = $max_spare
reserve_pool_timeout = 5
max_db_connections = $pool_size
max_user_connections = 0
server_reset_query = DISCARD ALL
server_check_delay = 30
server_check_query = select 1
server_fast_close = 0
tcp_keepalive = 1
tcp_keepidle = 60
tcp_keepintvl = 30
EOF
    
    # Create user list file
    echo "\"postgres\" \"$(openssl rand -base64 32)\"" > "/etc/pgbouncer/userlist.txt"
    
    # Restart PgBouncer
    systemctl restart pgbouncer
    
    log_connection "configure-pool" "success" "Configured connection pool with size $pool_size"
    echo "Connection pooling configured successfully"
}

# Function to monitor active connections
monitor_connections() {
    echo "Monitoring active connections..."
    
    while true; do
        clear
        date
        echo
        
        psql "$SUPABASE_DB_URL" << EOF
        -- Show active connections
        SELECT 
            datname as database,
            usename as username,
            application_name,
            client_addr,
            backend_start,
            state,
            wait_event_type,
            wait_event,
            query
        FROM pg_stat_activity
        WHERE state != 'idle'
        AND pid != pg_backend_pid()
        ORDER BY backend_start DESC;
        
        -- Show connection counts by state
        SELECT 
            state,
            count(*) as count
        FROM pg_stat_activity
        GROUP BY state
        ORDER BY count DESC;
        
        -- Show longest running queries
        SELECT 
            pid,
            now() - query_start as duration,
            state,
            query
        FROM pg_stat_activity
        WHERE state != 'idle'
        AND query_start is not null
        ORDER BY duration DESC
        LIMIT 5;
EOF
        
        sleep 5
    done
}

# Function to kill problematic connections
kill_connection() {
    local pid=$1
    
    if [ -z "$pid" ]; then
        echo "Error: Process ID not specified"
        echo "Usage: $0 $ENV kill-connection <pid>"
        return 1
    fi
    
    echo "Terminating connection with PID: $pid..."
    
    psql "$SUPABASE_DB_URL" << EOF
    SELECT pg_terminate_backend($pid);
EOF
    
    log_connection "kill" "success" "Terminated connection with PID $pid"
    echo "Connection terminated successfully"
}

# Function to analyze connection patterns
analyze_connections() {
    echo "Analyzing connection patterns..."
    
    local report_file="$CONN_DIR/connection_analysis_$(date '+%Y%m%d_%H%M%S').md"
    
    {
        echo "# Database Connection Analysis"
        echo "Generated on: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Environment: $ENV"
        echo
        
        echo "## Current Connection Status"
        echo
        psql "$SUPABASE_DB_URL" << EOF
        -- Show connection limits
        SELECT 
            current_setting('max_connections')::int as max_connections,
            count(*) as current_connections,
            count(*) * 100.0 / current_setting('max_connections')::int as connection_percentage
        FROM pg_stat_activity;
        
        -- Show connection distribution
        SELECT 
            usename,
            count(*) as connection_count,
            count(*) * 100.0 / sum(count(*)) over () as percentage
        FROM pg_stat_activity
        GROUP BY usename
        ORDER BY connection_count DESC;
        
        -- Show application distribution
        SELECT 
            application_name,
            count(*) as connection_count
        FROM pg_stat_activity
        WHERE application_name != ''
        GROUP BY application_name
        ORDER BY connection_count DESC;
        
        -- Show client address distribution
        SELECT 
            client_addr,
            count(*) as connection_count
        FROM pg_stat_activity
        WHERE client_addr is not null
        GROUP BY client_addr
        ORDER BY connection_count DESC;
EOF
        
        echo
        echo "## Connection Duration Analysis"
        echo
        psql "$SUPABASE_DB_URL" << EOF
        SELECT 
            usename,
            state,
            count(*) as connections,
            avg(extract(epoch from (now() - backend_start)))::integer as avg_duration_seconds,
            min(extract(epoch from (now() - backend_start)))::integer as min_duration_seconds,
            max(extract(epoch from (now() - backend_start)))::integer as max_duration_seconds
        FROM pg_stat_activity
        GROUP BY usename, state
        ORDER BY connections DESC;
EOF
        
        echo
        echo "## Idle Connection Analysis"
        echo
        psql "$SUPABASE_DB_URL" << EOF
        SELECT 
            usename,
            count(*) as idle_connections,
            avg(extract(epoch from (now() - state_change)))::integer as avg_idle_seconds
        FROM pg_stat_activity
        WHERE state = 'idle'
        GROUP BY usename
        ORDER BY idle_connections DESC;
EOF
        
    } > "$report_file"
    
    log_connection "analyze" "success" "Generated connection analysis report"
    echo "Analysis report generated: $report_file"
}

# Function to set connection limits
set_limits() {
    local max_conn=$1
    local per_user=$2
    
    if [ -z "$max_conn" ] || [ -z "$per_user" ]; then
        echo "Error: Missing parameters"
        echo "Usage: $0 $ENV set-limits <max_connections> <per_user_connections>"
        return 1
    fi
    
    echo "Setting connection limits..."
    
    psql "$SUPABASE_DB_URL" << EOF
    ALTER SYSTEM SET max_connections = '$max_conn';
    ALTER SYSTEM SET superuser_reserved_connections = '3';
    
    -- Set per-user connection limits
    SELECT 
        format('ALTER ROLE %I CONNECTION LIMIT %s', rolname, '$per_user')
    FROM pg_roles
    WHERE rolname !~ '^pg_'
    AND rolcanlogin = true;
EOF
    
    log_connection "set-limits" "success" "Set max_connections=$max_conn, per_user=$per_user"
    echo "Connection limits set successfully"
}

# Function to generate connection report
generate_report() {
    local report_file="$CONN_DIR/connection_report_$(date '+%Y%m%d_%H%M%S').md"
    
    {
        echo "# Database Connection Report"
        echo "Generated on: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Environment: $ENV"
        echo
        
        echo "## Connection Settings"
        echo
        psql "$SUPABASE_DB_URL" << EOF
        SELECT name, setting, unit, context
        FROM pg_settings
        WHERE name IN (
            'max_connections',
            'superuser_reserved_connections',
            'idle_in_transaction_session_timeout',
            'statement_timeout',
            'tcp_keepalives_idle',
            'tcp_keepalives_interval'
        )
        ORDER BY name;
EOF
        
        echo
        echo "## Current Connections"
        echo
        analyze_connections
        
    } > "$report_file"
    
    log_connection "report" "success" "Generated connection report"
    echo "Report generated: $report_file"
}

# Process commands
case "${2:-status}" in
    "configure-pool")
        configure_pool
        ;;
        
    "monitor")
        monitor_connections
        ;;
        
    "kill")
        kill_connection "$3"
        ;;
        
    "analyze")
        analyze_connections
        ;;
        
    "set-limits")
        set_limits "$3" "$4"
        ;;
        
    "report")
        generate_report
        ;;
        
    *)
        echo "Usage: $0 [environment] [configure-pool|monitor|kill|analyze|set-limits|report] [args]"
        exit 1
        ;;
esac

exit 0
