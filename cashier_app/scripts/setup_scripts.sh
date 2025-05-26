#!/bin/bash

# Script to setup database management scripts
# Makes all scripts executable and sets up proper permissions
# Usage: ./setup_scripts.sh

# Log setup operations
log_setup() {
    local script=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $script: $status - $message"
}

# Create logs directory
mkdir -p ../logs
echo "Created logs directory"

# List of all database management scripts
SCRIPTS=(
    "db.sh"
    "setup_db.sql"
    "run_migrations.sh"
    "seed_db.sql"
    "run_seeder.sh"
    "backup_db.sh"
    "maintain_db.sh"
    "monitor_db.sh"
    "test_db.sh"
    "benchmark_db.sh"
    "cleanup_db.sh"
    "restore_db.sh"
    "audit_db.sh"
    "replicate_db.sh"
    "analyze_db.sh"
    "optimize_db.sh"
    "secure_db.sh"
)

# Make scripts executable
echo "Making scripts executable..."
for script in "${SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        chmod +x "$script"
        log_setup "$script" "success" "Made executable"
    else
        log_setup "$script" "error" "File not found"
    fi
done

# Create required directories
echo "Creating required directories..."
DIRS=(
    "../logs/backups"
    "../logs/monitoring"
    "../logs/tests"
    "../logs/benchmarks"
    "../logs/cleanup"
    "../logs/restore"
    "../logs/audit"
    "../logs/replication"
    "../logs/analytics"
    "../logs/optimization"
    "../logs/security"
)

for dir in "${DIRS[@]}"; do
    if mkdir -p "$dir"; then
        log_setup "$dir" "success" "Directory created"
    else
        log_setup "$dir" "error" "Failed to create directory"
    fi
done

# Set up symbolic links for convenience
echo "Setting up symbolic links..."
ln -sf db.sh ../db
log_setup "db symlink" "success" "Created symbolic link"

# Create environment files if they don't exist
echo "Setting up environment files..."
ENV_FILES=(
    "../.env.development"
    "../.env.staging"
    "../.env.production"
)

for env_file in "${ENV_FILES[@]}"; do
    if [ ! -f "$env_file" ]; then
        cat > "$env_file" << EOF
# Database Configuration
SUPABASE_DB_URL=postgresql://postgres:postgres@localhost:5432/cashier_app_${env_file##*.}
REPLICA_DB_URL=postgresql://postgres:postgres@localhost:5433/cashier_app_${env_file##*.}

# Backup Configuration
BACKUP_RETENTION_DAYS=30
MAX_PARALLEL_BACKUPS=3

# Monitoring Configuration
ALERT_EMAIL=admin@example.com
MONITORING_INTERVAL=5m

# Security Configuration
AUDIT_RETENTION_DAYS=90
MAX_FAILED_LOGINS=5

# Performance Configuration
MAX_CONNECTIONS=100
STATEMENT_TIMEOUT=3600000  # 1 hour in milliseconds
EOF
        log_setup "$env_file" "success" "Created environment file"
    else
        log_setup "$env_file" "info" "Environment file already exists"
    fi
done

# Create a simple README for the scripts
cat > README.md << EOF
# Database Management Scripts

This directory contains scripts for managing the Cashier App database.

## Available Scripts

- \`db.sh\`: Main database management script
- \`setup_db.sql\`: Initial database setup
- \`run_migrations.sh\`: Database migration runner
- \`seed_db.sql\`: Database seeder
- \`backup_db.sh\`: Database backup management
- \`maintain_db.sh\`: Database maintenance
- \`monitor_db.sh\`: Database monitoring
- \`test_db.sh\`: Database testing
- \`benchmark_db.sh\`: Database benchmarking
- \`cleanup_db.sh\`: Database cleanup
- \`restore_db.sh\`: Database restore
- \`audit_db.sh\`: Database auditing
- \`replicate_db.sh\`: Database replication
- \`analyze_db.sh\`: Database analytics
- \`optimize_db.sh\`: Database optimization
- \`secure_db.sh\`: Database security

## Usage

1. Run \`./setup_scripts.sh\` first to set up the environment
2. Use \`./db.sh\` as the main entry point for database operations
3. Individual scripts can be run directly for specific tasks

## Environment

- Development: \`.env.development\`
- Staging: \`.env.staging\`
- Production: \`.env.production\`

## Logs

All logs are stored in the \`../logs\` directory, organized by operation type.

## Security

Make sure to:
1. Review environment files and update credentials
2. Set proper file permissions
3. Keep logs directory secure
4. Regularly rotate log files
EOF

echo "Created README.md"

# Set restrictive permissions on environment files
echo "Setting environment file permissions..."
for env_file in "${ENV_FILES[@]}"; do
    if [ -f "$env_file" ]; then
        chmod 600 "$env_file"
        log_setup "$env_file" "success" "Set restrictive permissions"
    fi
done

# Create a log rotation configuration
cat > logrotate.conf << EOF
../logs/*/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        /usr/bin/find ../logs -name "*.gz" -mtime +30 -delete
    endscript
}
EOF

echo "Created log rotation configuration"

# Final status check
echo -e "\nSetup completed!"
echo "Run './db.sh help' for usage information"

exit 0
