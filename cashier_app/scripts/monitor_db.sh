#!/bin/bash

# Database monitoring script
# Usage: ./monitor_db.sh [environment] [command]
# Example: ./monitor_db.sh development health

# Set environment
ENV=${1:-development}
echo "Monitoring database in $ENV environment"

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

# Create monitoring directory
MONITOR_DIR="../logs/monitoring"
mkdir -p "$MONITOR_DIR"

# Function to log monitoring data
log_monitoring() {
    local check=$1
    local status=$2
    local data=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $check: $status - $data" >> "$MONITOR_DIR/monitoring.log"
}

# Function to check database health
check_health() {
    echo "Checking database health..."
    
    # Check connection
    if ! psql "$SUPABASE_DB_URL" -c "SELECT 1;" > /dev/null 2>&1; then
        log_monitoring "health" "error" "Cannot connect to database"
        return 1
    fi
    
    # Check database size
    local db_size=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT pg_size_pretty(pg_database_size(current_database()));
    ")
    log_monitoring "health" "info" "Database size: $db_size"
    
    # Check connection count
    local connections=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT count(*) FROM pg_stat_activity;
    ")
    log_monitoring "health" "info" "Active connections: $connections"
    
    # Check long-running queries
    local long_queries=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT count(*) FROM pg_stat_activity 
        WHERE state = 'active' 
        AND (now() - query_start) > interval '5 minutes';
    ")
    log_monitoring "health" "info" "Long-running queries: $long_queries"
    
    # Check dead tuples
    psql "$SUPABASE_DB_URL" -t -c "
        SELECT schemaname, relname, n_dead_tup, last_autovacuum 
        FROM pg_stat_user_tables 
        WHERE n_dead_tup > 1000 
        ORDER BY n_dead_tup DESC;
    "
    
    return 0
}

# Function to check performance metrics
check_performance() {
    echo "Checking database performance..."
    
    # Check index usage
    psql "$SUPABASE_DB_URL" << EOF
    SELECT 
        schemaname, 
        relname, 
        indexrelname, 
        idx_scan, 
        idx_tup_read, 
        idx_tup_fetch 
    FROM pg_stat_user_indexes 
    WHERE idx_scan = 0 
    AND schemaname = 'public'
    ORDER BY relname, indexrelname;
EOF
    
    # Check table statistics
    psql "$SUPABASE_DB_URL" << EOF
    SELECT 
        relname, 
        seq_scan, 
        seq_tup_read, 
        idx_scan, 
        idx_tup_fetch,
        n_tup_ins, 
        n_tup_upd, 
        n_tup_del
    FROM pg_stat_user_tables 
    WHERE schemaname = 'public'
    ORDER BY relname;
EOF
    
    # Check cache hit ratio
    psql "$SUPABASE_DB_URL" << EOF
    SELECT 
        sum(heap_blks_read) as heap_read,
        sum(heap_blks_hit)  as heap_hit,
        sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as ratio
    FROM pg_statio_user_tables;
EOF
}

# Function to check storage usage
check_storage() {
    echo "Checking storage usage..."
    
    # Table sizes
    psql "$SUPABASE_DB_URL" << EOF
    SELECT 
        relname as table_name,
        pg_size_pretty(pg_total_relation_size(relid)) as total_size,
        pg_size_pretty(pg_relation_size(relid)) as table_size,
        pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) as index_size
    FROM pg_catalog.pg_statio_user_tables
    ORDER BY pg_total_relation_size(relid) DESC;
EOF
    
    # Database size
    psql "$SUPABASE_DB_URL" << EOF
    SELECT 
        current_database(),
        pg_size_pretty(pg_database_size(current_database()));
EOF
}

