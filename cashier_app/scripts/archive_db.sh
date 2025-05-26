#!/bin/bash

# Database archiving script
# Usage: ./archive_db.sh [environment] [operation]
# Example: ./archive_db.sh development archive-old-data

# Set environment
ENV=${1:-development}
echo "Managing database archives for $ENV environment"

# Load environment variables
if [ -f "../.env.$ENV" ]; then
    source "../.env.$ENV"
else
    echo "Error: Environment file .env.$ENV not found"
    exit 1
fi

# Create archive directory
ARCHIVE_DIR="../archives"
mkdir -p "$ARCHIVE_DIR"

# Create archive logs directory
LOG_DIR="../logs/archives"
mkdir -p "$LOG_DIR"

# Function to log archive operations
log_archive() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$LOG_DIR/archives.log"
}

# Function to archive old data
archive_old_data() {
    local retention_days=${1:-365}
    echo "Archiving data older than $retention_days days..."
    
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local archive_file="$ARCHIVE_DIR/archive_${ENV}_${timestamp}"
    
    # Create archive tables if they don't exist
    psql "$SUPABASE_DB_URL" << EOF
    -- Create archive schema
    CREATE SCHEMA IF NOT EXISTS archive;
    
    -- Create archive tracking table
    CREATE TABLE IF NOT EXISTS archive.archive_log (
        id SERIAL PRIMARY KEY,
        table_name TEXT NOT NULL,
        archive_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        records_archived INTEGER,
        archive_file TEXT,
        status TEXT,
        retention_days INTEGER
    );
EOF
    
    # Archive data from each table with timestamp column
    psql "$SUPABASE_DB_URL" -t -c "
        SELECT table_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
        AND column_name IN ('created_at', 'updated_at', 'timestamp')
        GROUP BY table_name;
    " | while read -r table; do
        if [ ! -z "$table" ]; then
            table=$(echo "$table" | xargs)
            echo "Processing table: $table"
            
            # Create archive table if it doesn't exist
            psql "$SUPABASE_DB_URL" -c "
                CREATE TABLE IF NOT EXISTS archive.${table} (LIKE public.${table} INCLUDING ALL);
            "
            
            # Move old records to archive
            local archived_count=$(psql "$SUPABASE_DB_URL" -t -c "
                WITH moved_rows AS (
                    DELETE FROM public.${table}
                    WHERE created_at < CURRENT_DATE - INTERVAL '$retention_days days'
                    RETURNING *
                )
                INSERT INTO archive.${table}
                SELECT * FROM moved_rows
                RETURNING COUNT(*);
            ")
            
            if [ ! -z "$archived_count" ]; then
                archived_count=$(echo "$archived_count" | xargs)
                
                # Export archived data
                if [ "$archived_count" -gt 0 ]; then
                    local table_archive="${archive_file}_${table}.csv"
                    psql "$SUPABASE_DB_URL" -c "\COPY archive.${table} TO '$table_archive' WITH CSV HEADER;"
                    
                    # Compress archive
                    gzip "$table_archive"
                    
                    # Log archive operation
                    psql "$SUPABASE_DB_URL" -c "
                        INSERT INTO archive.archive_log 
                        (table_name, records_archived, archive_file, status, retention_days)
                        VALUES 
                        ('$table', $archived_count, '${table_archive}.gz', 'completed', $retention_days);
                    "
                    
                    log_archive "archive" "success" "Archived $archived_count records from $table"
                    echo "Archived $archived_count records from $table"
                fi
            fi
        fi
    done
}

# Function to restore archived data
restore_archived_data() {
    local archive_file=$1
    
    if [ ! -f "$archive_file" ]; then
        echo "Error: Archive file not found: $archive_file"
        return 1
    fi
    
    echo "Restoring data from archive: $archive_file"
    
    # Extract table name from filename
    local table=$(basename "$archive_file" | sed 's/archive_.*_[0-9]\{8\}_[0-9]\{6\}_\(.*\)\.csv\.gz/\1/')
    
    if [ -z "$table" ]; then
        echo "Error: Could not determine table name from archive filename"
        return 1
    fi
    
    # Create temporary directory
    local temp_dir=$(mktemp -d)
    
    # Decompress archive
    gunzip -c "$archive_file" > "$temp_dir/${table}.csv"
    
    # Restore data
    psql "$SUPABASE_DB_URL" -c "
        CREATE TEMP TABLE temp_restore (LIKE public.${table} INCLUDING ALL);
        
        \COPY temp_restore FROM '$temp_dir/${table}.csv' WITH CSV HEADER;
        
        INSERT INTO public.${table}
        SELECT *
        FROM temp_restore
        ON CONFLICT DO NOTHING;
        
        DROP TABLE temp_restore;
    "
    
    # Clean up
    rm -rf "$temp_dir"
    
    log_archive "restore" "success" "Restored data from $archive_file"
    echo "Restored data from $archive_file"
}

# Function to manage retention policies
manage_retention() {
    echo "Managing retention policies..."
    
    # Define retention periods for different tables
    declare -A retention_periods=(
        ["transactions"]=730    # 2 years
        ["audit_log"]=365      # 1 year
        ["system_logs"]=90     # 90 days
        ["sessions"]=30        # 30 days
        ["temp_data"]=7        # 7 days
    )
    
    for table in "${!retention_periods[@]}"; do
        local days=${retention_periods[$table]}
        echo "Applying $days day retention policy to $table"
        
        # Archive old data
        archive_old_data "$days"
        
        # Clean up archive tables older than retention period
        psql "$SUPABASE_DB_URL" -c "
            DELETE FROM archive.${table}
            WHERE created_at < CURRENT_DATE - INTERVAL '$days days';
        "
    done
}

# Function to list archives
list_archives() {
    echo "Available archives:"
    echo "------------------"
    
    ls -lh "$ARCHIVE_DIR"
    
    echo -e "\nArchive Log:"
    echo "------------"
    
    psql "$SUPABASE_DB_URL" -c "
        SELECT 
            table_name,
            archive_date,
            records_archived,
            archive_file,
            status,
            retention_days
        FROM archive.archive_log
        ORDER BY archive_date DESC
        LIMIT 10;
    "
}

# Function to clean up old archives
cleanup_archives() {
    local retention_days=${1:-90}
    echo "Cleaning up archives older than $retention_days days..."
    
    # Remove old archive files
    find "$ARCHIVE_DIR" -name "archive_*.csv.gz" -mtime +$retention_days -delete
    
    # Clean up archive log
    psql "$SUPABASE_DB_URL" -c "
        DELETE FROM archive.archive_log
        WHERE archive_date < CURRENT_DATE - INTERVAL '$retention_days days';
    "
    
    log_archive "cleanup" "success" "Cleaned up archives older than $retention_days days"
    echo "Archive cleanup completed"
}

# Function to verify archives
verify_archives() {
    echo "Verifying archives..."
    local issues=0
    
    # Check archive files
    for archive in "$ARCHIVE_DIR"/archive_*.csv.gz; do
        if [ -f "$archive" ]; then
            # Check if file is valid gzip
            if ! gunzip -t "$archive" 2>/dev/null; then
                echo "Error: Corrupt archive file: $archive"
                ((issues++))
                continue
            fi
            
            # Check if archive is logged
            local filename=$(basename "$archive")
            local logged=$(psql "$SUPABASE_DB_URL" -t -c "
                SELECT COUNT(*)
                FROM archive.archive_log
                WHERE archive_file LIKE '%$filename%';
            ")
            
            if [ "$logged" -eq 0 ]; then
                echo "Warning: Unlogged archive file: $archive"
                ((issues++))
            fi
        fi
    done
    
    # Check for missing archive files
    psql "$SUPABASE_DB_URL" -t -c "
        SELECT archive_file
        FROM archive.archive_log
        WHERE status = 'completed';
    " | while read -r file; do
        if [ ! -z "$file" ]; then
            file=$(echo "$file" | xargs)
            if [ ! -f "$file" ]; then
                echo "Warning: Missing archive file: $file"
                ((issues++))
            fi
        fi
    done
    
    if [ "$issues" -eq 0 ]; then
        log_archive "verify" "success" "All archives verified successfully"
        echo "All archives verified successfully"
    else
        log_archive "verify" "warning" "Found $issues issue(s) with archives"
        echo "Found $issues issue(s) with archives"
    fi
    
    return $issues
}

# Process commands
case "${2:-list}" in
    "archive")
        archive_old_data "${3:-365}"
        ;;
        
    "restore")
        if [ -z "$3" ]; then
            echo "Error: Archive file not specified"
            echo "Usage: $0 $ENV restore <archive_file>"
            exit 1
        fi
        restore_archived_data "$3"
        ;;
        
    "retention")
        manage_retention
        ;;
        
    "list")
        list_archives
        ;;
        
    "cleanup")
        cleanup_archives "${3:-90}"
        ;;
        
    "verify")
        verify_archives
        ;;
        
    *)
        echo "Usage: $0 [environment] [archive|restore|retention|list|cleanup|verify] [args]"
        exit 1
        ;;
esac

exit 0
