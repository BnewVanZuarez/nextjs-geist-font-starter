#!/bin/bash

# Database migration script
# Usage: ./run_migrations.sh [environment]
# Example: ./run_migrations.sh development

# Set environment
ENV=${1:-development}
echo "Running migrations for $ENV environment"

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

# Function to run a migration
run_migration() {
    local file=$1
    local version=$(basename "$file" | cut -d'_' -f1)
    
    echo "Running migration $file..."
    
    # Check if migration was already applied
    if psql "$SUPABASE_DB_URL" -t -c "SELECT version FROM schema_versions WHERE version = $version;" | grep -q "$version"; then
        echo "Migration $version already applied"
        return 0
    fi
    
    # Run migration
    if psql "$SUPABASE_DB_URL" -f "$file"; then
        echo "Migration $file completed successfully"
        return 0
    else
        echo "Error: Migration $file failed"
        return 1
    fi
}

# Function to rollback a migration
rollback_migration() {
    local file=$1
    local version=$(basename "$file" | cut -d'_' -f1)
    
    echo "Rolling back migration $file..."
    
    # Extract rollback script
    local rollback_script=$(sed -n '/^-- Rollback script/,/^$/p' "$file" | grep -v "^--" | grep -v "^$")
    
    if [ -z "$rollback_script" ]; then
        echo "Error: No rollback script found in $file"
        return 1
    fi
    
    # Run rollback
    if echo "$rollback_script" | psql "$SUPABASE_DB_URL"; then
        echo "Rollback of $file completed successfully"
        return 0
    else
        echo "Error: Rollback of $file failed"
        return 1
    fi
}

# Create schema_versions table if it doesn't exist
psql "$SUPABASE_DB_URL" << EOF
CREATE TABLE IF NOT EXISTS schema_versions (
    version INTEGER PRIMARY KEY,
    description TEXT NOT NULL,
    applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
EOF

# Process command line arguments
case "${2:-up}" in
    "up")
        # Run all migrations in order
        for file in migrations/[0-9]*.sql; do
            if [ -f "$file" ]; then
                if ! run_migration "$file"; then
                    echo "Migration process failed"
                    exit 1
                fi
            fi
        done
        echo "All migrations completed successfully"
        ;;
        
    "down")
        # Rollback last migration
        last_version=$(psql "$SUPABASE_DB_URL" -t -c "SELECT MAX(version) FROM schema_versions;")
        if [ -z "$last_version" ]; then
            echo "No migrations to roll back"
            exit 0
        fi
        
        file="migrations/$(printf "%03d" "$last_version")_*.sql"
        if [ -f "$file" ]; then
            if ! rollback_migration "$file"; then
                echo "Rollback failed"
                exit 1
            fi
        else
            echo "Migration file not found: $file"
            exit 1
        fi
        echo "Rollback completed successfully"
        ;;
        
    "reset")
        # Rollback all migrations in reverse order
        while true; do
            last_version=$(psql "$SUPABASE_DB_URL" -t -c "SELECT MAX(version) FROM schema_versions;")
            if [ -z "$last_version" ]; then
                break
            fi
            
            file="migrations/$(printf "%03d" "$last_version")_*.sql"
            if [ -f "$file" ]; then
                if ! rollback_migration "$file"; then
                    echo "Reset failed"
                    exit 1
                fi
            else
                echo "Migration file not found: $file"
                exit 1
            fi
        done
        echo "Reset completed successfully"
        ;;
        
    "status")
        # Show migration status
        echo "Applied migrations:"
        psql "$SUPABASE_DB_URL" -c "SELECT version, description, applied_at FROM schema_versions ORDER BY version;"
        
        echo -e "\nPending migrations:"
        for file in migrations/[0-9]*.sql; do
            if [ -f "$file" ]; then
                version=$(basename "$file" | cut -d'_' -f1)
                if ! psql "$SUPABASE_DB_URL" -t -c "SELECT version FROM schema_versions WHERE version = $version;" | grep -q "$version"; then
                    echo "$file"
                fi
            fi
        done
        ;;
        
    *)
        echo "Usage: $0 [environment] [up|down|reset|status]"
        exit 1
        ;;
esac

exit 0
