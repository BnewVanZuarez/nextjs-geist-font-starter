#!/bin/bash

# Database maintenance script
# Usage: ./maintain_db.sh [environment] [operation]
# Example: ./maintain_db.sh development vacuum

# Set environment
ENV=${1:-development}
echo "Running maintenance operation for $ENV environment"

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

# Create maintenance log directory
LOG_DIR="../logs/maintenance"
mkdir -p "$LOG_DIR"

# Function to log maintenance operations
log_operation() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$LOG_DIR/maintenance.log"
}

# Function to vacuum database
vacuum_db() {
    echo "Performing VACUUM operation..."
    
    if psql "$SUPABASE_DB_URL" -c "VACUUM ANALYZE;"; then
        log_operation "vacuum" "success" "VACUUM ANALYZE completed"
        echo "VACUUM completed successfully"
        return 0
    else
        log_operation "vacuum" "error" "VACUUM ANALYZE failed"
        echo "Error: VACUUM failed"
        return 1
    fi
}

# Function to reindex database
reindex_db() {
    echo "Performing REINDEX operation..."
    
    if psql "$SUPABASE_DB_URL" -c "REINDEX DATABASE current_database;"; then
        log_operation "reindex" "success" "REINDEX completed"
        echo "REINDEX completed successfully"
        return 0
    else
        log_operation "reindex" "error" "REINDEX failed"
        echo "Error: REINDEX failed"
        return 1
    fi
}

# Function to analyze database statistics
analyze_db() {
    echo "Performing ANALYZE operation..."
    
    if psql "$SUPABASE_DB_URL" -c "ANALYZE VERBOSE;"; then
        log_operation "analyze" "success" "ANALYZE completed"
        echo "ANALYZE completed successfully"
        return 0
    else
        log_operation "analyze" "error" "ANALYZE failed"
        echo "Error: ANALYZE failed"
        return 1
    fi
}

# Function to check database size
check_db_size() {
    echo "Checking database size..."
    
    psql "$SUPABASE_DB_URL" << EOF
    SELECT
        pg_size_pretty(pg_database_size(current_database())) as "Database Size",
        pg_size_pretty(pg_total_relation_size('users')) as "Users Table Size",
        pg_size_pretty(pg_total_relation_size('stores')) as "Stores Table Size",
        pg_size_pretty(pg_total_relation_size('products')) as "Products Table Size",
        pg_size_pretty(pg_total_relation_size('transactions')) as "Transactions Table Size";

    SELECT schemaname, relname, n_live_tup, n_dead_tup, last_autovacuum
    FROM pg_stat_user_tables
    ORDER BY n_dead_tup DESC;
EOF
}

# Function to check index usage
check_indexes() {
    echo "Checking index usage..."
    
    psql "$SUPABASE_DB_URL" << EOF
    SELECT
        schemaname,
        relname,
        indexrelname,
        idx_scan,
        idx_tup_read,
        idx_tup_fetch
    FROM pg_stat_user_indexes
    ORDER BY idx_scan DESC;
EOF
}

# Function to check long-running queries
check_queries() {
    echo "Checking active queries..."
    
    psql "$SUPABASE_DB_URL" << EOF
    SELECT
        pid,
        now() - pg_stat_activity.query_start AS duration,
        query,
        state
    FROM pg_stat_activity
    WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes'
    ORDER BY duration DESC;
EOF
}

# Function to optimize tables
optimize_tables() {
    echo "Optimizing tables..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Update table statistics
    ANALYZE VERBOSE;
    
    -- Clean up bloat
    VACUUM FULL ANALYZE users;
    VACUUM FULL ANALYZE stores;
    VACUUM FULL ANALYZE products;
    VACUUM FULL ANALYZE transactions;
    
    -- Reindex important indexes
    REINDEX TABLE users;
    REINDEX TABLE stores;
    REINDEX TABLE products;
    REINDEX TABLE transactions;
EOF

    if [ $? -eq 0 ]; then
        log_operation "optimize" "success" "Table optimization completed"
        echo "Table optimization completed successfully"
        return 0
    else
        log_operation "optimize" "error" "Table optimization failed"
        echo "Error: Table optimization failed"
        return 1
    fi
}

# Process command line arguments
case "${2:-status}" in
    "vacuum")
        if ! vacuum_db; then
            exit 1
        fi
        ;;
        
    "reindex")
        if ! reindex_db; then
            exit 1
        fi
        ;;
        
    "analyze")
        if ! analyze_db; then
            exit 1
        fi
        ;;
        
    "optimize")
        if ! optimize_tables; then
            exit 1
        fi
        ;;
        
    "size")
        check_db_size
        ;;
        
    "indexes")
        check_indexes
        ;;
        
    "queries")
        check_queries
        ;;
        
    "all")
        echo "Running all maintenance operations..."
        
        if ! vacuum_db; then
            exit 1
        fi
        
        if ! reindex_db; then
            exit 1
        fi
        
        if ! analyze_db; then
            exit 1
        fi
        
        if ! optimize_tables; then
            exit 1
        fi
        
        check_db_size
        check_indexes
        check_queries
        ;;
        
    "status")
        echo "Database Status Report"
        echo "--------------------"
        check_db_size
        echo -e "\nIndex Status"
        echo "------------"
        check_indexes
        echo -e "\nLong Running Queries"
        echo "-------------------"
        check_queries
        ;;
        
    *)
        echo "Usage: $0 [environment] [vacuum|reindex|analyze|optimize|size|indexes|queries|all|status]"
        exit 1
        ;;
esac

exit 0
