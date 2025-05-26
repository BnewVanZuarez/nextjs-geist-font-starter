#!/bin/bash

# Database versioning script
# Usage: ./version_db.sh [environment] [operation]
# Example: ./version_db.sh development create "Add user preferences"

# Set environment
ENV=${1:-development}
echo "Managing database versions for $ENV environment"

# Load environment variables
if [ -f "../.env.$ENV" ]; then
    source "../.env.$ENV"
else
    echo "Error: Environment file .env.$ENV not found"
    exit 1
fi

# Create version control directory
VERSION_DIR="../migrations"
mkdir -p "$VERSION_DIR"

# Create version logs directory
LOG_DIR="../logs/versions"
mkdir -p "$LOG_DIR"

# Function to log version operations
log_version() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$LOG_DIR/versions.log"
}

# Function to create new migration
create_migration() {
    local description=$1
    local timestamp=$(date '+%Y%m%d%H%M%S')
    local filename="${timestamp}_${description// /_}.sql"
    local filepath="$VERSION_DIR/$filename"
    
    # Create migration file
    cat > "$filepath" << EOF
-- Migration: $description
-- Created at: $(date '+%Y-%m-%d %H:%M:%S')
-- Environment: $ENV

-- Write your migration SQL here

---- Up migration
BEGIN;

-- Add your schema changes here

COMMIT;

---- Down migration
BEGIN;

-- Add your rollback changes here

COMMIT;
EOF
    
    log_version "create" "success" "Created migration: $filename"
    echo "Created migration file: $filepath"
    
    # Update version registry
    psql "$SUPABASE_DB_URL" << EOF
    CREATE TABLE IF NOT EXISTS schema_versions (
        id SERIAL PRIMARY KEY,
        version VARCHAR(255) NOT NULL,
        description TEXT,
        applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        applied_by TEXT DEFAULT CURRENT_USER,
        status TEXT DEFAULT 'pending'
    );
    
    INSERT INTO schema_versions (version, description)
    VALUES ('$timestamp', '$description');
EOF
}

# Function to apply migrations
apply_migrations() {
    echo "Applying pending migrations..."
    
    # Create temporary directory for logs
    local temp_dir=$(mktemp -d)
    
    # Get list of pending migrations
    local pending_migrations=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT version 
        FROM schema_versions 
        WHERE status = 'pending'
        ORDER BY version ASC;
    ")
    
    for version in $pending_migrations; do
        version=$(echo "$version" | xargs)  # Trim whitespace
        local migration_file=$(find "$VERSION_DIR" -name "${version}*.sql")
        
        if [ -f "$migration_file" ]; then
            echo "Applying migration: $(basename "$migration_file")"
            
            # Extract up migration
            sed -n '/^---- Up migration$/,/^---- Down migration$/p' "$migration_file" > "$temp_dir/up.sql"
            
            # Apply migration
            if psql "$SUPABASE_DB_URL" < "$temp_dir/up.sql"; then
                psql "$SUPABASE_DB_URL" -c "
                    UPDATE schema_versions 
                    SET status = 'applied', applied_at = CURRENT_TIMESTAMP 
                    WHERE version = '$version';
                "
                log_version "apply" "success" "Applied migration: $version"
                echo "Successfully applied migration: $version"
            else
                log_version "apply" "error" "Failed to apply migration: $version"
                echo "Error: Failed to apply migration: $version"
                rm -rf "$temp_dir"
                return 1
            fi
        else
            log_version "apply" "error" "Migration file not found: $version"
            echo "Error: Migration file not found for version: $version"
        fi
    done
    
    rm -rf "$temp_dir"
}

