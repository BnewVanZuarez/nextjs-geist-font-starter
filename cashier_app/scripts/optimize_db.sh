#!/bin/bash

# Database optimization script
# Usage: ./optimize_db.sh [environment] [operation]
# Example: ./optimize_db.sh development indexes

# Set environment
ENV=${1:-development}
echo "Running database optimization in $ENV environment"

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

# Create optimization logs directory
OPT_DIR="../logs/optimization"
mkdir -p "$OPT_DIR"

# Function to log optimization operations
log_optimization() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$OPT_DIR/optimization.log"
}

# Function to optimize tables
optimize_tables() {
    echo "Optimizing tables..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Analyze all tables
    ANALYZE VERBOSE;
    
    -- Vacuum analyze tables with high dead tuple counts
    DO \$\$
    DECLARE
        tbl text;
    BEGIN
        FOR tbl IN
            SELECT schemaname || '.' || tablename
            FROM pg_stat_user_tables
            WHERE n_dead_tup > 10000
        LOOP
            EXECUTE 'VACUUM ANALYZE ' || tbl;
            RAISE NOTICE 'Vacuumed table: %', tbl;
        END LOOP;
    END;
    \$\$;
    
    -- Cluster tables based on their primary key
    DO \$\$
    DECLARE
        tbl text;
        idx text;
    BEGIN
        FOR tbl, idx IN
            SELECT
                schemaname || '.' || tablename,
                indexrelname
            FROM pg_stat_user_tables t
            JOIN pg_index i ON t.relid = i.indrelid
            WHERE i.indisprimary
        LOOP
            EXECUTE 'CLUSTER ' || tbl || ' USING ' || idx;
            RAISE NOTICE 'Clustered table % using index %', tbl, idx;
        END LOOP;
    END;
    \$\$;
EOF
    
    log_optimization "tables" "success" "Tables optimized"
    echo "Table optimization completed"
}

# Function to optimize indexes
optimize_indexes() {
    echo "Optimizing indexes..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Identify and remove unused indexes
    WITH unused_indexes AS (
        SELECT
            schemaname || '.' || tablename as table_name,
            indexrelname as index_name,
            pg_size_pretty(pg_relation_size(i.indexrelid)) as index_size,
            idx_scan as index_scans
        FROM pg_stat_user_indexes ui
        JOIN pg_index i ON ui.indexrelid = i.indexrelid
        WHERE NOT indisunique AND idx_scan < 50
        AND pg_relation_size(i.indexrelid) > 5 * 1024 * 1024
        AND NOT EXISTS (
            SELECT 1
            FROM pg_constraint c
            WHERE c.conindid = i.indexrelid
        )
    )
    SELECT * FROM unused_indexes;
    
    -- Create missing indexes for foreign keys
    DO \$\$
    DECLARE
        fk record;
    BEGIN
        FOR fk IN
            SELECT
                tc.table_schema,
                tc.table_name,
                kcu.column_name,
                ccu.table_schema AS foreign_table_schema,
                ccu.table_name AS foreign_table_name,
                ccu.column_name AS foreign_column_name
            FROM information_schema.table_constraints AS tc
            JOIN information_schema.key_column_usage AS kcu
                ON tc.constraint_name = kcu.constraint_name
                AND tc.table_schema = kcu.table_schema
            JOIN information_schema.constraint_column_usage AS ccu
                ON ccu.constraint_name = tc.constraint_name
                AND ccu.table_schema = tc.table_schema
            WHERE tc.constraint_type = 'FOREIGN KEY'
        LOOP
            -- Check if index exists
            IF NOT EXISTS (
                SELECT 1
                FROM pg_indexes
                WHERE schemaname = fk.table_schema
                AND tablename = fk.table_name
                AND indexdef LIKE '%' || fk.column_name || '%'
            ) THEN
                -- Create index
                EXECUTE format('CREATE INDEX ON %I.%I(%I)',
                    fk.table_schema,
                    fk.table_name,
                    fk.column_name
                );
                RAISE NOTICE 'Created index on %.%.%',
                    fk.table_schema,
                    fk.table_name,
                    fk.column_name;
            END IF;
        END LOOP;
    END;
    \$\$;
    
    -- Reindex bloated indexes
    DO \$\$
    DECLARE
        idx record;
    BEGIN
        FOR idx IN
            SELECT schemaname, tablename, indexrelname
            FROM pg_stat_user_indexes
            JOIN pg_index i ON indexrelid = i.indexrelid
            WHERE idx_scan > 0
            AND pg_relation_size(indexrelid) > 10 * 1024 * 1024
        LOOP
            EXECUTE format('REINDEX INDEX %I.%I',
                idx.schemaname,
                idx.indexrelname
            );
            RAISE NOTICE 'Reindexed %.%',
                idx.schemaname,
                idx.indexrelname;
        END LOOP;
    END;
    \$\$;
EOF
    
    log_optimization "indexes" "success" "Indexes optimized"
    echo "Index optimization completed"
}

