#!/bin/bash

# Database synchronization script
# Usage: ./sync_db.sh [source_env] [target_env] [operation]
# Example: ./sync_db.sh development staging compare

# Set environments
SOURCE_ENV=${1:-development}
TARGET_ENV=${2:-staging}
echo "Managing database synchronization from $SOURCE_ENV to $TARGET_ENV"

# Load environment variables
if [ -f "../.env.$SOURCE_ENV" ]; then
    source "../.env.$SOURCE_ENV"
    SOURCE_DB_URL="$SUPABASE_DB_URL"
else
    echo "Error: Source environment file .env.$SOURCE_ENV not found"
    exit 1
fi

if [ -f "../.env.$TARGET_ENV" ]; then
    source "../.env.$TARGET_ENV"
    TARGET_DB_URL="$SUPABASE_DB_URL"
else
    echo "Error: Target environment file .env.$TARGET_ENV not found"
    exit 1
fi

# Create sync directory
SYNC_DIR="../logs/sync"
mkdir -p "$SYNC_DIR"

# Function to log sync operations
log_sync() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $SOURCE_ENV -> $TARGET_ENV - $operation: $status - $message" >> "$SYNC_DIR/sync.log"
}

# Function to compare schemas
compare_schemas() {
    echo "Comparing schemas between $SOURCE_ENV and $TARGET_ENV..."
    
    local diff_file="$SYNC_DIR/schema_diff_$(date '+%Y%m%d_%H%M%S').sql"
    
    {
        echo "-- Schema Comparison Report"
        echo "-- Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "-- Source: $SOURCE_ENV"
        echo "-- Target: $TARGET_ENV"
        echo
        
        # Compare tables
        echo "-- Table Differences"
        echo
        
        # Get source tables
        local source_tables=$(psql "$SOURCE_DB_URL" -t -c "
            SELECT tablename 
            FROM pg_tables 
            WHERE schemaname = 'public'
            ORDER BY tablename;
        ")
        
        # Get target tables
        local target_tables=$(psql "$TARGET_DB_URL" -t -c "
            SELECT tablename 
            FROM pg_tables 
            WHERE schemaname = 'public'
            ORDER BY tablename;
        ")
        
        # Compare table structures
        for table in $source_tables; do
            table=$(echo "$table" | xargs)
            
            # Check if table exists in target
            if echo "$target_tables" | grep -q "^$table$"; then
                # Compare table structures
                local source_structure=$(psql "$SOURCE_DB_URL" -c "\d+ $table")
                local target_structure=$(psql "$TARGET_DB_URL" -c "\d+ $table")
                
                if [ "$source_structure" != "$target_structure" ]; then
                    echo "-- Table $table has different structure"
                    echo
                    
                    # Generate ALTER TABLE statements
                    psql "$SOURCE_DB_URL" -t -c "
                        SELECT 'ALTER TABLE $table ' || 
                        CASE 
                            WHEN a.attnotnull THEN 'ALTER COLUMN ' || a.attname || ' SET NOT NULL'
                            ELSE 'ALTER COLUMN ' || a.attname || ' DROP NOT NULL'
                        END || ';'
                        FROM pg_attribute a
                        JOIN pg_class c ON a.attrelid = c.oid
                        WHERE c.relname = '$table'
                        AND a.attnum > 0
                        AND NOT a.attisdropped;
                    "
                    echo
                fi
            else
                echo "-- Table $table does not exist in target"
                echo
                
                # Generate CREATE TABLE statement
                pg_dump -t "$table" --schema-only "$SOURCE_DB_URL"
                echo
            fi
        done
        
        # Check for tables in target that don't exist in source
        for table in $target_tables; do
            table=$(echo "$table" | xargs)
            if ! echo "$source_tables" | grep -q "^$table$"; then
                echo "-- Table $table exists in target but not in source"
                echo "DROP TABLE IF EXISTS $table CASCADE;"
                echo
            fi
        done
        
        # Compare indexes
        echo "-- Index Differences"
        echo
        
        psql "$SOURCE_DB_URL" -t -c "
            SELECT 
                schemaname || '.' || tablename as table_name,
                indexname,
                indexdef
            FROM pg_indexes
            WHERE schemaname = 'public'
            ORDER BY tablename, indexname;
        " | while read -r line; do
            if [ ! -z "$line" ]; then
                local table_name=$(echo "$line" | cut -d'|' -f1)
                local index_name=$(echo "$line" | cut -d'|' -f2)
                local index_def=$(echo "$line" | cut -d'|' -f3)
                
                # Check if index exists in target
                if ! psql "$TARGET_DB_URL" -t -c "
                    SELECT 1 
                    FROM pg_indexes 
                    WHERE schemaname = 'public' 
                    AND indexname = '$index_name';
                " | grep -q "1"; then
                    echo "-- Index $index_name does not exist in target"
                    echo "$index_def;"
                    echo
                fi
            fi
        done
        
        # Compare constraints
        echo "-- Constraint Differences"
        echo
        
        psql "$SOURCE_DB_URL" -t -c "
            SELECT 
                conname,
                pg_get_constraintdef(oid)
            FROM pg_constraint
            WHERE connamespace = 'public'::regnamespace
            ORDER BY conname;
        " | while read -r line; do
            if [ ! -z "$line" ]; then
                local const_name=$(echo "$line" | cut -d'|' -f1)
                local const_def=$(echo "$line" | cut -d'|' -f2)
                
                # Check if constraint exists in target
                if ! psql "$TARGET_DB_URL" -t -c "
                    SELECT 1 
                    FROM pg_constraint 
                    WHERE conname = '$const_name';
                " | grep -q "1"; then
                    echo "-- Constraint $const_name does not exist in target"
                    echo "ALTER TABLE ${const_def%)*}) ADD CONSTRAINT $const_name ${const_def#*(};"
                    echo
                fi
            fi
        done
        
        # Compare functions
        echo "-- Function Differences"
        echo
        
        psql "$SOURCE_DB_URL" -t -c "
            SELECT 
                proname,
                pg_get_functiondef(oid)
            FROM pg_proc
            WHERE pronamespace = 'public'::regnamespace
            ORDER BY proname;
        " | while read -r line; do
            if [ ! -z "$line" ]; then
                local func_name=$(echo "$line" | cut -d'|' -f1)
                local func_def=$(echo "$line" | cut -d'|' -f2)
                
                # Check if function exists in target
                if ! psql "$TARGET_DB_URL" -t -c "
                    SELECT 1 
                    FROM pg_proc 
                    WHERE proname = '$func_name';
                " | grep -q "1"; then
                    echo "-- Function $func_name does not exist in target"
                    echo "$func_def"
                    echo
                fi
            fi
        done
        
    } > "$diff_file"
    
    log_sync "compare" "success" "Generated schema comparison report"
    echo "Schema comparison report generated: $diff_file"
}

# Function to sync schema changes
sync_schema() {
    echo "Syncing schema changes..."
    
    local diff_file=$1
    if [ ! -f "$diff_file" ]; then
        echo "Error: Diff file not found: $diff_file"
        return 1
    fi
    
    # Apply schema changes
    psql "$TARGET_DB_URL" -f "$diff_file"
    
    log_sync "sync" "success" "Applied schema changes from $diff_file"
    echo "Schema changes applied"
}

# Function to verify sync
verify_sync() {
    echo "Verifying synchronization..."
    
    local verify_file="$SYNC_DIR/verify_$(date '+%Y%m%d_%H%M%S').log"
    
    {
        echo "Verification Report"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo
        
        # Compare table counts
        echo "Table Count Comparison:"
        echo
        
        psql "$SOURCE_DB_URL" -t -c "
            SELECT tablename, count(*) as row_count
            FROM pg_tables
            WHERE schemaname = 'public'
            GROUP BY tablename
            ORDER BY tablename;
        " | while read -r line; do
            if [ ! -z "$line" ]; then
                local table=$(echo "$line" | cut -d'|' -f1)
                local source_count=$(echo "$line" | cut -d'|' -f2)
                
                local target_count=$(psql "$TARGET_DB_URL" -t -c "
                    SELECT count(*)
                    FROM $table;
                ")
                
                echo "Table: $table"
                echo "Source count: $source_count"
                echo "Target count: $target_count"
                echo
            fi
        done
        
        # Compare table schemas
        echo "Schema Comparison:"
        echo
        
        psql "$SOURCE_DB_URL" -t -c "
            SELECT tablename
            FROM pg_tables
            WHERE schemaname = 'public'
            ORDER BY tablename;
        " | while read -r table; do
            if [ ! -z "$table" ]; then
                table=$(echo "$table" | xargs)
                
                echo "Table: $table"
                echo "Source schema:"
                psql "$SOURCE_DB_URL" -c "\d $table"
                echo
                echo "Target schema:"
                psql "$TARGET_DB_URL" -c "\d $table"
                echo
            fi
        done
        
    } > "$verify_file"
    
    log_sync "verify" "success" "Generated verification report"
    echo "Verification report generated: $verify_file"
}

# Function to generate sync report
generate_report() {
    local report_file="$SYNC_DIR/sync_report_$(date '+%Y%m%d_%H%M%S').md"
    
    {
        echo "# Database Synchronization Report"
        echo "Generated on: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Source: $SOURCE_ENV"
        echo "Target: $TARGET_ENV"
        echo
        
        echo "## Schema Differences"
        echo
        compare_schemas
        echo
        
        echo "## Verification Results"
        echo
        verify_sync
        echo
        
        echo "## Recent Sync Operations"
        echo
        tail -n 20 "$SYNC_DIR/sync.log"
        
    } > "$report_file"
    
    log_sync "report" "success" "Generated sync report"
    echo "Report generated: $report_file"
}

# Process commands
case "${3:-compare}" in
    "compare")
        compare_schemas
        ;;
        
    "sync")
        if [ -z "$4" ]; then
            echo "Error: Diff file not specified"
            echo "Usage: $0 $SOURCE_ENV $TARGET_ENV sync <diff_file>"
            exit 1
        fi
        sync_schema "$4"
        ;;
        
    "verify")
        verify_sync
        ;;
        
    "report")
        generate_report
        ;;
        
    *)
        echo "Usage: $0 [source_env] [target_env] [compare|sync|verify|report] [args]"
        exit 1
        ;;
esac

exit 0
