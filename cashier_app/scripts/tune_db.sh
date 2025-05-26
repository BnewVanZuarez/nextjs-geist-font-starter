#!/bin/bash

# Database tuning script
# Usage: ./tune_db.sh [environment] [operation]
# Example: ./tune_db.sh development auto-tune

# Set environment
ENV=${1:-development}
echo "Managing database tuning for $ENV environment"

# Load environment variables
if [ -f "../.env.$ENV" ]; then
    source "../.env.$ENV"
else
    echo "Error: Environment file .env.$ENV not found"
    exit 1
fi

# Create tuning logs directory
TUNE_DIR="../logs/tuning"
mkdir -p "$TUNE_DIR"

# Function to log tuning operations
log_tuning() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$TUNE_DIR/tuning.log"
}

# Function to analyze system resources
analyze_resources() {
    echo "Analyzing system resources..."
    
    # Get system memory
    local total_memory=$(free -b | awk '/^Mem:/{print $2}')
    local available_memory=$(free -b | awk '/^Mem:/{print $7}')
    
    # Get CPU info
    local cpu_cores=$(nproc)
    
    # Get disk info
    local disk_space=$(df -B1 . | awk 'NR==2 {print $4}')
    
    # Calculate recommended settings
    local shared_buffers=$((total_memory / 4))
    local effective_cache_size=$((total_memory * 3 / 4))
    local maintenance_work_mem=$((total_memory / 16))
    local work_mem=$((total_memory / (cpu_cores * 4)))
    
    echo "System Analysis:"
    echo "Total Memory: $(numfmt --to=iec $total_memory)"
    echo "Available Memory: $(numfmt --to=iec $available_memory)"
    echo "CPU Cores: $cpu_cores"
    echo "Available Disk Space: $(numfmt --to=iec $disk_space)"
    echo
    echo "Recommended Settings:"
    echo "shared_buffers = $(numfmt --to=iec $shared_buffers)"
    echo "effective_cache_size = $(numfmt --to=iec $effective_cache_size)"
    echo "maintenance_work_mem = $(numfmt --to=iec $maintenance_work_mem)"
    echo "work_mem = $(numfmt --to=iec $work_mem)"
}

# Function to auto-tune database
auto_tune() {
    echo "Auto-tuning database..."
    
    # Get system info
    local total_memory=$(free -b | awk '/^Mem:/{print $2}')
    local cpu_cores=$(nproc)
    
    # Apply optimized settings
    psql "$SUPABASE_DB_URL" << EOF
    -- Memory settings
    ALTER SYSTEM SET shared_buffers = '$(echo "$total_memory/4" | bc)B';
    ALTER SYSTEM SET effective_cache_size = '$(echo "$total_memory*3/4" | bc)B';
    ALTER SYSTEM SET maintenance_work_mem = '$(echo "$total_memory/16" | bc)B';
    ALTER SYSTEM SET work_mem = '$(echo "$total_memory/($cpu_cores*4)" | bc)B';
    
    -- Query planner settings
    ALTER SYSTEM SET random_page_cost = 1.1;
    ALTER SYSTEM SET effective_io_concurrency = 200;
    ALTER SYSTEM SET default_statistics_target = 100;
    
    -- Parallel query settings
    ALTER SYSTEM SET max_parallel_workers_per_gather = $((cpu_cores / 2));
    ALTER SYSTEM SET max_parallel_workers = $cpu_cores;
    ALTER SYSTEM SET max_parallel_maintenance_workers = $((cpu_cores / 2));
    
    -- WAL settings
    ALTER SYSTEM SET wal_buffers = '16MB';
    ALTER SYSTEM SET checkpoint_completion_target = 0.9;
    ALTER SYSTEM SET checkpoint_timeout = '15min';
    
    -- Connection settings
    ALTER SYSTEM SET max_connections = $((cpu_cores * 4));
    
    -- Vacuum settings
    ALTER SYSTEM SET autovacuum_vacuum_scale_factor = 0.1;
    ALTER SYSTEM SET autovacuum_analyze_scale_factor = 0.05;
EOF
    
    log_tuning "auto-tune" "success" "Applied optimized settings"
    echo "Database auto-tuned successfully"
}

