#!/bin/bash

# Database recovery script
# Usage: ./recover_db.sh [environment] [operation]
# Example: ./recover_db.sh development pitr "2023-12-01 14:30:00"

# Set environment
ENV=${1:-development}
echo "Managing database recovery for $ENV environment"

# Load environment variables
if [ -f "../.env.$ENV" ]; then
    source "../.env.$ENV"
else
    echo "Error: Environment file .env.$ENV not found"
    exit 1
fi

# Create recovery directory
RECOVERY_DIR="../recovery"
mkdir -p "$RECOVERY_DIR"

# Create recovery logs directory
LOG_DIR="../logs/recovery"
mkdir -p "$LOG_DIR"

# Function to log recovery operations
log_recovery() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$LOG_DIR/recovery.log"
}

# Function to perform point-in-time recovery
pitr_recovery() {
    local target_time=$1
    
    if [ -z "$target_time" ]; then
        echo "Error: Target time not specified"
        echo "Usage: $0 $ENV pitr \"YYYY-MM-DD HH:MM:SS\""
        return 1
    fi
    
    echo "Performing point-in-time recovery to $target_time..."
    
    # Create recovery instance name
    local recovery_name="recovery_${ENV}_$(date '+%Y%m%d_%H%M%S')"
    
    # Create recovery configuration
    cat > "$RECOVERY_DIR/recovery.conf" << EOF
restore_command = 'cp /var/lib/postgresql/archive/%f %p'
recovery_target_time = '$target_time'
recovery_target_timeline = 'latest'
EOF
    
    # Stop the database
    pg_ctl stop -D "$PGDATA"
    
    # Backup current data directory
    mv "$PGDATA" "${PGDATA}.backup"
    
    # Create new data directory
    mkdir -p "$PGDATA"
    
    # Restore from latest base backup
    pg_basebackup -D "$PGDATA" -h localhost -U postgres
    
    # Copy recovery configuration
    cp "$RECOVERY_DIR/recovery.conf" "$PGDATA/recovery.conf"
    
    # Start database in recovery mode
    pg_ctl start -D "$PGDATA"
    
    # Wait for recovery to complete
    while pg_isready -h localhost -p 5432 >/dev/null 2>&1; do
        sleep 1
        if [ -f "$PGDATA/recovery.done" ]; then
            break
        fi
    done
    
    log_recovery "pitr" "success" "Recovered to $target_time"
    echo "Point-in-time recovery completed"
}

# Function to perform crash recovery
crash_recovery() {
    echo "Performing crash recovery..."
    
    # Check database status
    if ! pg_isready -h localhost -p 5432 >/dev/null 2>&1; then
        echo "Database is not responding, attempting recovery..."
        
        # Try to start database
        if pg_ctl start -D "$PGDATA"; then
            echo "Database started successfully"
            
            # Check for consistency
            if psql "$SUPABASE_DB_URL" -c "SELECT 1;" >/dev/null 2>&1; then
                log_recovery "crash" "success" "Database recovered successfully"
                echo "Crash recovery completed successfully"
            else
                log_recovery "crash" "error" "Database is inconsistent after recovery"
                echo "Error: Database is inconsistent after recovery"
                return 1
            fi
        else
            log_recovery "crash" "error" "Failed to start database"
            echo "Error: Failed to start database"
            return 1
        fi
    else
        echo "Database is already running"
    fi
}