# Function to rollback migrations
rollback_migrations() {
    local versions=$1
    echo "Rolling back last $versions migration(s)..."
    
    # Create temporary directory for logs
    local temp_dir=$(mktemp -d)
    
    # Get list of migrations to rollback
    local rollback_migrations=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT version 
        FROM schema_versions 
        WHERE status = 'applied'
        ORDER BY version DESC
        LIMIT $versions;
    ")
    
    for version in $rollback_migrations; do
        version=$(echo "$version" | xargs)  # Trim whitespace
        local migration_file=$(find "$VERSION_DIR" -name "${version}*.sql")
        
        if [ -f "$migration_file" ]; then
            echo "Rolling back migration: $(basename "$migration_file")"
            
            # Extract down migration
            sed -n '/^---- Down migration$/,/^$/p' "$migration_file" > "$temp_dir/down.sql"
            
            # Apply rollback
            if psql "$SUPABASE_DB_URL" < "$temp_dir/down.sql"; then
                psql "$SUPABASE_DB_URL" -c "
                    UPDATE schema_versions 
                    SET status = 'rolled_back', applied_at = CURRENT_TIMESTAMP 
                    WHERE version = '$version';
                "
                log_version "rollback" "success" "Rolled back migration: $version"
                echo "Successfully rolled back migration: $version"
            else
                log_version "rollback" "error" "Failed to roll back migration: $version"
                echo "Error: Failed to roll back migration: $version"
                rm -rf "$temp_dir"
                return 1
            fi
        else
            log_version "rollback" "error" "Migration file not found: $version"
            echo "Error: Migration file not found for version: $version"
        fi
    done
    
    rm -rf "$temp_dir"
}

# Function to check migration status
check_status() {
    echo "Checking migration status..."
    
    psql "$SUPABASE_DB_URL" << EOF
    SELECT 
        version,
        description,
        status,
        applied_at,
        applied_by
    FROM schema_versions
    ORDER BY version DESC;
EOF
}

# Function to verify database version
verify_version() {
    echo "Verifying database version..."
    
    # Get current version
    local current_version=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT version 
        FROM schema_versions 
        WHERE status = 'applied'
        ORDER BY version DESC
        LIMIT 1;
    ")
    
    if [ -z "$current_version" ]; then
        echo "No migrations have been applied yet"
        return 1
    fi
    
    # Check if all migrations up to current version are applied
    local missing_migrations=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT version 
        FROM schema_versions 
        WHERE version <= '$current_version'
        AND status != 'applied'
        ORDER BY version ASC;
    ")
    
    if [ ! -z "$missing_migrations" ]; then
        echo "Warning: Found missing migrations:"
        echo "$missing_migrations"
        return 1
    fi
    
    echo "Database version is consistent: $current_version"
    return 0
}

# Function to generate migration report
generate_report() {
    local report_file="$LOG_DIR/migration_report_$(date '+%Y%m%d_%H%M%S').txt"
    
    {
        echo "Database Migration Report"
        echo "========================"
        echo "Environment: $ENV"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo
        
        echo "Current Status"
        echo "--------------"
        check_status
        echo
        
        echo "Version Verification"
        echo "-------------------"
        verify_version
        echo
        
        echo "Migration History"
        echo "----------------"
        psql "$SUPABASE_DB_URL" -c "
            SELECT 
                version,
                description,
                status,
                applied_at,
                applied_by
            FROM schema_versions
            ORDER BY version DESC;
        "
        
    } > "$report_file"
    
    echo "Report generated: $report_file"
}

# Process commands
case "${2:-status}" in
    "create")
        if [ -z "$3" ]; then
            echo "Error: Migration description required"
            echo "Usage: $0 $ENV create \"<description>\""
            exit 1
        fi
        create_migration "$3"
        ;;
        
    "apply")
        apply_migrations
        ;;
        
    "rollback")
        local versions=${3:-1}
        rollback_migrations "$versions"
        ;;
        
    "status")
        check_status
        ;;
        
    "verify")
        verify_version
        ;;
        
    "report")
        generate_report
        ;;
        
    *)
        echo "Usage: $0 [environment] [create|apply|rollback|status|verify|report] [args]"
        exit 1
        ;;
esac

exit 0