# Function to analyze query performance
analyze_queries() {
    echo "Analyzing query performance..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Enable query statistics collection
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
    
    -- Show top time-consuming queries
    SELECT
        substring(query, 1, 100) as query_snippet,
        calls,
        total_time / 1000 as total_seconds,
        mean_time / 1000 as mean_seconds,
        rows,
        100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0) as hit_percent
    FROM pg_stat_statements
    ORDER BY total_time DESC
    LIMIT 10;
    
    -- Show queries with poor cache hit ratio
    SELECT
        substring(query, 1, 100) as query_snippet,
        calls,
        shared_blks_hit,
        shared_blks_read,
        100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0) as hit_percent
    FROM pg_stat_statements
    WHERE shared_blks_read > 0
    ORDER BY hit_percent ASC
    LIMIT 10;
    
    -- Show queries with high row counts
    SELECT
        substring(query, 1, 100) as query_snippet,
        calls,
        rows,
        rows / calls as avg_rows
    FROM pg_stat_statements
    ORDER BY rows DESC
    LIMIT 10;
EOF
}

# Function to optimize indexes
optimize_indexes() {
    echo "Optimizing indexes..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Find missing indexes
    WITH table_scans as (
        SELECT relid,
               tables.idx_scan + tables.seq_scan as all_scans,
               ( tables.n_tup_ins + tables.n_tup_upd + tables.n_tup_del ) as writes,
               tables.n_live_tup as rows_in_table
        FROM pg_stat_user_tables as tables
    ),
    all_writes as (
        SELECT sum(writes) as total_writes
        FROM table_scans
    ),
    indexes as (
        SELECT idx_stat.relid, idx_stat.indexrelid,
               idx_stat.idx_scan, pg_index.indisunique,
               pg_index.indisprimary,
               indexdef ~* 'using btree' as idx_is_btree
        FROM pg_stat_user_indexes as idx_stat
        JOIN pg_index ON idx_stat.indexrelid = pg_index.indexrelid
        JOIN pg_indexes ON idx_stat.schemaname = pg_indexes.schemaname
            AND idx_stat.tablename = pg_indexes.tablename
            AND pg_indexes.indexname = pg_stat_user_indexes.indexrelname
    ),
    index_ratios AS (
        SELECT relid,
               CASE WHEN all_scans = 0 THEN 0
                    ELSE idx_scan::float / all_scans * 100 END as index_scan_pct
        FROM table_scans
        JOIN indexes USING (relid)
    )
    SELECT
        schemaname,
        tablename,
        reltuples::bigint as rows,
        pg_size_pretty(pg_relation_size(quote_ident(schemaname) || '.' || quote_ident(tablename))) as table_size,
        seq_scan as sequential_scans,
        idx_scan as index_scans
    FROM pg_stat_user_tables
    WHERE seq_scan > 10
    AND pg_relation_size(quote_ident(schemaname) || '.' || quote_ident(tablename)) > 100000
    ORDER BY seq_scan DESC;
    
    -- Find unused indexes
    SELECT
        schemaname || '.' || tablename as table,
        indexname as index,
        pg_size_pretty(pg_relation_size(quote_ident(schemaname) || '.' || quote_ident(indexname))) as index_size,
        idx_scan as index_scans
    FROM pg_stat_user_indexes
    JOIN pg_index ON indexrelid = pg_index.indexrelid
    WHERE idx_scan = 0
    AND indisunique is false
    AND indisprimary is false
    ORDER BY pg_relation_size(quote_ident(schemaname) || '.' || quote_ident(indexname)) DESC;
    
    -- Find redundant indexes
    WITH index_cols AS (
        SELECT
            pg_class.relname as tablename,
            pg_class.oid as tableid,
            pg_index.indexrelid,
            pg_index.indrelid,
            pg_index.indkey,
            pg_index.indisunique,
            pg_index.indisprimary,
            pg_class2.relname as indexname,
            array_to_string(array_agg(pg_attribute.attname ORDER BY attnum), ', ') as cols
        FROM pg_index
        JOIN pg_class ON pg_class.oid = pg_index.indrelid
        JOIN pg_class pg_class2 ON pg_class2.oid = pg_index.indexrelid
        JOIN pg_attribute ON pg_attribute.attrelid = pg_index.indrelid
        AND pg_attribute.attnum = ANY(pg_index.indkey)
        WHERE pg_class.relnamespace = 'public'::regnamespace
        GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
    )
    SELECT
        ic1.tablename,
        ic1.indexname as index1,
        ic2.indexname as index2,
        ic1.cols
    FROM index_cols ic1
    JOIN index_cols ic2 ON ic1.tableid = ic2.tableid
    AND ic1.indexrelid < ic2.indexrelid
    AND (
        ic1.cols LIKE ic2.cols || '%'
        OR ic2.cols LIKE ic1.cols || '%'
    );
EOF
}

