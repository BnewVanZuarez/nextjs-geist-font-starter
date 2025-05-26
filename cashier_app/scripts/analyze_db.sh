#!/bin/bash

# Database analytics script
# Usage: ./analyze_db.sh [environment] [operation]
# Example: ./analyze_db.sh development usage

# Set environment
ENV=${1:-development}
echo "Running database analytics in $ENV environment"

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

# Create analytics directory
ANALYTICS_DIR="../logs/analytics"
mkdir -p "$ANALYTICS_DIR"

# Function to log analytics operations
log_analytics() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$ANALYTICS_DIR/analytics.log"
}

# Function to analyze table usage
analyze_usage() {
    echo "Analyzing table usage patterns..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Table sizes and row counts
    SELECT
        relname as table_name,
        pg_size_pretty(pg_total_relation_size(relid)) as total_size,
        pg_size_pretty(pg_relation_size(relid)) as table_size,
        pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) as index_size,
        n_live_tup as row_count
    FROM pg_stat_user_tables
    ORDER BY pg_total_relation_size(relid) DESC;
    
    -- Table access patterns
    SELECT
        relname as table_name,
        seq_scan as sequential_scans,
        idx_scan as index_scans,
        n_tup_ins as inserts,
        n_tup_upd as updates,
        n_tup_del as deletes,
        n_live_tup as live_rows,
        n_dead_tup as dead_rows
    FROM pg_stat_user_tables
    ORDER BY coalesce(seq_scan, 0) + coalesce(idx_scan, 0) DESC;
    
    -- Index usage
    SELECT
        schemaname,
        tablename,
        indexname,
        idx_scan as number_of_scans,
        idx_tup_read as tuples_read,
        idx_tup_fetch as tuples_fetched
    FROM pg_stat_user_indexes
    ORDER BY idx_scan DESC;
EOF
}

# Function to analyze query performance
analyze_queries() {
    echo "Analyzing query performance..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Slow queries
    SELECT
        substring(query, 1, 100) as query_preview,
        round(total_time::numeric, 2) as total_time,
        calls,
        round(mean_time::numeric, 2) as mean_time,
        round((100 * total_time / sum(total_time) over())::numeric, 2) as percentage
    FROM pg_stat_statements
    ORDER BY total_time DESC
    LIMIT 10;
    
    -- Most frequent queries
    SELECT
        substring(query, 1, 100) as query_preview,
        calls,
        round(mean_time::numeric, 2) as mean_time,
        round(total_time::numeric, 2) as total_time
    FROM pg_stat_statements
    ORDER BY calls DESC
    LIMIT 10;
    
    -- Cache hit ratios
    SELECT
        'index hit rate' as name,
        round(100 * sum(idx_blks_hit) / nullif(sum(idx_blks_hit + idx_blks_read), 0), 2) as ratio
    FROM pg_statio_user_indexes
    UNION ALL
    SELECT
        'table hit rate' as name,
        round(100 * sum(heap_blks_hit) / nullif(sum(heap_blks_hit + heap_blks_read), 0), 2) as ratio
    FROM pg_statio_user_tables;
EOF
}

# Function to analyze data patterns
analyze_data() {
    echo "Analyzing data patterns..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Transaction patterns by hour
    SELECT
        EXTRACT(HOUR FROM created_at) as hour,
        COUNT(*) as transaction_count,
        ROUND(AVG(total)::numeric, 2) as avg_amount
    FROM transactions
    WHERE created_at > NOW() - INTERVAL '30 days'
    GROUP BY hour
    ORDER BY hour;
    
    -- Product sales analysis
    SELECT
        p.name as product_name,
        COUNT(*) as sale_count,
        SUM(ti.quantity) as total_quantity,
        ROUND(AVG(ti.price)::numeric, 2) as avg_price,
        ROUND(SUM(ti.subtotal)::numeric, 2) as total_revenue
    FROM transactions_items ti
    JOIN products p ON ti.product_id = p.id
    GROUP BY p.name
    ORDER BY total_revenue DESC
    LIMIT 10;
    
    -- Customer segments
    SELECT
        CASE
            WHEN total_spent >= 1000 THEN 'High Value'
            WHEN total_spent >= 500 THEN 'Medium Value'
            ELSE 'Low Value'
        END as customer_segment,
        COUNT(*) as customer_count,
        ROUND(AVG(total_spent)::numeric, 2) as avg_spent
    FROM customers
    GROUP BY customer_segment
    ORDER BY avg_spent DESC;
EOF
}

# Function to analyze growth trends
analyze_growth() {
    echo "Analyzing growth trends..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Monthly transaction growth
    SELECT
        DATE_TRUNC('month', created_at) as month,
        COUNT(*) as transaction_count,
        ROUND(SUM(total)::numeric, 2) as total_revenue,
        COUNT(DISTINCT customer_id) as unique_customers
    FROM transactions
    WHERE created_at > NOW() - INTERVAL '12 months'
    GROUP BY month
    ORDER BY month;
    
    -- Store growth
    SELECT
        DATE_TRUNC('month', created_at) as month,
        COUNT(*) as new_stores,
        COUNT(*) FILTER (WHERE is_active) as active_stores
    FROM stores
    WHERE created_at > NOW() - INTERVAL '12 months'
    GROUP BY month
    ORDER BY month;
    
    -- User acquisition
    SELECT
        DATE_TRUNC('month', created_at) as month,
        COUNT(*) as new_users,
        COUNT(*) FILTER (WHERE is_active) as active_users
    FROM users
    WHERE created_at > NOW() - INTERVAL '12 months'
    GROUP BY month
    ORDER BY month;
EOF
}

