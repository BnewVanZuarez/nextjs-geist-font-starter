#!/bin/bash

# Database statistics script
# Usage: ./stats_db.sh [environment] [operation]
# Example: ./stats_db.sh development collect

# Set environment
ENV=${1:-development}
echo "Managing database statistics for $ENV environment"

# Load environment variables
if [ -f "../.env.$ENV" ]; then
    source "../.env.$ENV"
else
    echo "Error: Environment file .env.$ENV not found"
    exit 1
fi

# Create statistics directory
STATS_DIR="../logs/statistics"
mkdir -p "$STATS_DIR"

# Function to log statistics operations
log_stats() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$STATS_DIR/statistics.log"
}

# Function to collect general statistics
collect_stats() {
    echo "Collecting database statistics..."
    
    local stats_file="$STATS_DIR/stats_$(date '+%Y%m%d_%H%M%S').json"
    
    {
        echo "{"
        
        # Database size
        echo "\"database_size\": $(psql "$SUPABASE_DB_URL" -t -c "
            SELECT pg_database_size(current_database());
        "),"
        
        # Table sizes
        echo "\"table_sizes\": {"
        psql "$SUPABASE_DB_URL" -t -c "
            SELECT 
                json_object_agg(
                    tablename,
                    json_build_object(
                        'size', pg_relation_size(quote_ident(schemaname) || '.' || quote_ident(tablename)),
                        'total_size', pg_total_relation_size(quote_ident(schemaname) || '.' || quote_ident(tablename)),
                        'rows', n_live_tup
                    )
                )
            FROM pg_stat_user_tables;
        "
        echo "},"
        
        # Index statistics
        echo "\"index_stats\": {"
        psql "$SUPABASE_DB_URL" -t -c "
            SELECT 
                json_object_agg(
                    indexrelname,
                    json_build_object(
                        'table', relname,
                        'scans', idx_scan,
                        'tuples_read', idx_tup_read,
                        'tuples_fetched', idx_tup_fetch
                    )
                )
            FROM pg_stat_user_indexes;
        "
        echo "},"
        
        # Table statistics
        echo "\"table_stats\": {"
        psql "$SUPABASE_DB_URL" -t -c "
            SELECT 
                json_object_agg(
                    relname,
                    json_build_object(
                        'sequential_scans', seq_scan,
                        'sequential_tuples_read', seq_tup_read,
                        'index_scans', idx_scan,
                        'index_tuples_fetched', idx_tup_fetch,
                        'rows_inserted', n_tup_ins,
                        'rows_updated', n_tup_upd,
                        'rows_deleted', n_tup_del,
                        'rows_hot_updated', n_tup_hot_upd,
                        'live_rows', n_live_tup,
                        'dead_rows', n_dead_tup
                    )
                )
            FROM pg_stat_user_tables;
        "
        echo "},"
        
        # Buffer cache statistics
        echo "\"buffer_stats\": {"
        psql "$SUPABASE_DB_URL" -t -c "
            SELECT 
                json_object_agg(
                    relname,
                    json_build_object(
                        'heap_blks_read', heap_blks_read,
                        'heap_blks_hit', heap_blks_hit,
                        'idx_blks_read', idx_blks_read,
                        'idx_blks_hit', idx_blks_hit,
                        'toast_blks_read', toast_blks_read,
                        'toast_blks_hit', toast_blks_hit
                    )
                )
            FROM pg_statio_user_tables;
        "
        echo "},"
        
        # Query statistics
        echo "\"query_stats\": {"
        psql "$SUPABASE_DB_URL" -t -c "
            SELECT 
                json_object_agg(
                    md5(query),
                    json_build_object(
                        'calls', calls,
                        'total_time', total_time,
                        'min_time', min_time,
                        'max_time', max_time,
                        'mean_time', mean_time,
                        'rows', rows
                    )
                )
            FROM pg_stat_statements;
        "
        echo "},"
        
        # Connection statistics
        echo "\"connection_stats\": "
        psql "$SUPABASE_DB_URL" -t -c "
            SELECT json_build_object(
                'max_connections', setting::int
            ) FROM pg_settings WHERE name = 'max_connections';
        "
        
        echo "}"
        
    } > "$stats_file"
    
    log_stats "collect" "success" "Statistics collected to $stats_file"
    echo "Statistics collected to: $stats_file"
}

