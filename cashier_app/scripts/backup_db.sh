#!/bin/bash

# Database backup script
# Usage: ./backup_db.sh [environment] [operation]
# Example: ./backup_db.sh development backup

# Set environment
ENV=${1:-development}
echo "Running backup operation for $ENV environment"

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

# Create backups directory if it doesn't exist
BACKUP_DIR="../backups"
mkdir -p "$BACKUP_DIR"

# Function to create backup
create_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/backup_${ENV}_${timestamp}.sql"
    local compressed_file="${backup_file}.gz"
    
    echo "Creating backup..."
    
    # Create backup with schema and data
    if pg_dump "$SUPABASE_DB_URL" > "$backup_file"; then
        # Compress backup
        if gzip "$backup_file"; then
            echo "Backup created successfully: $compressed_file"
            
            # Clean up old backups (keep last 5)
            local keep_count=5
            local old_backups=$(ls -t "$BACKUP_DIR"/backup_${ENV}_*.sql.gz | tail -n +$((keep_count + 1)))
            if [ ! -z "$old_backups" ]; then
                echo "Cleaning up old backups..."
                echo "$old_backups" | xargs rm -f
            fi
            
            return 0
        else
            echo "Error: Failed to compress backup"
            rm -f "$backup_file"
            return 1
        fi
    else
        echo "Error: Backup failed"
        rm -f "$backup_file"
        return 1
    fi
}

# Function to restore backup
restore_backup() {
    local backup_file=$1
    
    if [ ! -f "$backup_file" ]; then
        echo "Error: Backup file not found: $backup_file"
        return 1
    fi
    
    echo "Restoring from backup: $backup_file"
    
    # If file is compressed, decompress it first
    if [[ "$backup_file" == *.gz ]]; then
        echo "Decompressing backup file..."
        gunzip -c "$backup_file" | psql "$SUPABASE_DB_URL"
    else
        psql "$SUPABASE_DB_URL" < "$backup_file"
    fi
    
    if [ $? -eq 0 ]; then
        echo "Restore completed successfully"
        return 0
    else
        echo "Error: Restore failed"
        return 1
    fi
}

# Function to list backups
list_backups() {
    echo "Available backups:"
    echo "----------------"
    
    if [ -d "$BACKUP_DIR" ]; then
        local backups=$(ls -1 "$BACKUP_DIR"/backup_${ENV}_*.sql.gz 2>/dev/null)
        if [ ! -z "$backups" ]; then
            ls -lh "$BACKUP_DIR"/backup_${ENV}_*.sql.gz | awk '{print $9, "(" $5 ")"}'
        else
            echo "No backups found"
        fi
    else
        echo "No backups directory found"
    fi
}

# Process command line arguments
case "${2:-backup}" in
    "backup")
        if ! create_backup; then
            exit 1
        fi
        ;;
        
    "restore")
        # List available backups
        list_backups
        
        # Ask which backup to restore
        echo
        read -p "Enter the backup file name to restore (or 'latest' for most recent): " backup_choice
        
        if [ "$backup_choice" = "latest" ]; then
            backup_file=$(ls -t "$BACKUP_DIR"/backup_${ENV}_*.sql.gz | head -1)
        else
            backup_file="$BACKUP_DIR/$backup_choice"
        fi
        
        # Confirm restore
        read -p "Are you sure you want to restore from $backup_file? This will overwrite the current database. (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if ! restore_backup "$backup_file"; then
                exit 1
            fi
        else
            echo "Restore cancelled"
            exit 0
        fi
        ;;
        
    "list")
        list_backups
        ;;
        
    "clean")
        read -p "Are you sure you want to delete all backups for $ENV environment? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -f "$BACKUP_DIR"/backup_${ENV}_*.sql.gz
            echo "All backups deleted"
        else
            echo "Clean operation cancelled"
        fi
        ;;
        
    *)
        echo "Usage: $0 [environment] [backup|restore|list|clean]"
        exit 1
        ;;
esac

# Create backup log entry
LOG_FILE="$BACKUP_DIR/backup.log"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] $ENV - ${2:-backup} operation completed" >> "$LOG_FILE"

exit 0
