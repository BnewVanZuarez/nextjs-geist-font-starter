#!/bin/bash

# Database cleanup script
# Usage: ./cleanup_db.sh [environment] [operation]
# Example: ./cleanup_db.sh development transactions

# Set environment
ENV=${1:-development}
echo "Running database cleanup in $ENV environment"

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

# Create cleanup logs directory
CLEANUP_DIR="../logs/cleanup"
mkdir -p "$CLEANUP_DIR"

# Function to log cleanup operations
log_cleanup() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$CLEANUP_DIR/cleanup.log"
}

# Function to archive old transactions
cleanup_transactions() {
    echo "Cleaning up old transactions..."
    
    # Create archive table if it doesn't exist
    psql "$SUPABASE_DB_URL" << EOF
    CREATE TABLE IF NOT EXISTS archived_transactions (
        LIKE transactions INCLUDING ALL
    );
    
    CREATE TABLE IF NOT EXISTS archived_transactions_items (
        LIKE transactions_items INCLUDING ALL
    );
EOF
    
    # Archive transactions older than 1 year
    local start_time=$(date +%s.%N)
    local archived_count=$(psql "$SUPABASE_DB_URL" -t -c "
        WITH moved_transactions AS (
            DELETE FROM transactions 
            WHERE created_at < NOW() - INTERVAL '1 year'
            RETURNING *
        )
        INSERT INTO archived_transactions 
        SELECT * FROM moved_transactions
        RETURNING id;
    " | wc -l)
    
    # Archive related transaction items
    local archived_items=$(psql "$SUPABASE_DB_URL" -t -c "
        WITH moved_items AS (
            DELETE FROM transactions_items 
            WHERE transaction_id IN (SELECT id FROM archived_transactions)
            RETURNING *
        )
        INSERT INTO archived_transactions_items 
        SELECT * FROM moved_items
        RETURNING id;
    " | wc -l)
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    
    log_cleanup "transactions" "success" "Archived $archived_count transactions and $archived_items items in $duration seconds"
    echo "Archived $archived_count transactions and $archived_items items (${duration}s)"
}

# Function to clean up inactive users
cleanup_users() {
    echo "Cleaning up inactive users..."
    
    # Create archive table if it doesn't exist
    psql "$SUPABASE_DB_URL" << EOF
    CREATE TABLE IF NOT EXISTS archived_users (
        LIKE users INCLUDING ALL
    );
EOF
    
    # Archive users inactive for more than 1 year
    local start_time=$(date +%s.%N)
    local archived_count=$(psql "$SUPABASE_DB_URL" -t -c "
        WITH moved_users AS (
            DELETE FROM users 
            WHERE updated_at < NOW() - INTERVAL '1 year'
            AND NOT EXISTS (
                SELECT 1 FROM transactions 
                WHERE transactions.user_id = users.id 
                AND transactions.created_at > NOW() - INTERVAL '1 year'
            )
            RETURNING *
        )
        INSERT INTO archived_users 
        SELECT * FROM moved_users
        RETURNING id;
    " | wc -l)
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    
    log_cleanup "users" "success" "Archived $archived_count inactive users in $duration seconds"
    echo "Archived $archived_count inactive users (${duration}s)"
}

# Function to clean up old payment logs
cleanup_payments() {
    echo "Cleaning up old payment logs..."
    
    # Create archive table if it doesn't exist
    psql "$SUPABASE_DB_URL" << EOF
    CREATE TABLE IF NOT EXISTS archived_payment_logs (
        LIKE payment_logs INCLUDING ALL
    );
EOF
    
    # Archive payment logs older than 1 year
    local start_time=$(date +%s.%N)
    local archived_count=$(psql "$SUPABASE_DB_URL" -t -c "
        WITH moved_logs AS (
            DELETE FROM payment_logs 
            WHERE created_at < NOW() - INTERVAL '1 year'
            RETURNING *
        )
        INSERT INTO archived_payment_logs 
        SELECT * FROM moved_logs
        RETURNING id;
    " | wc -l)
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    
    log_cleanup "payments" "success" "Archived $archived_count payment logs in $duration seconds"
    echo "Archived $archived_count payment logs (${duration}s)"
}

# Function to vacuum database
cleanup_vacuum() {
    echo "Running VACUUM FULL..."
    
    local start_time=$(date +%s.%N)
    if psql "$SUPABASE_DB_URL" -c "VACUUM FULL ANALYZE;" > /dev/null 2>&1; then
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc)
        log_cleanup "vacuum" "success" "VACUUM FULL completed in $duration seconds"
        echo "VACUUM FULL completed (${duration}s)"
    else
        log_cleanup "vacuum" "error" "VACUUM FULL failed"
        echo "VACUUM FULL failed"
    fi
}

# Function to clean up temporary tables
cleanup_temp() {
    echo "Cleaning up temporary tables..."
    
    local start_time=$(date +%s.%N)
    local temp_tables=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_name LIKE 'temp_%'
        OR table_name LIKE 'test_%';
    ")
    
    if [ ! -z "$temp_tables" ]; then
        for table in $temp_tables; do
            if psql "$SUPABASE_DB_URL" -c "DROP TABLE IF EXISTS $table;" > /dev/null 2>&1; then
                log_cleanup "temp" "success" "Dropped table $table"
                echo "Dropped table $table"
            else
                log_cleanup "temp" "error" "Failed to drop table $table"
                echo "Failed to drop table $table"
            fi
        done
    fi
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    echo "Temporary cleanup completed (${duration}s)"
}

# Function to generate cleanup report
generate_report() {
    local report_file="$CLEANUP_DIR/cleanup_report_$(date '+%Y%m%d_%H%M%S').txt"
    
    {
        echo "Database Cleanup Report"
        echo "======================"
        echo "Environment: $ENV"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo
        
        echo "1. Transaction Cleanup"
        echo "---------------------"
        cleanup_transactions
        echo
        
        echo "2. User Cleanup"
        echo "--------------"
        cleanup_users
        echo
        
        echo "3. Payment Log Cleanup"
        echo "---------------------"
        cleanup_payments
        echo
        
        echo "4. Temporary Table Cleanup"
        echo "-------------------------"
        cleanup_temp
        echo
        
        echo "5. Database Vacuum"
        echo "-----------------"
        cleanup_vacuum
        
    } > "$report_file"
    
    echo "Report generated: $report_file"
}

# Process commands
case "${2:-all}" in
    "transactions")
        cleanup_transactions
        ;;
        
    "users")
        cleanup_users
        ;;
        
    "payments")
        cleanup_payments
        ;;
        
    "vacuum")
        cleanup_vacuum
        ;;
        
    "temp")
        cleanup_temp
        ;;
        
    "all")
        generate_report
        ;;
        
    *)
        echo "Usage: $0 [environment] [transactions|users|payments|vacuum|temp|all]"
        exit 1
        ;;
esac

exit 0
