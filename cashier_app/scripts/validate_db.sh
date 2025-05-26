#!/bin/bash

# Database validation script
# Usage: ./validate_db.sh [environment] [operation]
# Example: ./validate_db.sh development schema

# Set environment
ENV=${1:-development}
echo "Validating database for $ENV environment"

# Load environment variables
if [ -f "../.env.$ENV" ]; then
    source "../.env.$ENV"
else
    echo "Error: Environment file .env.$ENV not found"
    exit 1
fi

# Create validation logs directory
VALIDATE_DIR="../logs/validation"
mkdir -p "$VALIDATE_DIR"

# Function to log validation operations
log_validation() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$VALIDATE_DIR/validation.log"
}

# Function to validate schema
validate_schema() {
    echo "Validating database schema..."
    local issues=0
    
    # Check primary keys
    echo "Checking primary keys..."
    local tables_without_pk=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT table_name
        FROM information_schema.tables t
        WHERE table_schema = 'public'
        AND table_type = 'BASE TABLE'
        AND NOT EXISTS (
            SELECT 1
            FROM information_schema.table_constraints tc
            WHERE tc.table_name = t.table_name
            AND tc.table_schema = t.table_schema
            AND tc.constraint_type = 'PRIMARY KEY'
        );
    ")
    
    if [ ! -z "$tables_without_pk" ]; then
        echo "Warning: Tables without primary keys:"
        echo "$tables_without_pk"
        ((issues++))
    fi
    
    # Check foreign key constraints
    echo "Checking foreign key constraints..."
    local invalid_fks=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT
            tc.table_name,
            kcu.column_name,
            ccu.table_name AS foreign_table_name,
            ccu.column_name AS foreign_column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
            ON tc.constraint_name = kcu.constraint_name
        JOIN information_schema.constraint_column_usage ccu
            ON ccu.constraint_name = tc.constraint_name
        WHERE tc.constraint_type = 'FOREIGN KEY'
        AND NOT EXISTS (
            SELECT 1
            FROM information_schema.table_constraints tc2
            WHERE tc2.table_name = ccu.table_name
            AND tc2.constraint_type = 'PRIMARY KEY'
            AND tc2.table_schema = 'public'
        );
    ")
    
    if [ ! -z "$invalid_fks" ]; then
        echo "Error: Invalid foreign key constraints found:"
        echo "$invalid_fks"
        ((issues++))
    fi
    
    # Check for nullable foreign keys
    echo "Checking nullable foreign keys..."
    local nullable_fks=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT
            tc.table_name,
            kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
            ON tc.constraint_name = kcu.constraint_name
        JOIN information_schema.columns c
            ON c.table_name = tc.table_name
            AND c.column_name = kcu.column_name
        WHERE tc.constraint_type = 'FOREIGN KEY'
        AND c.is_nullable = 'YES';
    ")
    
    if [ ! -z "$nullable_fks" ]; then
        echo "Warning: Nullable foreign keys found:"
        echo "$nullable_fks"
        ((issues++))
    fi
    
    # Check index coverage
    echo "Checking index coverage..."
    local unindexed_fks=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT
            tc.table_name,
            kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
            ON tc.constraint_name = kcu.constraint_name
        WHERE tc.constraint_type = 'FOREIGN KEY'
        AND NOT EXISTS (
            SELECT 1
            FROM pg_indexes pi
            WHERE pi.tablename = tc.table_name
            AND pi.indexdef LIKE '%' || kcu.column_name || '%'
        );
    ")
    
    if [ ! -z "$unindexed_fks" ]; then
        echo "Warning: Foreign keys without indexes:"
        echo "$unindexed_fks"
        ((issues++))
    fi
    
    return $issues
}

