#!/bin/bash

# Database partitioning script
# Usage: ./partition_db.sh [environment] [operation]
# Example: ./partition_db.sh development create-partitions

# Set environment
ENV=${1:-development}
echo "Managing database partitions for $ENV environment"

# Load environment variables
if [ -f "../.env.$ENV" ]; then
    source "../.env.$ENV"
else
    echo "Error: Environment file .env.$ENV not found"
    exit 1
fi

# Create partition logs directory
PARTITION_DIR="../logs/partitions"
mkdir -p "$PARTITION_DIR"

# Function to log partition operations
log_partition() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$PARTITION_DIR/partitions.log"
}

# Function to create table partitions
create_partitions() {
    echo "Creating table partitions..."
    
    # Tables to partition and their strategies
    declare -A partition_configs=(
        ["transactions"]="RANGE created_at INTERVAL '1 month'"
        ["audit_log"]="RANGE created_at INTERVAL '1 month'"
        ["system_logs"]="RANGE created_at INTERVAL '1 week'"
    )
    
    for table in "${!partition_configs[@]}"; do
        local strategy=${partition_configs[$table]}
        echo "Setting up partitioning for $table using $strategy"
        
        # Create partitioned table
        psql "$SUPABASE_DB_URL" << EOF
        -- Create partition table
        CREATE TABLE IF NOT EXISTS ${table}_partitioned (
            LIKE ${table} INCLUDING ALL
        ) PARTITION BY ${strategy};
        
        -- Create partitions for the next 12 months
        DO \$\$
        DECLARE
            start_date DATE := DATE_TRUNC('month', CURRENT_DATE);
            end_date DATE := start_date + INTERVAL '12 months';
            current_date DATE := start_date;
            partition_name TEXT;
            partition_start TEXT;
            partition_end TEXT;
        BEGIN
            WHILE current_date < end_date LOOP
                partition_name := '${table}_' || TO_CHAR(current_date, 'YYYY_MM');
                partition_start := TO_CHAR(current_date, 'YYYY-MM-DD');
                partition_end := TO_CHAR(current_date + INTERVAL '1 month', 'YYYY-MM-DD');
                
                EXECUTE format(
                    'CREATE TABLE IF NOT EXISTS %I PARTITION OF ${table}_partitioned
                     FOR VALUES FROM (%L) TO (%L)',
                    partition_name, partition_start, partition_end
                );
                
                current_date := current_date + INTERVAL '1 month';
            END LOOP;
        END;
        \$\$;
        
        -- Move data to partitioned table
        INSERT INTO ${table}_partitioned
        SELECT * FROM ${table};
        
        -- Rename tables
        ALTER TABLE ${table} RENAME TO ${table}_old;
        ALTER TABLE ${table}_partitioned RENAME TO ${table};
        
        -- Create indexes on partitioned table
        DO \$\$
        DECLARE
            idx record;
        BEGIN
            FOR idx IN
                SELECT indexdef
                FROM pg_indexes
                WHERE tablename = '${table}_old'
                AND indexdef NOT LIKE '%PRIMARY KEY%'
            LOOP
                EXECUTE REPLACE(idx.indexdef, '${table}_old', '${table}');
            END LOOP;
        END;
        \$\$;
EOF
        
        log_partition "create" "success" "Created partitions for $table"
        echo "Partitions created for $table"
    done
}

# Function to manage partition maintenance
maintain_partitions() {
    echo "Maintaining partitions..."
    
    # Create future partitions
    psql "$SUPABASE_DB_URL" << EOF
    DO \$\$
    DECLARE
        table_record record;
        current_date DATE := CURRENT_DATE;
        future_date DATE := current_date + INTERVAL '3 months';
        partition_name TEXT;
        partition_start TEXT;
        partition_end TEXT;
    BEGIN
        FOR table_record IN
            SELECT tablename
            FROM pg_tables
            WHERE tablename IN ('transactions', 'audit_log', 'system_logs')
        LOOP
            WHILE current_date < future_date LOOP
                partition_name := table_record.tablename || '_' || TO_CHAR(current_date, 'YYYY_MM');
                partition_start := TO_CHAR(current_date, 'YYYY-MM-DD');
                partition_end := TO_CHAR(current_date + INTERVAL '1 month', 'YYYY-MM-DD');
                
                BEGIN
                    EXECUTE format(
                        'CREATE TABLE IF NOT EXISTS %I PARTITION OF %I
                         FOR VALUES FROM (%L) TO (%L)',
                        partition_name, table_record.tablename, partition_start, partition_end
                    );
                    RAISE NOTICE 'Created partition: %', partition_name;
                EXCEPTION WHEN duplicate_table THEN
                    RAISE NOTICE 'Partition already exists: %', partition_name;
                END;
                
                current_date := current_date + INTERVAL '1 month';
            END LOOP;
        END LOOP;
    END;
    \$\$;
EOF
    
    log_partition "maintain" "success" "Created future partitions"
    echo "Future partitions created"
}

# Function to analyze partition usage
analyze_partitions() {
    echo "Analyzing partition usage..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Get partition statistics
    SELECT
        parent.relname as table_name,
        child.relname as partition_name,
        pg_size_pretty(pg_relation_size(child.oid)) as partition_size,
        pg_stat_get_live_tuples(child.oid) as row_count,
        pg_stat_get_dead_tuples(child.oid) as dead_tuples,
        pg_stat_get_blocks_fetched(child.oid) - 
        pg_stat_get_blocks_hit(child.oid) as disk_reads,
        pg_stat_get_blocks_hit(child.oid) as buffer_hits
    FROM pg_inherits
    JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
    JOIN pg_class child ON pg_inherits.inhrelid = child.oid
    WHERE parent.relname IN ('transactions', 'audit_log', 'system_logs')
    ORDER BY parent.relname, child.relname;
    
    -- Get partition boundaries
    SELECT
        schemaname,
        tablename,
        pg_get_expr(partbound, partrelid) as partition_bound
    FROM pg_partitioned_table pt
    JOIN pg_class pc ON pt.partrelid = pc.oid
    JOIN pg_namespace pn ON pc.relnamespace = pn.oid
    WHERE tablename IN ('transactions', 'audit_log', 'system_logs');
EOF
}