# Function to tune autovacuum
tune_autovacuum() {
    echo "Tuning autovacuum settings..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Set autovacuum parameters
    ALTER SYSTEM SET autovacuum_vacuum_threshold = 50;
    ALTER SYSTEM SET autovacuum_vacuum_scale_factor = 0.1;
    ALTER SYSTEM SET autovacuum_analyze_threshold = 50;
    ALTER SYSTEM SET autovacuum_analyze_scale_factor = 0.05;
    ALTER SYSTEM SET autovacuum_vacuum_cost_delay = 2;
    ALTER SYSTEM SET autovacuum_vacuum_cost_limit = 200;
    
    -- Show current autovacuum statistics
    SELECT
        schemaname,
        relname,
        n_dead_tup,
        n_live_tup,
        last_vacuum,
        last_autovacuum,
        last_analyze,
        last_autoanalyze
    FROM pg_stat_user_tables
    ORDER BY n_dead_tup DESC;
EOF
    
    log_tuning "autovacuum" "success" "Optimized autovacuum settings"
    echo "Autovacuum settings tuned"
}

# Function to generate tuning report
generate_report() {
    local report_file="$TUNE_DIR/tuning_report_$(date '+%Y%m%d_%H%M%S').md"
    
    {
        echo "# Database Tuning Report"
        echo "Generated on: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Environment: $ENV"
        echo
        
        echo "## System Resources"
        echo
        analyze_resources
        echo
        
        echo "## Current Settings"
        echo
        psql "$SUPABASE_DB_URL" -c "
            SELECT name, setting, unit, context
            FROM pg_settings
            WHERE name IN (
                'shared_buffers',
                'effective_cache_size',
                'work_mem',
                'maintenance_work_mem',
                'random_page_cost',
                'effective_io_concurrency',
                'default_statistics_target',
                'max_parallel_workers_per_gather',
                'max_parallel_workers',
                'autovacuum_vacuum_scale_factor',
                'autovacuum_analyze_scale_factor'
            )
            ORDER BY name;
        "
        echo
        
        echo "## Query Performance"
        echo
        analyze_queries
        echo
        
        echo "## Index Analysis"
        echo
        optimize_indexes
        
    } > "$report_file"
    
    log_tuning "report" "success" "Generated tuning report"
    echo "Report generated: $report_file"
}

# Process commands
case "${2:-analyze}" in
    "analyze")
        analyze_resources
        ;;
        
    "auto-tune")
        auto_tune
        ;;
        
    "queries")
        analyze_queries
        ;;
        
    "indexes")
        optimize_indexes
        ;;
        
    "autovacuum")
        tune_autovacuum
        ;;
        
    "report")
        generate_report
        ;;
        
    *)
        echo "Usage: $0 [environment] [analyze|auto-tune|queries|indexes|autovacuum|report]"
        exit 1
        ;;
esac

exit 0