# Function to analyze trends
analyze_trends() {
    echo "Analyzing database trends..."
    
    local trends_file="$STATS_DIR/trends_$(date '+%Y%m%d_%H%M%S').json"
    
    {
        echo "{"
        
        # Growth trends
        echo "\"growth_trends\": {"
        
        # Database size growth
        echo "\"database_size\": ["
        for file in "$STATS_DIR"/stats_*.json; do
            if [ -f "$file" ]; then
                timestamp=$(echo "$file" | grep -o '[0-9]\{8\}_[0-9]\{6\}')
                size=$(jq '.database_size' "$file")
                echo "{ \"timestamp\": \"$timestamp\", \"size\": $size },"
            fi
        done
        echo "],"
        
        # Table growth
        echo "\"table_growth\": {"
        psql "$SUPABASE_DB_URL" -t -c "
            SELECT json_object_agg(
                tablename,
                (
                    SELECT json_agg(json_build_object(
                        'date', date_trunc('day', created_at),
                        'rows', count(*)
                    ))
                    FROM (
                        SELECT created_at
                        FROM ONLY quote_ident(tablename)
                        WHERE created_at >= NOW() - INTERVAL '30 days'
                        GROUP BY date_trunc('day', created_at)
                        ORDER BY date_trunc('day', created_at)
                    ) t
                )
            )
            FROM pg_tables
            WHERE schemaname = 'public'
            AND EXISTS (
                SELECT 1
                FROM information_schema.columns
                WHERE table_name = pg_tables.tablename
                AND column_name = 'created_at'
            );
        "
        echo "}"
        
        echo "},"
        
        # Performance trends
        echo "\"performance_trends\": {"
        
        # Query performance
        echo "\"query_performance\": ["
        for file in "$STATS_DIR"/stats_*.json; do
            if [ -f "$file" ]; then
                timestamp=$(echo "$file" | grep -o '[0-9]\{8\}_[0-9]\{6\}')
                jq -c '.query_stats | to_entries[] | select(.value.calls > 100) | {
                    timestamp: "'$timestamp'",
                    query_id: .key,
                    metrics: .value
                }' "$file"
            fi
        done
        echo "],"
        
        # Cache hit ratios
        echo "\"cache_hit_ratios\": ["
        for file in "$STATS_DIR"/stats_*.json; do
            if [ -f "$file" ]; then
                timestamp=$(echo "$file" | grep -o '[0-9]\{8\}_[0-9]\{6\}')
                jq -c '.buffer_stats | to_entries[] | {
                    timestamp: "'$timestamp'",
                    table: .key,
                    ratio: ((.value.heap_blks_hit + .value.idx_blks_hit) * 100.0 / 
                           (.value.heap_blks_hit + .value.idx_blks_hit + 
                            .value.heap_blks_read + .value.idx_blks_read))
                }' "$file"
            fi
        done
        echo "]"
        
        echo "}"
        
        echo "}"
        
    } > "$trends_file"
    
    log_stats "trends" "success" "Trends analyzed to $trends_file"
    echo "Trends analyzed to: $trends_file"
}

# Function to generate statistics report
generate_report() {
    local report_file="$STATS_DIR/stats_report_$(date '+%Y%m%d_%H%M%S').md"
    
    {
        echo "# Database Statistics Report"
        echo "Generated on: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Environment: $ENV"
        echo
        
        echo "## Database Overview"
        echo
        psql "$SUPABASE_DB_URL" -c "
            SELECT
                pg_size_pretty(pg_database_size(current_database())) as database_size,
                (SELECT count(*) FROM pg_stat_activity) as active_connections,
                (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') as max_connections,
                (SELECT count(*) FROM pg_stat_user_tables) as table_count,
                (SELECT count(*) FROM pg_stat_user_indexes) as index_count;
        "
        echo
        
        echo "## Table Statistics"
        echo
        echo "| Table | Size | Rows | Scans | Updates | Cache Hit Ratio |"
        echo "|-------|------|------|--------|----------|----------------|"
        psql "$SUPABASE_DB_URL" -t -c "
            SELECT format(
                '| %s | %s | %s | %s | %s | %.2f%% |',
                relname,
                pg_size_pretty(pg_relation_size(quote_ident(schemaname) || '.' || quote_ident(relname))),
                n_live_tup,
                seq_scan + idx_scan,
                n_tup_upd + n_tup_del + n_tup_ins,
                CASE WHEN heap_blks_hit + heap_blks_read = 0 THEN 0
                     ELSE heap_blks_hit * 100.0 / (heap_blks_hit + heap_blks_read)
                END
            )
            FROM pg_stat_user_tables t
            JOIN pg_statio_user_tables st ON t.relid = st.relid
            ORDER BY n_live_tup DESC;
        "
        echo
        
        echo "## Query Statistics"
        echo
        echo "| Query Pattern | Calls | Total Time | Avg Time | Rows |"
        echo "|---------------|--------|------------|-----------|------|"
        psql "$SUPABASE_DB_URL" -t -c "
            SELECT format(
                '| %s | %s | %.2f ms | %.2f ms | %s |',
                substring(query, 1, 50),
                calls,
                total_time,
                mean_time,
                rows
            )
            FROM pg_stat_statements
            ORDER BY total_time DESC
            LIMIT 10;
        "
        echo
        
        echo "## Index Usage"
        echo
        echo "| Index | Table | Scans | Rows Read | Rows Fetched |"
        echo "|-------|-------|--------|------------|--------------|"
        psql "$SUPABASE_DB_URL" -t -c "
            SELECT format(
                '| %s | %s | %s | %s | %s |',
                indexrelname,
                relname,
                idx_scan,
                idx_tup_read,
                idx_tup_fetch
            )
            FROM pg_stat_user_indexes
            ORDER BY idx_scan DESC
            LIMIT 10;
        "
        
    } > "$report_file"
    
    log_stats "report" "success" "Report generated to $report_file"
    echo "Report generated to: $report_file"
}

# Process commands
case "${2:-collect}" in
    "collect")
        collect_stats
        ;;
        
    "trends")
        analyze_trends
        ;;
        
    "report")
        generate_report
        ;;
        
    *)
        echo "Usage: $0 [environment] [collect|trends|report]"
        exit 1
        ;;
esac

exit 0
