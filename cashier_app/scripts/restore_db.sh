#!/bin/bash

# Database restore script
# Usage: ./restore_db.sh [environment] [operation] [backup-file]
# Example: ./restore_db.sh development restore backups/backup_dev_20240101.sql.gz

# Set environment
ENV=${1:-development}
echo "Running database restore operations in $ENV environment"

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

# Create restore logs directory
RESTORE_DIR="../logs/restore"
mkdir -p "$RESTORE_DIR"

# Function to log restore operations
log_restore() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$RESTORE_DIR/restore.log"
}

# Function to verify backup file
verify_backup() {
    local backup_file=$1
    
    if [ ! -f "$backup_file" ]; then
        echo "Error: Backup file not found: $backup_file"
        return 1
    fi
    
    # Check if file is gzipped
    if [[ "$backup_file" == *.gz ]]; then
        if ! gunzip -t "$backup_file" 2>/dev/null; then
            echo "Error: Backup file is corrupted: $backup_file"
            return 1
        fi
    fi
    
    return 0
}

# Function to create point-in-time snapshot
create_snapshot() {
    local snapshot_file="$RESTORE_DIR/snapshot_$(date '+%Y%m%d_%H%M%S').sql.gz"
    
    echo "Creating database snapshot before restore..."
    
    if pg_dump "$SUPABASE_DB_URL" | gzip > "$snapshot_file"; then
        log_restore "snapshot" "success" "Created snapshot: $snapshot_file"
        echo "Snapshot created: $snapshot_file"
        return 0
    else
        log_restore "snapshot" "error" "Failed to create snapshot"
        echo "Error: Failed to create snapshot"
        return 1
    fi
}

# Function to restore database
restore_database() {
    local backup_file=$1
    
    echo "Restoring database from backup..."
    
    # Create snapshot first
    if ! create_snapshot; then
        return 1
    fi
    
    # Drop existing connections
    psql "$SUPABASE_DB_URL" << EOF
    SELECT pg_terminate_backend(pid) 
    FROM pg_stat_activity 
    WHERE datname = current_database()
    AND pid <> pg_backend_pid();
EOF
    
    # Drop and recreate database objects
    psql "$SUPABASE_DB_URL" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
    
    # Restore from backup
    if [[ "$backup_file" == *.gz ]]; then
        if gunzip -c "$backup_file" | psql "$SUPABASE_DB_URL"; then
            log_restore "restore" "success" "Restored from: $backup_file"
            echo "Database restored successfully"
            return 0
        else
            log_restore "restore" "error" "Failed to restore from: $backup_file"
            echo "Error: Restore failed"
            return 1
        fi
    else
        if psql "$SUPABASE_DB_URL" < "$backup_file"; then
            log_restore "restore" "success" "Restored from: $backup_file"
            echo "Database restored successfully"
            return 0
        else
            log_restore "restore" "error" "Failed to restore from: $backup_file"
            echo "Error: Restore failed"
            return 1
        fi
    fi
}

# Function to verify restore
verify_restore() {
    echo "Verifying database restore..."
    
    # Check if essential tables exist
    local tables=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT COUNT(*) 
        FROM information_schema.tables 
        WHERE table_schema = 'public'
        AND table_name IN ('users', 'stores', 'products', 'transactions');
    ")
    
    if [ "$tables" -ne "4" ]; then
        log_restore "verify" "error" "Missing essential tables"
        echo "Error: Database restore verification failed - missing tables"
        return 1
    fi
    
    # Check if data exists
    local data_exists=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT CASE 
            WHEN EXISTS (SELECT 1 FROM users LIMIT 1) THEN 1 
            ELSE 0 
        END;
    ")
    
    if [ "$data_exists" -eq "0" ]; then
        log_restore "verify" "error" "No data found in essential tables"
        echo "Error: Database restore verification failed - no data"
        return 1
    fi
    
    log_restore "verify" "success" "Database restore verified"
    echo "Database restore verified successfully"
    return 0
}

# Function to list available backups
list_backups() {
    echo "Available backups:"
    echo "----------------"
    
    if [ -d "../backups" ]; then
        ls -lh ../backups/*.sql.gz 2>/dev/null
    else
        echo "No backups directory found"
    fi
    
    echo -e "\nAvailable snapshots:"
    echo "------------------"
    
    if [ -d "$RESTORE_DIR" ]; then
        ls -lh "$RESTORE_DIR"/*.sql.gz 2>/dev/null
    else
        echo "No snapshots found"
    fi
}

# Function to restore to specific point in time
restore_point_in_time() {
    local timestamp=$1
    
    echo "Restoring database to point in time: $timestamp"
    
    # Find closest backup before timestamp
    local backup_file=$(ls -1 ../backups/*.sql.gz 2>/dev/null | while read file; do
        backup_date=$(echo "$file" | grep -o '[0-9]\{8\}_[0-9]\{6\}')
        if [[ "$backup_date" < "$timestamp" ]]; then
            echo "$file"
        fi
    done | tail -n 1)
    
    if [ -z "$backup_file" ]; then
        echo "Error: No suitable backup found before timestamp: $timestamp"
        return 1
    fi
    
    echo "Using backup file: $backup_file"
    
    # Restore backup
    if ! restore_database "$backup_file"; then
        return 1
    fi
    
    # Apply WAL logs if available
    # Note: This requires archive_mode=on and archive_command set up in PostgreSQL
    
    return 0
}

# Process commands
case "${2:-list}" in
    "restore")
        if [ -z "$3" ]; then
            echo "Error: Backup file not specified"
            echo "Usage: $0 $ENV restore <backup-file>"
            exit 1
        fi
        
        if ! verify_backup "$3"; then
            exit 1
        fi
        
        if ! restore_database "$3"; then
            exit 1
        fi
        
        if ! verify_restore; then
            exit 1
        fi
        ;;
        
    "verify")
        if ! verify_restore; then
            exit 1
        fi
        ;;
        
    "snapshot")
        if ! create_snapshot; then
            exit 1
        fi
        ;;
        
    "point-in-time")
        if [ -z "$3" ]; then
            echo "Error: Timestamp not specified"
            echo "Usage: $0 $ENV point-in-time YYYYMMDD_HHMMSS"
            exit 1
        fi
        
        if ! restore_point_in_time "$3"; then
            exit 1
        fi
        ;;
        
    "list")
        list_backups
        ;;
        
    *)
        echo "Usage: $0 [environment] [restore|verify|snapshot|point-in-time|list] [backup-file|timestamp]"
        exit 1
        ;;
esac

exit 0