# Function to validate data integrity
validate_data() {
    echo "Validating data integrity..."
    local issues=0
    
    # Check orphaned records
    echo "Checking for orphaned records..."
    psql "$SUPABASE_DB_URL" -t -c "
        SELECT
            tc.table_name,
            kcu.column_name,
            ccu.table_name AS foreign_table_name,
            COUNT(*) as orphaned_count
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
            ON tc.constraint_name = kcu.constraint_name
        JOIN information_schema.constraint_column_usage ccu
            ON ccu.constraint_name = tc.constraint_name
        WHERE tc.constraint_type = 'FOREIGN KEY'
        AND EXISTS (
            SELECT 1
            FROM information_schema.tables t
            WHERE t.table_name = tc.table_name
            AND t.table_schema = 'public'
        )
        GROUP BY tc.table_name, kcu.column_name, ccu.table_name
        HAVING COUNT(*) > 0;
    " | while read -r line; do
        if [ ! -z "$line" ]; then
            echo "Warning: Found orphaned records: $line"
            ((issues++))
        fi
    done
    
    # Check for duplicate records
    echo "Checking for duplicate records..."
    psql "$SUPABASE_DB_URL" -t -c "
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public';
    " | while read -r table; do
        if [ ! -z "$table" ]; then
            table=$(echo "$table" | xargs)
            
            # Get unique constraint columns
            local unique_cols=$(psql "$SUPABASE_DB_URL" -t -c "
                SELECT array_to_string(array_agg(column_name), ',')
                FROM information_schema.table_constraints tc
                JOIN information_schema.constraint_column_usage ccu
                    ON ccu.constraint_name = tc.constraint_name
                WHERE tc.table_name = '$table'
                AND tc.constraint_type = 'UNIQUE';
            ")
            
            if [ ! -z "$unique_cols" ]; then
                local dupes=$(psql "$SUPABASE_DB_URL" -t -c "
                    SELECT COUNT(*)
                    FROM (
                        SELECT $unique_cols
                        FROM $table
                        GROUP BY $unique_cols
                        HAVING COUNT(*) > 1
                    ) t;
                ")
                
                if [ "$dupes" -gt 0 ]; then
                    echo "Warning: Found $dupes duplicate record(s) in $table"
                    ((issues++))
                fi
            fi
        fi
    done
    
    # Check for invalid dates
    echo "Checking for invalid dates..."
    psql "$SUPABASE_DB_URL" -t -c "
        SELECT
            table_name,
            column_name
        FROM information_schema.columns
        WHERE data_type IN ('date', 'timestamp', 'timestamptz')
        AND table_schema = 'public';
    " | while read -r line; do
        if [ ! -z "$line" ]; then
            IFS='|' read -r table col <<< "$line"
            table=$(echo "$table" | xargs)
            col=$(echo "$col" | xargs)
            
            local invalid_dates=$(psql "$SUPABASE_DB_URL" -t -c "
                SELECT COUNT(*)
                FROM $table
                WHERE $col IS NOT NULL
                AND $col > CURRENT_TIMESTAMP + INTERVAL '100 years'
                OR $col < TIMESTAMP '1900-01-01';
            ")
            
            if [ "$invalid_dates" -gt 0 ]; then
                echo "Warning: Found $invalid_dates invalid date(s) in $table.$col"
                ((issues++))
            fi
        fi
    done
    
    return $issues
}

# Function to validate constraints
validate_constraints() {
    echo "Validating database constraints..."
    local issues=0
    
    # Check constraint definitions
    echo "Checking constraint definitions..."
    local invalid_constraints=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT
            conname as constraint_name,
            contype as constraint_type,
            relname as table_name
        FROM pg_constraint c
        JOIN pg_class r ON r.oid = c.conrelid
        WHERE NOT convalidated;
    ")
    
    if [ ! -z "$invalid_constraints" ]; then
        echo "Warning: Invalid constraints found:"
        echo "$invalid_constraints"
        ((issues++))
    fi
    
    # Check check constraints
    echo "Checking check constraints..."
    local violated_checks=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT
            tc.table_name,
            tc.constraint_name
        FROM information_schema.table_constraints tc
        WHERE tc.constraint_type = 'CHECK'
        AND EXISTS (
            SELECT 1
            FROM information_schema.check_constraints cc
            WHERE cc.constraint_name = tc.constraint_name
            AND NOT cc.is_deferrable = 'NO'
        );
    ")
    
    if [ ! -z "$violated_checks" ]; then
        echo "Warning: Potentially violated check constraints:"
        echo "$violated_checks"
        ((issues++))
    fi
    
    return $issues
}

# Function to validate indexes
validate_indexes() {
    echo "Validating database indexes..."
    local issues=0
    
    # Check for unused indexes
    echo "Checking for unused indexes..."
    local unused_indexes=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT
            schemaname || '.' || tablename as table,
            indexname as index,
            idx_scan as scans
        FROM pg_stat_user_indexes
        WHERE idx_scan = 0
        AND NOT EXISTS (
            SELECT 1
            FROM pg_constraint c
            WHERE c.conname = indexname
        );
    ")
    
    if [ ! -z "$unused_indexes" ]; then
        echo "Warning: Unused indexes found:"
        echo "$unused_indexes"
        ((issues++))
    fi
    
    # Check for duplicate indexes
    echo "Checking for duplicate indexes..."
    local duplicate_indexes=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT
            array_agg(indexname) as indexes,
            tablename,
            indexdef
        FROM pg_indexes
        WHERE schemaname = 'public'
        GROUP BY tablename, indexdef
        HAVING COUNT(*) > 1;
    ")
    
    if [ ! -z "$duplicate_indexes" ]; then
        echo "Warning: Duplicate indexes found:"
        echo "$duplicate_indexes"
        ((issues++))
    fi
    
    return $issues
}

# Function to generate validation report
generate_report() {
    local report_file="$VALIDATE_DIR/validation_report_$(date '+%Y%m%d_%H%M%S').md"
    
    {
        echo "# Database Validation Report"
        echo "Generated on: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Environment: $ENV"
        echo
        
        echo "## Schema Validation"
        echo
        validate_schema
        echo
        
        echo "## Data Integrity Validation"
        echo
        validate_data
        echo
        
        echo "## Constraint Validation"
        echo
        validate_constraints
        echo
        
        echo "## Index Validation"
        echo
        validate_indexes
        
    } > "$report_file"
    
    log_validation "report" "success" "Report generated to $report_file"
    echo "Report generated: $report_file"
}

# Process commands
case "${2:-all}" in
    "schema")
        validate_schema
        ;;
        
    "data")
        validate_data
        ;;
        
    "constraints")
        validate_constraints
        ;;
        
    "indexes")
        validate_indexes
        ;;
        
    "all")
        generate_report
        ;;
        
    *)
        echo "Usage: $0 [environment] [schema|data|constraints|indexes|all]"
        exit 1
        ;;
esac

exit 0