# Function to analyze performance metrics
analyze_performance() {
    echo "Analyzing performance metrics..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Table bloat
    WITH constants AS (
        SELECT current_setting('block_size')::numeric AS bs, 23 AS hdr, 8 AS ma
    ),
    bloat_info AS (
        SELECT
            schemaname, tablename, bs*tblpages AS real_size,
            (tblpages-est_tblpages)*bs AS extra_size,
            CASE WHEN tblpages - est_tblpages > 0
                THEN 100 * (tblpages - est_tblpages)/tblpages::float
                ELSE 0
            END AS bloat_ratio
        FROM (
            SELECT ceil(reltuples/((bs-page_hdr)/tpl_size)) + ceil(toasttuples/4) AS est_tblpages,
                tblpages, bs, tpl_size, schemaname, tablename
            FROM (
                SELECT
                    ( (heappages + toastpages) * bs) AS real_size,
                    schemaname,
                    tablename,
                    bs,
                    tblpages,
                    heappages,
                    toastpages,
                    reltuples,
                    toasttuples,
                    bs - ( (heappages + toastpages) * bs) AS extra_size,
                    (heappages + toastpages) AS total_pages
                FROM (
                    SELECT
                        tbl.schemaname,
                        tbl.tablename,
                        tbl.heappages,
                        tbl.toastpages,
                        tbl.reltuples,
                        tbl.toasttuples,
                        tbl.bs,
                        tbl.tblpages,
                        tbl.bs - page_hdr AS tpl_size
                    FROM (
                        SELECT
                            n.nspname AS schemaname,
                            c.relname AS tablename,
                            c.reltuples,
                            c.relpages AS heappages,
                            coalesce(toast.relpages, 0) AS toastpages,
                            coalesce(toast.reltuples, 0) AS toasttuples,
                            coalesce(substring(array_to_string(c.reloptions, ' ') FROM 'fillfactor=([0-9]+)')::smallint, 100) AS fillfactor,
                            current_setting('block_size')::numeric AS bs,
                            c.relpages AS tblpages,
                            24 AS page_hdr
                        FROM pg_class c
                        JOIN pg_namespace n ON n.oid = c.relnamespace
                        LEFT JOIN pg_class toast ON c.reltoastrelid = toast.oid
                        WHERE c.relkind = 'r'
                    ) AS tbl
                ) AS tab
            ) AS tab2
        ) AS tab3
    )
    SELECT
        schemaname,
        tablename,
        pg_size_pretty(real_size) as actual_size,
        pg_size_pretty(extra_size) as bloat_size,
        round(bloat_ratio::numeric, 2) as bloat_percentage
    FROM bloat_info
    WHERE bloat_ratio >= 30
    ORDER BY bloat_ratio DESC;
    
    -- Buffer cache hit ratio
    SELECT
        'buffer cache hit ratio' as name,
        round(100 * blks_hit::numeric / (blks_hit + blks_read), 2) as ratio
    FROM pg_stat_database
    WHERE datname = current_database();
    
    -- Index efficiency
    SELECT
        schemaname,
        tablename,
        indexname,
        idx_scan,
        idx_tup_read,
        idx_tup_fetch,
        round(100.0 * idx_scan / nullif(seq_scan + idx_scan, 0), 2) as index_use_ratio
    FROM pg_stat_user_indexes
    JOIN pg_stat_user_tables USING (relid)
    WHERE seq_scan + idx_scan > 0
    ORDER BY index_use_ratio ASC;
EOF
}

# Function to generate analytics report
generate_report() {
    local report_file="$ANALYTICS_DIR/analytics_report_$(date '+%Y%m%d_%H%M%S').txt"
    
    {
        echo "Database Analytics Report"
        echo "======================="
        echo "Environment: $ENV"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo
        
        echo "1. Table Usage Analysis"
        echo "---------------------"
        analyze_usage
        echo
        
        echo "2. Query Performance Analysis"
        echo "---------------------------"
        analyze_queries
        echo
        
        echo "3. Data Pattern Analysis"
        echo "----------------------"
        analyze_data
        echo
        
        echo "4. Growth Trend Analysis"
        echo "----------------------"
        analyze_growth
        echo
        
        echo "5. Performance Metrics"
        echo "-------------------"
        analyze_performance
        
    } > "$report_file"
    
    echo "Report generated: $report_file"
}

# Process commands
case "${2:-report}" in
    "usage")
        analyze_usage
        ;;
        
    "queries")
        analyze_queries
        ;;
        
    "data")
        analyze_data
        ;;
        
    "growth")
        analyze_growth
        ;;
        
    "performance")
        analyze_performance
        ;;
        
    "report")
        generate_report
        ;;
        
    *)
        echo "Usage: $0 [environment] [usage|queries|data|growth|performance|report]"
        exit 1
        ;;
esac

exit 0