# Function to optimize queries
optimize_queries() {
    echo "Optimizing query patterns..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Update table statistics
    DO \$\$
    DECLARE
        tbl text;
    BEGIN
        FOR tbl IN
            SELECT schemaname || '.' || tablename
            FROM pg_stat_user_tables
        LOOP
            EXECUTE 'ANALYZE VERBOSE ' || tbl;
        END LOOP;
    END;
    \$\$;
    
    -- Identify slow queries
    SELECT
        substring(query, 1, 100) as query_preview,
        round(total_time::numeric, 2) as total_time,
        calls,
        round(mean_time::numeric, 2) as mean_time,
        round((100 * total_time / sum(total_time) over())::numeric, 2) as percentage_cpu
    FROM pg_stat_statements
    WHERE total_time > 1000 -- queries taking more than 1 second
    ORDER BY total_time DESC
    LIMIT 10;
    
    -- Reset query statistics
    SELECT pg_stat_statements_reset();
EOF
    
    log_optimization "queries" "success" "Query patterns optimized"
    echo "Query optimization completed"
}

# Function to optimize configuration
optimize_config() {
    echo "Optimizing database configuration..."
    
    # Calculate recommended settings based on system resources
    local total_mem=$(free -b | awk '/^Mem:/{print $2}')
    local shared_buffers=$(( total_mem / 4 ))
    local effective_cache_size=$(( total_mem * 3 / 4 ))
    local work_mem=$(( total_mem / 4 / 100 )) # Assume max 100 concurrent connections
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Update configuration parameters
    ALTER SYSTEM SET shared_buffers = '${shared_buffers}B';
    ALTER SYSTEM SET effective_cache_size = '${effective_cache_size}B';
    ALTER SYSTEM SET work_mem = '${work_mem}B';
    ALTER SYSTEM SET maintenance_work_mem = '256MB';
    ALTER SYSTEM SET random_page_cost = 1.1;
    ALTER SYSTEM SET effective_io_concurrency = 200;
    ALTER SYSTEM SET default_statistics_target = 100;
    
    -- Autovacuum settings
    ALTER SYSTEM SET autovacuum_vacuum_scale_factor = 0.1;
    ALTER SYSTEM SET autovacuum_analyze_scale_factor = 0.05;
    ALTER SYSTEM SET autovacuum_vacuum_cost_delay = 2;
    
    -- WAL settings
    ALTER SYSTEM SET wal_buffers = '16MB';
    ALTER SYSTEM SET checkpoint_completion_target = 0.9;
    ALTER SYSTEM SET checkpoint_timeout = '15min';
    
    -- Connection settings
    ALTER SYSTEM SET max_connections = 100;
    ALTER SYSTEM SET idle_in_transaction_session_timeout = '1h';
    ALTER SYSTEM SET statement_timeout = '1h';
EOF
    
    log_optimization "config" "success" "Database configuration optimized"
    echo "Configuration optimization completed"
}

# Function to optimize storage
optimize_storage() {
    echo "Optimizing storage..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Identify bloated tables
    WITH bloat_info AS (
        SELECT
            schemaname, tablename,
            pg_total_relation_size(quote_ident(schemaname) || '.' || quote_ident(tablename))::bigint as total_size,
            n_dead_tup::bigint as dead_tuples,
            n_live_tup::bigint as live_tuples
        FROM pg_stat_user_tables
    )
    SELECT
        schemaname || '.' || tablename as table_name,
        pg_size_pretty(total_size) as total_size,
        dead_tuples,
        live_tuples,
        round(100 * dead_tuples::numeric / nullif(live_tuples, 0), 2) as bloat_ratio
    FROM bloat_info
    WHERE dead_tuples > 10000
    ORDER BY bloat_ratio DESC;
    
    -- Vacuum full bloated tables
    DO \$\$
    DECLARE
        tbl text;
    BEGIN
        FOR tbl IN
            SELECT schemaname || '.' || tablename
            FROM pg_stat_user_tables
            WHERE n_dead_tup > 10000
            AND n_dead_tup > n_live_tup * 0.2
        LOOP
            EXECUTE 'VACUUM FULL VERBOSE ' || tbl;
            RAISE NOTICE 'Vacuum full completed on table: %', tbl;
        END LOOP;
    END;
    \$\$;
EOF
    
    log_optimization "storage" "success" "Storage optimized"
    echo "Storage optimization completed"
}

# Function to generate optimization report
generate_report() {
    local report_file="$OPT_DIR/optimization_report_$(date '+%Y%m%d_%H%M%S').txt"
    
    {
        echo "Database Optimization Report"
        echo "==========================="
        echo "Environment: $ENV"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo
        
        echo "1. Table Optimization"
        echo "-------------------"
        optimize_tables
        echo
        
        echo "2. Index Optimization"
        echo "-------------------"
        optimize_indexes
        echo
        
        echo "3. Query Optimization"
        echo "-------------------"
        optimize_queries
        echo
        
        echo "4. Configuration Optimization"
        echo "---------------------------"
        optimize_config
        echo
        
        echo "5. Storage Optimization"
        echo "---------------------"
        optimize_storage
        
    } > "$report_file"
    
    echo "Report generated: $report_file"
}

# Process commands
case "${2:-all}" in
    "tables")
        optimize_tables
        ;;
        
    "indexes")
        optimize_indexes
        ;;
        
    "queries")
        optimize_queries
        ;;
        
    "config")
        optimize_config
        ;;
        
    "storage")
        optimize_storage
        ;;
        
    "all")
        generate_report
        ;;
        
    *)
        echo "Usage: $0 [environment] [tables|indexes|queries|config|storage|all]"
        exit 1
        ;;
esac

exit 0
