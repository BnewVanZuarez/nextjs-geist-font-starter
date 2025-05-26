#!/bin/bash

# Database transfer script
# Usage: ./transfer_db.sh [environment] [operation]
# Example: ./transfer_db.sh development export

# Set environment
ENV=${1:-development}
echo "Managing database transfers for $ENV environment"

# Load environment variables
if [ -f "../.env.$ENV" ]; then
    source "../.env.$ENV"
else
    echo "Error: Environment file .env.$ENV not found"
    exit 1
fi

# Create transfer directory
TRANSFER_DIR="../transfers"
mkdir -p "$TRANSFER_DIR"

# Create transfer logs directory
LOG_DIR="../logs/transfers"
mkdir -p "$LOG_DIR"

# Function to log transfer operations
log_transfer() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$LOG_DIR/transfers.log"
}

# Function to export database
export_db() {
    local format=${1:-sql}
    echo "Exporting database in $format format..."
    
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local export_file="$TRANSFER_DIR/export_${ENV}_${timestamp}"
    
    case "$format" in
        "sql")
            export_file="${export_file}.sql"
            if pg_dump "$SUPABASE_DB_URL" > "$export_file"; then
                log_transfer "export" "success" "Database exported to $export_file"
                echo "Database exported to: $export_file"
                
                # Compress the export
                gzip "$export_file"
                echo "Export compressed: ${export_file}.gz"
            else
                log_transfer "export" "error" "Failed to export database"
                echo "Error: Failed to export database"
                return 1
            fi
            ;;
            
        "csv")
            export_file="${export_file}_csv"
            mkdir -p "$export_file"
            
            # Export each table to CSV
            psql "$SUPABASE_DB_URL" -t -c "
                SELECT tablename 
                FROM pg_tables 
                WHERE schemaname = 'public'
                ORDER BY tablename;
            " | while read -r table; do
                if [ ! -z "$table" ]; then
                    table=$(echo "$table" | xargs)
                    echo "Exporting table: $table"
                    
                    # Export table structure
                    pg_dump "$SUPABASE_DB_URL" --schema-only -t "$table" > "$export_file/${table}_schema.sql"
                    
                    # Export table data
                    psql "$SUPABASE_DB_URL" -c "\COPY $table TO '$export_file/${table}.csv' WITH CSV HEADER;"
                fi
            done
            
            # Create metadata file
            {
                echo "Export Date: $(date '+%Y-%m-%d %H:%M:%S')"
                echo "Environment: $ENV"
                echo "Tables:"
                ls -1 "$export_file"/*.csv | xargs -n1 basename
            } > "$export_file/metadata.txt"
            
            # Compress the export
            cd "$TRANSFER_DIR" && tar czf "export_${ENV}_${timestamp}_csv.tar.gz" "export_${ENV}_${timestamp}_csv"
            rm -rf "$export_file"
            
            log_transfer "export" "success" "Database exported to CSV format"
            echo "Database exported to CSV format: export_${ENV}_${timestamp}_csv.tar.gz"
            ;;
            
        "custom")
            export_file="${export_file}.custom"
            if pg_dump -Fc "$SUPABASE_DB_URL" > "$export_file"; then
                log_transfer "export" "success" "Database exported to custom format"
                echo "Database exported to: $export_file"
            else
                log_transfer "export" "error" "Failed to export database"
                echo "Error: Failed to export database"
                return 1
            fi
            ;;
            
        *)
            echo "Error: Unsupported format. Use 'sql', 'csv', or 'custom'"
            return 1
            ;;
    esac
}

# Function to import database
import_db() {
    local file=$1
    
    if [ ! -f "$file" ]; then
        echo "Error: Import file not found: $file"
        return 1
    fi
    
    echo "Importing database from $file..."
    
    # Create backup before import
    local backup_file="$TRANSFER_DIR/pre_import_backup_$(date '+%Y%m%d_%H%M%S').sql.gz"
    echo "Creating backup before import..."
    if pg_dump "$SUPABASE_DB_URL" | gzip > "$backup_file"; then
        echo "Backup created: $backup_file"
    else
        echo "Warning: Failed to create backup"
    fi
    
    # Determine file type and import
    case "$file" in
        *.sql)
            if psql "$SUPABASE_DB_URL" < "$file"; then
                log_transfer "import" "success" "Database imported from SQL file"
                echo "Database imported successfully"
            else
                log_transfer "import" "error" "Failed to import database"
                echo "Error: Failed to import database"
                return 1
            fi
            ;;
            
        *.sql.gz)
            if gunzip -c "$file" | psql "$SUPABASE_DB_URL"; then
                log_transfer "import" "success" "Database imported from compressed SQL file"
                echo "Database imported successfully"
            else
                log_transfer "import" "error" "Failed to import database"
                echo "Error: Failed to import database"
                return 1
            fi
            ;;
            
        *.tar.gz)
            local temp_dir=$(mktemp -d)
            
            # Extract archive
            tar xzf "$file" -C "$temp_dir"
            
            # Find CSV directory
            local csv_dir=$(find "$temp_dir" -type d -name "*_csv")
            
            if [ -d "$csv_dir" ]; then
                # Process each table
                for schema_file in "$csv_dir"/*_schema.sql; do
                    if [ -f "$schema_file" ]; then
                        local table=$(basename "$schema_file" _schema.sql)
                        echo "Importing table: $table"
                        
                        # Create table structure
                        psql "$SUPABASE_DB_URL" < "$schema_file"
                        
                        # Import data if CSV exists
                        if [ -f "$csv_dir/${table}.csv" ]; then
                            psql "$SUPABASE_DB_URL" -c "\COPY $table FROM '$csv_dir/${table}.csv' WITH CSV HEADER;"
                        fi
                    fi
                done
                
                rm -rf "$temp_dir"
                log_transfer "import" "success" "Database imported from CSV format"
                echo "Database imported successfully"
            else
                rm -rf "$temp_dir"
                log_transfer "import" "error" "Invalid CSV archive format"
                echo "Error: Invalid CSV archive format"
                return 1
            fi
            ;;
            
        *.custom)
            if pg_restore -d "$SUPABASE_DB_URL" "$file"; then
                log_transfer "import" "success" "Database imported from custom format"
                echo "Database imported successfully"
            else
                log_transfer "import" "error" "Failed to import database"
                echo "Error: Failed to import database"
                return 1
            fi
            ;;
            
        *)
            echo "Error: Unsupported file format"
            return 1
            ;;
    esac
}

# Function to verify transfer
verify_transfer() {
    local source_file=$1
    echo "Verifying database transfer..."
    
    # Create temporary database for verification
    local temp_db="verify_${RANDOM}"
    
    if createdb "$temp_db"; then
        echo "Created temporary database: $temp_db"
        
        # Import to temporary database
        local temp_url="${SUPABASE_DB_URL/%[^/]*/}$temp_db"
        
        case "$source_file" in
            *.sql)
                psql "$temp_url" < "$source_file"
                ;;
            *.sql.gz)
                gunzip -c "$source_file" | psql "$temp_url"
                ;;
            *.custom)
                pg_restore -d "$temp_url" "$source_file"
                ;;
        esac
        
        # Compare row counts
        local discrepancies=0
        
        psql "$SUPABASE_DB_URL" -t -c "
            SELECT tablename 
            FROM pg_tables 
            WHERE schemaname = 'public'
            ORDER BY tablename;
        " | while read -r table; do
            if [ ! -z "$table" ]; then
                table=$(echo "$table" | xargs)
                
                local orig_count=$(psql "$SUPABASE_DB_URL" -t -c "SELECT COUNT(*) FROM $table;")
                local temp_count=$(psql "$temp_url" -t -c "SELECT COUNT(*) FROM $table;")
                
                if [ "$orig_count" != "$temp_count" ]; then
                    echo "Discrepancy in table $table: Original=$orig_count, Imported=$temp_count"
                    ((discrepancies++))
                fi
            fi
        done
        
        # Clean up
        dropdb "$temp_db"
        
        if [ "$discrepancies" -eq 0 ]; then
            log_transfer "verify" "success" "Transfer verification passed"
            echo "Transfer verification passed"
            return 0
        else
            log_transfer "verify" "error" "Found $discrepancies table(s) with discrepancies"
            echo "Error: Found $discrepancies table(s) with discrepancies"
            return 1
        fi
    else
        log_transfer "verify" "error" "Failed to create temporary database"
        echo "Error: Failed to create temporary database"
        return 1
    fi
}

# Function to list transfers
list_transfers() {
    echo "Available transfers:"
    echo "------------------"
    
    ls -lh "$TRANSFER_DIR"
}

# Process commands
case "${2:-list}" in
    "export")
        export_db "${3:-sql}"
        ;;
        
    "import")
        if [ -z "$3" ]; then
            echo "Error: Import file not specified"
            echo "Usage: $0 $ENV import <file>"
            exit 1
        fi
        import_db "$3"
        ;;
        
    "verify")
        if [ -z "$3" ]; then
            echo "Error: Source file not specified"
            echo "Usage: $0 $ENV verify <file>"
            exit 1
        fi
        verify_transfer "$3"
        ;;
        
    "list")
        list_transfers
        ;;
        
    *)
        echo "Usage: $0 [environment] [export|import|verify|list] [args]"
        exit 1
        ;;
esac

exit 0
