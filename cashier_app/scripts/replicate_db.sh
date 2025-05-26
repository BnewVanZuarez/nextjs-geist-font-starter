#!/bin/bash

# Database replication script
# Usage: ./replicate_db.sh [environment] [operation]
# Example: ./replicate_db.sh development setup-primary

# Set environment
ENV=${1:-development}
echo "Running replication operations in $ENV environment"

# Load environment variables
if [ -f "../.env.$ENV" ]; then
    source "../.env.$ENV"
else
    echo "Error: Environment file .env.$ENV not found"
    exit 1
fi

# Check required variables
if [ -z "$SUPABASE_DB_URL" ]; then
    echo "Error: SUPABASE_DB_URL is not set"
    exit 1
fi

if [ -z "$REPLICA_DB_URL" ]; then
    echo "Error: REPLICA_DB_URL is not set"
    exit 1
fi

# Create replication logs directory
REPL_DIR="../logs/replication"
mkdir -p "$REPL_DIR"

# Function to log replication operations
log_replication() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$REPL_DIR/replication.log"
}

# Function to setup primary database
setup_primary() {
    echo "Setting up primary database for replication..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Create replication role
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replicator') THEN
            CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'repl_password';
        END IF;
    END
    \$\$;
    
    -- Configure postgresql.conf settings
    ALTER SYSTEM SET wal_level = logical;
    ALTER SYSTEM SET max_wal_senders = 10;
    ALTER SYSTEM SET max_replication_slots = 10;
    
    -- Create publication for all tables
    DROP PUBLICATION IF EXISTS app_publication;
    CREATE PUBLICATION app_publication FOR ALL TABLES;
    
    -- Create replication slot
    SELECT pg_create_logical_replication_slot('app_replication_slot', 'pgoutput')
    WHERE NOT EXISTS (
        SELECT FROM pg_replication_slots 
        WHERE slot_name = 'app_replication_slot'
    );
EOF
    
    log_replication "setup-primary" "success" "Primary database configured for replication"
    echo "Primary database setup completed"
}

# Function to setup replica database
setup_replica() {
    echo "Setting up replica database..."
    
    psql "$REPLICA_DB_URL" << EOF
    -- Create subscription
    DROP SUBSCRIPTION IF EXISTS app_subscription;
    CREATE SUBSCRIPTION app_subscription
    CONNECTION 'host=primary_host port=5432 dbname=app_db user=replicator password=repl_password'
    PUBLICATION app_publication
    WITH (copy_data = true);
EOF
    
    log_replication "setup-replica" "success" "Replica database configured"
    echo "Replica database setup completed"
}

# Function to check replication status
check_status() {
    echo "Checking replication status..."
    
    # Check primary status
    echo "Primary Status:"
    psql "$SUPABASE_DB_URL" << EOF
    -- Check publication
    SELECT * FROM pg_publication;
    
    -- Check replication slots
    SELECT * FROM pg_replication_slots;
    
    -- Check WAL senders
    SELECT * FROM pg_stat_replication;
EOF
    
    # Check replica status
    echo -e "\nReplica Status:"
    psql "$REPLICA_DB_URL" << EOF
    -- Check subscription
    SELECT * FROM pg_subscription;
    
    -- Check subscription tables
    SELECT * FROM pg_stat_subscription;
EOF
}

# Function to monitor replication lag
monitor_lag() {
    echo "Monitoring replication lag..."
    
    psql "$SUPABASE_DB_URL" << EOF
    SELECT 
        client_addr,
        state,
        sent_lsn,
        write_lsn,
        flush_lsn,
        replay_lsn,
        write_lag,
        flush_lag,
        replay_lag
    FROM pg_stat_replication;
EOF
}

# Function to promote replica
promote_replica() {
    echo "Promoting replica to primary..."
    
    read -p "Are you sure you want to promote the replica? This will break replication. (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        psql "$REPLICA_DB_URL" -c "SELECT pg_promote();"
        
        if [ $? -eq 0 ]; then
            log_replication "promote" "success" "Replica promoted to primary"
            echo "Replica promoted successfully"
        else
            log_replication "promote" "error" "Failed to promote replica"
            echo "Error: Failed to promote replica"
            return 1
        fi
    else
        echo "Promotion cancelled"
    fi
}

# Function to resync replica
resync_replica() {
    echo "Resyncing replica database..."
    
    # Drop and recreate subscription
    psql "$REPLICA_DB_URL" << EOF
    DROP SUBSCRIPTION IF EXISTS app_subscription;
    CREATE SUBSCRIPTION app_subscription
    CONNECTION 'host=primary_host port=5432 dbname=app_db user=replicator password=repl_password'
    PUBLICATION app_publication
    WITH (copy_data = true);
EOF
    
    if [ $? -eq 0 ]; then
        log_replication "resync" "success" "Replica resynced with primary"
        echo "Replica resync completed"
    else
        log_replication "resync" "error" "Failed to resync replica"
        echo "Error: Failed to resync replica"
        return 1
    fi
}

# Function to generate replication report
generate_report() {
    local report_file="$REPL_DIR/replication_report_$(date '+%Y%m%d_%H%M%S').txt"
    
    {
        echo "Database Replication Report"
        echo "=========================="
        echo "Environment: $ENV"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo
        
        echo "1. Replication Status"
        echo "-------------------"
        check_status
        echo
        
        echo "2. Replication Lag"
        echo "-----------------"
        monitor_lag
        
    } > "$report_file"
    
    echo "Report generated: $report_file"
}

# Process commands
case "${2:-status}" in
    "setup-primary")
        setup_primary
        ;;
        
    "setup-replica")
        setup_replica
        ;;
        
    "status")
        check_status
        ;;
        
    "monitor")
        monitor_lag
        ;;
        
    "promote")
        promote_replica
        ;;
        
    "resync")
        resync_replica
        ;;
        
    "report")
        generate_report
        ;;
        
    *)
        echo "Usage: $0 [environment] [setup-primary|setup-replica|status|monitor|promote|resync|report]"
        exit 1
        ;;
esac

exit 0