# Function to cleanup old partitions
cleanup_partitions() {
    local retention_months=${1:-12}
    echo "Cleaning up partitions older than $retention_months months..."
    
    psql "$SUPABASE_DB_URL" << EOF
    DO \$\$
    DECLARE
        partition_record record;
        partition_date date;
        cutoff_date date := CURRENT_DATE - INTERVAL '$retention_months months';
    BEGIN
        FOR partition_record IN
            SELECT
                nmsp_child.nspname AS child_schema,
                child.relname AS child_table
            FROM pg_inherits
            JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
            JOIN pg_class child ON pg_inherits.inhrelid = child.oid
            JOIN pg_namespace nmsp_parent ON parent.relnamespace = nmsp_parent.oid
            JOIN pg_namespace nmsp_child ON child.relnamespace = nmsp_child.oid
            WHERE parent.relname IN ('transactions', 'audit_log', 'system_logs')
        LOOP
            -- Extract date from partition name (assumes format table_YYYY_MM)
            BEGIN
                partition_date := to_date(
                    substring(partition_record.child_table from '[0-9]{4}_[0-9]{2}$'),
                    'YYYY_MM'
                );
                
                IF partition_date < cutoff_date THEN
                    EXECUTE format(
                        'DROP TABLE IF EXISTS %I.%I',
                        partition_record.child_schema,
                        partition_record.child_table
                    );
                    RAISE NOTICE 'Dropped partition: %.%',
                        partition_record.child_schema,
                        partition_record.child_table;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                RAISE NOTICE 'Could not process partition: %.%',
                    partition_record.child_schema,
                    partition_record.child_table;
            END;
        END LOOP;
    END;
    \$\$;
EOF
    
    log_partition "cleanup" "success" "Cleaned up old partitions"
    echo "Old partitions cleaned up"
}

# Function to rebalance partitions
rebalance_partitions() {
    echo "Rebalancing partitions..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Analyze all partitions
    DO \$\$
    DECLARE
        partition_record record;
    BEGIN
        FOR partition_record IN
            SELECT
                nmsp_child.nspname AS child_schema,
                child.relname AS child_table
            FROM pg_inherits
            JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
            JOIN pg_class child ON pg_inherits.inhrelid = child.oid
            JOIN pg_namespace nmsp_parent ON parent.relnamespace = nmsp_parent.oid
            JOIN pg_namespace nmsp_child ON child.relnamespace = nmsp_child.oid
            WHERE parent.relname IN ('transactions', 'audit_log', 'system_logs')
        LOOP
            EXECUTE format('ANALYZE %I.%I',
                partition_record.child_schema,
                partition_record.child_table
            );
        END LOOP;
    END;
    \$\$;
    
    -- Vacuum analyze partitions
    DO \$\$
    DECLARE
        partition_record record;
    BEGIN
        FOR partition_record IN
            SELECT
                nmsp_child.nspname AS child_schema,
                child.relname AS child_table
            FROM pg_inherits
            JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
            JOIN pg_class child ON pg_inherits.inhrelid = child.oid
            JOIN pg_namespace nmsp_parent ON parent.relnamespace = nmsp_parent.oid
            JOIN pg_namespace nmsp_child ON child.relnamespace = nmsp_child.oid
            WHERE parent.relname IN ('transactions', 'audit_log', 'system_logs')
        LOOP
            EXECUTE format('VACUUM ANALYZE %I.%I',
                partition_record.child_schema,
                partition_record.child_table
            );
        END LOOP;
    END;
    \$\$;
EOF
    
    log_partition "rebalance" "success" "Rebalanced partitions"
    echo "Partitions rebalanced"
}

# Function to generate partition report
generate_report() {
    local report_file="$PARTITION_DIR/partition_report_$(date '+%Y%m%d_%H%M%S').md"
    
    {
        echo "# Database Partition Report"
        echo "Generated on: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Environment: $ENV"
        echo
        
        echo "## Partition Overview"
        echo
        analyze_partitions
        echo
        
        echo "## Partition Usage"
        echo
        psql "$SUPABASE_DB_URL" -c "
            SELECT
                parent.relname as table_name,
                COUNT(child.oid) as partition_count,
                pg_size_pretty(SUM(pg_relation_size(child.oid))) as total_size,
                SUM(pg_stat_get_live_tuples(child.oid)) as total_rows
            FROM pg_inherits
            JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
            JOIN pg_class child ON pg_inherits.inhrelid = child.oid
            WHERE parent.relname IN ('transactions', 'audit_log', 'system_logs')
            GROUP BY parent.relname;
        "
        
    } > "$report_file"
    
    log_partition "report" "success" "Generated partition report"
    echo "Report generated: $report_file"
}

# Process commands
case "${2:-status}" in
    "create")
        create_partitions
        ;;
        
    "maintain")
        maintain_partitions
        ;;
        
    "analyze")
        analyze_partitions
        ;;
        
    "cleanup")
        cleanup_partitions "${3:-12}"
        ;;
        
    "rebalance")
        rebalance_partitions
        ;;
        
    "report")
        generate_report
        ;;
        
    *)
        echo "Usage: $0 [environment] [create|maintain|analyze|cleanup|rebalance|report] [args]"
        exit 1
        ;;
esac

exit 0
