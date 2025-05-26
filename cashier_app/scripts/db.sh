#!/bin/bash

# Database management script
# Usage: ./db.sh [environment] [command] [options]
# Example: ./db.sh development setup

# Set environment
ENV=${1:-development}
echo "Running database operations for $ENV environment"

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

# Create logs directory
LOG_DIR="../logs/db"
mkdir -p "$LOG_DIR"

# Function to log operations
log_operation() {
    local command=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $command: $status - $message" >> "$LOG_DIR/operations.log"
}

# Function to check if script exists
check_script() {
    local script=$1
    if [ ! -f "$script" ]; then
        echo "Error: Script not found: $script"
        return 1
    fi
    return 0
}

# Function to make script executable
make_executable() {
    local script=$1
    if [ ! -x "$script" ]; then
        chmod +x "$script"
    fi
}

# Function to run a script
run_script() {
    local script=$1
    shift
    local args=("$@")
    
    if ! check_script "$script"; then
        return 1
    fi
    
    make_executable "$script"
    
    if "./$script" "$ENV" "${args[@]}"; then
        return 0
    else
        return 1
    fi
}

# Show help message
show_help() {
    cat << EOF
Database Management Script

Usage: ./db.sh [environment] [command] [options]

Environments:
  development    Development environment (default)
  staging        Staging environment
  production    Production environment

Commands:
  setup         Initialize database with schema
  migrate       Run database migrations
  seed          Seed database with test data
  backup        Create database backup
  restore       Restore database from backup
  maintain      Run database maintenance
  reset         Reset database (drop and recreate)
  status        Show database status
  help          Show this help message

Examples:
  ./db.sh development setup
  ./db.sh production backup
  ./db.sh staging migrate
EOF
}

# Process commands
case "${2:-help}" in
    "setup")
        echo "Setting up database..."
        if run_script "setup_db.sql"; then
            log_operation "setup" "success" "Database setup completed"
        else
            log_operation "setup" "error" "Database setup failed"
            exit 1
        fi
        ;;
        
    "migrate")
        echo "Running migrations..."
        if run_script "run_migrations.sh" "${@:3}"; then
            log_operation "migrate" "success" "Migrations completed"
        else
            log_operation "migrate" "error" "Migrations failed"
            exit 1
        fi
        ;;
        
    "seed")
        echo "Seeding database..."
        if run_script "run_seeder.sh" "${@:3}"; then
            log_operation "seed" "success" "Database seeding completed"
        else
            log_operation "seed" "error" "Database seeding failed"
            exit 1
        fi
        ;;
        
    "backup")
        echo "Creating backup..."
        if run_script "backup_db.sh" "${@:3}"; then
            log_operation "backup" "success" "Backup completed"
        else
            log_operation "backup" "error" "Backup failed"
            exit 1
        fi
        ;;
        
    "restore")
        echo "Restoring database..."
        if run_script "backup_db.sh" "restore" "${@:3}"; then
            log_operation "restore" "success" "Restore completed"
        else
            log_operation "restore" "error" "Restore failed"
            exit 1
        fi
        ;;
        
    "maintain")
        echo "Running maintenance..."
        if run_script "maintain_db.sh" "${@:3}"; then
            log_operation "maintain" "success" "Maintenance completed"
        else
            log_operation "maintain" "error" "Maintenance failed"
            exit 1
        fi
        ;;
        
    "reset")
        echo "Resetting database..."
        read -p "Are you sure you want to reset the database? This will delete all data. (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Drop and recreate database
            if psql "$SUPABASE_DB_URL" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"; then
                # Run setup
                if run_script "setup_db.sql"; then
                    # Run migrations
                    if run_script "run_migrations.sh" "up"; then
                        log_operation "reset" "success" "Database reset completed"
                    else
                        log_operation "reset" "error" "Database reset failed at migrations"
                        exit 1
                    fi
                else
                    log_operation "reset" "error" "Database reset failed at setup"
                    exit 1
                fi
            else
                log_operation "reset" "error" "Database reset failed at schema drop"
                exit 1
            fi
        else
            echo "Reset cancelled"
            exit 0
        fi
        ;;
        
    "status")
        echo "Database Status"
        echo "--------------"
        
        # Check connection
        if psql "$SUPABASE_DB_URL" -c "SELECT version();"; then
            echo -e "\nMigration Status:"
            run_script "run_migrations.sh" "status"
            
            echo -e "\nDatabase Size and Statistics:"
            run_script "maintain_db.sh" "status"
            
            echo -e "\nBackup Status:"
            run_script "backup_db.sh" "list"
            
            log_operation "status" "success" "Status check completed"
        else
            log_operation "status" "error" "Could not connect to database"
            exit 1
        fi
        ;;
        
    "help")
        show_help
        ;;
        
    *)
        echo "Unknown command: ${2:-}"
        show_help
        exit 1
        ;;
esac

exit 0