# Function to verify database consistency
verify_consistency() {
    echo "Verifying database consistency..."
    
    # Run consistency checks
    psql "$SUPABASE_DB_URL" << EOF
    -- Check for invalid indexes
    SELECT schemaname, tablename, indexname
    FROM pg_indexes
    WHERE indexdef LIKE '%INVALID%';
    
    -- Check for corrupted tables
    SELECT relname, last_vacuum, last_autovacuum,
           n_dead_tup, n_live_tup, n_mod_since_analyze
    FROM pg_stat_user_tables
    WHERE n_dead_tup > n_live_tup;
    
    -- Check for long-running transactions
    SELECT pid, usename, application_name,
           age(clock_timestamp(), xact_start) as xact_age,
           query
    FROM pg_stat_activity
    WHERE state != 'idle'
    AND age(clock_timestamp(), xact_start) > interval '1 hour';
    
    -- Check for bloated tables
    SELECT schemaname, tablename,
           pg_size_pretty(pg_total_relation_size(quote_ident(schemaname) || '.' || quote_ident(tablename))) as size,
           pg_size_pretty(bloat_size) as bloat_size,
           round(bloat_ratio::numeric, 2) as bloat_ratio
    FROM (
        SELECT *, (bloat_size::float / pg_total_relation_size(quote_ident(schemaname) || '.' || quote_ident(tablename))) * 100 as bloat_ratio
        FROM (
            SELECT schemaname, tablename,
                   pg_total_relation_size(quote_ident(schemaname) || '.' || quote_ident(tablename)) - pg_relation_size(quote_ident(schemaname) || '.' || quote_ident(tablename)) as bloat_size
            FROM pg_tables
            WHERE schemaname = 'public'
        ) t
    ) t
    WHERE bloat_ratio > 20
    ORDER BY bloat_ratio DESC;
EOF
}

# Function to repair database objects
repair_database() {
    echo "Repairing database objects..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Reindex invalid indexes
    DO \$\$
    DECLARE
        idx record;
    BEGIN
        FOR idx IN
            SELECT schemaname, tablename, indexname
            FROM pg_indexes
            WHERE indexdef LIKE '%INVALID%'
        LOOP
            EXECUTE format('REINDEX INDEX %I.%I', idx.schemaname, idx.indexname);
            RAISE NOTICE 'Reindexed: %.%', idx.schemaname, idx.indexname;
        END LOOP;
    END;
    \$\$;
    
    -- Vacuum full bloated tables
    DO \$\$
    DECLARE
        tbl record;
    BEGIN
        FOR tbl IN
            SELECT schemaname, tablename
            FROM pg_tables
            WHERE schemaname = 'public'
            AND EXISTS (
                SELECT 1
                FROM pg_stat_user_tables
                WHERE schemaname = tbl.schemaname
                AND relname = tbl.tablename
                AND n_dead_tup > n_live_tup
            )
        LOOP
            EXECUTE format('VACUUM FULL ANALYZE %I.%I', tbl.schemaname, tbl.tablename);
            RAISE NOTICE 'Vacuumed: %.%', tbl.schemaname, tbl.tablename;
        END LOOP;
    END;
    \$\$;
    
    -- Terminate long-running transactions
    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE state != 'idle'
    AND age(clock_timestamp(), xact_start) > interval '1 hour';
EOF
    
    log_recovery "repair" "success" "Database objects repaired"
    echo "Database repair completed"
}

# Function to generate recovery report
generate_report() {
    local report_file="$LOG_DIR/recovery_report_$(date '+%Y%m%d_%H%M%S').md"
    
    {
        echo "# Database Recovery Report"
        echo "Generated on: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Environment: $ENV"
        echo
        
        echo "## Database Status"
        echo
        if pg_isready -h localhost -p 5432; then
            echo "Database is running"
        else
            echo "Database is not responding"
        fi
        echo
        
        echo "## Consistency Check"
        echo
        verify_consistency
        echo
        
        echo "## Recent Recovery Operations"
        echo
        tail -n 20 "$LOG_DIR/recovery.log"
        
    } > "$report_file"
    
    log_recovery "report" "success" "Generated recovery report"
    echo "Report generated: $report_file"
}

# Process commands
case "${2:-verify}" in
    "pitr")
        pitr_recovery "$3"
        ;;
        
    "crash")
        crash_recovery
        ;;
        
    "verify")
        verify_consistency
        ;;
        
    "repair")
        repair_database
        ;;
        
    "report")
        generate_report
        ;;
        
    *)
        echo "Usage: $0 [environment] [pitr|crash|verify|repair|report] [args]"
        exit 1
        ;;
esac

exit 0