# Function to check table bloat
check_bloat() {
    echo "Checking table bloat..."
    
    psql "$SUPABASE_DB_URL" << EOF
    WITH constants AS (
        SELECT current_setting('block_size')::numeric AS bs, 23 AS hdr, 8 AS ma
    ),
    no_stats AS (
        SELECT table_schema, table_name, 
            n_live_tup::numeric as est_rows,
            pg_table_size(relid)::numeric as table_size
        FROM information_schema.columns
        JOIN pg_stat_user_tables as psut
           ON table_schema = psut.schemaname
           AND table_name = psut.relname
        LEFT OUTER JOIN pg_stats
        ON table_schema = pg_stats.schemaname
            AND table_name = pg_stats.tablename
            AND column_name = attname
        WHERE attname IS NULL
            AND table_schema NOT IN ('pg_catalog', 'information_schema')
        GROUP BY table_schema, table_name, relid, n_live_tup
    ),
    null_headers AS (
        SELECT
            hdr+1+(sum(case when null_frac <> 0 THEN 1 else 0 END)/8) as nullhdr,
            SUM((1-null_frac)*avg_width) as datawidth,
            MAX(null_frac) as maxfrac,
            table_schema,
            table_name,
            hdr, ma, bs
        FROM information_schema.columns
        LEFT OUTER JOIN pg_stats
        ON table_schema = pg_stats.schemaname
            AND table_name = pg_stats.tablename
            AND column_name = attname
        JOIN constants
        ON true
        WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
        GROUP BY table_schema, table_name, hdr, ma, bs
    ),
    data_headers AS (
        SELECT
            ma, bs, hdr, nullhdr, datawidth, maxfrac,
            (datawidth+(hdr+ma-(case when hdr%ma=0 THEN ma ELSE hdr%ma END)))::numeric AS datahdr,
            (maxfrac*(nullhdr+ma-(case when nullhdr%ma=0 THEN ma ELSE nullhdr%ma END)))::numeric AS nullhdr2
        FROM null_headers
    ),
    table_estimates AS (
        SELECT schemaname, tablename, bs,
            reltuples::numeric as est_rows, relpages * bs as table_bytes,
        CEIL((reltuples*
            (datahdr + nullhdr2 + 4 + ma -
                (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END)
                )/(bs-20))
        ) * bs AS expected_bytes,
        reltoastrelid
        FROM data_headers
        JOIN pg_class ON tablename = relname
        JOIN pg_namespace ON relnamespace = pg_namespace.oid
            AND schemaname = nspname
        WHERE pg_class.relkind = 'r'
    ),
    estimates_with_toast AS (
        SELECT schemaname, tablename,
            TRUE as has_toast,
            est_rows,
            table_bytes + ( coalesce(toast.relpages, 0) * bs ) as table_bytes,
            expected_bytes + ( ceil( coalesce(toast.reltuples, 0) / 4 ) * bs ) as expected_bytes
        FROM table_estimates LEFT OUTER JOIN pg_class as toast
            ON table_estimates.reltoastrelid = toast.oid
            AND toast.relkind = 't'
    ),
    table_estimates_plus AS (
        SELECT current_database() as db, schemaname, tablename, has_toast,
            est_rows,
            ROUND(table_bytes/(1024^2)::numeric,3) as table_mb,
            ROUND(expected_bytes/(1024^2)::numeric,3) as expected_mb,
            ROUND(table_bytes*100/expected_bytes - 100,2) as bloat_pct
        FROM estimates_with_toast
    )
    SELECT db, schemaname, tablename,
        CASE WHEN bloat_pct > 50 THEN '*' ELSE '' END as attention,
        ROUND(table_mb,2) as table_mb,
        ROUND(bloat_pct,2) as bloat_pct,
        est_rows
    FROM table_estimates_plus
    WHERE bloat_pct > 20
    ORDER BY bloat_pct DESC;
EOF
}

# Function to generate monitoring report
generate_report() {
    local report_file="$MONITOR_DIR/report_$(date '+%Y%m%d_%H%M%S').txt"
    
    {
        echo "Database Monitoring Report"
        echo "========================="
        echo "Environment: $ENV"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo
        
        echo "Health Check"
        echo "-----------"
        check_health
        echo
        
        echo "Performance Metrics"
        echo "------------------"
        check_performance
        echo
        
        echo "Storage Usage"
        echo "-------------"
        check_storage
        echo
        
        echo "Table Bloat"
        echo "-----------"
        check_bloat
        
    } > "$report_file"
    
    echo "Report generated: $report_file"
}

# Process commands
case "${2:-report}" in
    "health")
        check_health
        ;;
        
    "performance")
        check_performance
        ;;
        
    "storage")
        check_storage
        ;;
        
    "bloat")
        check_bloat
        ;;
        
    "report")
        generate_report
        ;;
        
    "watch")
        while true; do
            clear
            check_health
            echo -e "\nPress Ctrl+C to stop monitoring"
            sleep 5
        done
        ;;
        
    *)
        echo "Usage: $0 [environment] [health|performance|storage|bloat|report|watch]"
        exit 1
        ;;
esac

exit 0
