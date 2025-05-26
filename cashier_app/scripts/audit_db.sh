#!/bin/bash

# Database audit script
# Usage: ./audit_db.sh [environment] [operation]
# Example: ./audit_db.sh development activity

# Set environment
ENV=${1:-development}
echo "Running database audit in $ENV environment"

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

# Create audit logs directory
AUDIT_DIR="../logs/audit"
mkdir -p "$AUDIT_DIR"

# Function to log audit operations
log_audit() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$AUDIT_DIR/audit.log"
}

# Function to setup audit triggers
setup_audit() {
    echo "Setting up audit triggers..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Create audit tables if they don't exist
    CREATE TABLE IF NOT EXISTS audit_log (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        table_name TEXT NOT NULL,
        operation TEXT NOT NULL,
        old_data JSONB,
        new_data JSONB,
        changed_by TEXT,
        changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    );
    
    -- Create audit function
    CREATE OR REPLACE FUNCTION audit_trigger_func()
    RETURNS TRIGGER AS \$\$
    DECLARE
        old_data JSONB;
        new_data JSONB;
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            old_data = row_to_json(OLD)::JSONB;
            new_data = NULL;
        ELSIF (TG_OP = 'UPDATE') THEN
            old_data = row_to_json(OLD)::JSONB;
            new_data = row_to_json(NEW)::JSONB;
        ELSIF (TG_OP = 'INSERT') THEN
            old_data = NULL;
            new_data = row_to_json(NEW)::JSONB;
        END IF;
    
        INSERT INTO audit_log (
            table_name,
            operation,
            old_data,
            new_data,
            changed_by
        ) VALUES (
            TG_TABLE_NAME,
            TG_OP,
            old_data,
            new_data,
            current_user
        );
    
        RETURN NULL;
    END;
    \$\$ LANGUAGE plpgsql;
    
    -- Create triggers for each table
    DO \$\$
    DECLARE
        t text;
    BEGIN
        FOR t IN 
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public'
            AND table_type = 'BASE TABLE'
            AND table_name NOT LIKE 'audit_%'
        LOOP
            EXECUTE format('DROP TRIGGER IF EXISTS audit_trigger ON %I', t);
            EXECUTE format('
                CREATE TRIGGER audit_trigger
                AFTER INSERT OR UPDATE OR DELETE ON %I
                FOR EACH ROW EXECUTE FUNCTION audit_trigger_func()
            ', t);
        END LOOP;
    END;
    \$\$;
EOF
    
    log_audit "setup" "success" "Audit triggers created"
    echo "Audit triggers setup completed"
}

# Function to analyze user activity
analyze_activity() {
    echo "Analyzing user activity..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Recent activity by table
    SELECT 
        table_name,
        operation,
        COUNT(*) as count,
        MIN(changed_at) as first_change,
        MAX(changed_at) as last_change
    FROM audit_log
    WHERE changed_at > NOW() - INTERVAL '24 hours'
    GROUP BY table_name, operation
    ORDER BY table_name, operation;
    
    -- Most active users
    SELECT 
        changed_by,
        COUNT(*) as operations,
        COUNT(DISTINCT table_name) as tables_affected
    FROM audit_log
    WHERE changed_at > NOW() - INTERVAL '24 hours'
    GROUP BY changed_by
    ORDER BY operations DESC
    LIMIT 10;
    
    -- Most modified tables
    SELECT 
        table_name,
        COUNT(*) as changes,
        COUNT(DISTINCT changed_by) as users
    FROM audit_log
    WHERE changed_at > NOW() - INTERVAL '24 hours'
    GROUP BY table_name
    ORDER BY changes DESC
    LIMIT 10;
EOF
}

# Function to analyze schema changes
analyze_schema() {
    echo "Analyzing schema changes..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Compare current schema with last known state
    SELECT 
        c.table_name,
        c.column_name,
        c.data_type,
        c.character_maximum_length,
        c.is_nullable
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
    ORDER BY c.table_name, c.ordinal_position;
    
    -- List indexes
    SELECT
        schemaname,
        tablename,
        indexname,
        indexdef
    FROM pg_indexes
    WHERE schemaname = 'public'
    ORDER BY tablename, indexname;
    
    -- List constraints
    SELECT
        tc.table_name,
        tc.constraint_name,
        tc.constraint_type,
        kcu.column_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
    WHERE tc.table_schema = 'public'
    ORDER BY tc.table_name, tc.constraint_name;
EOF
}

# Function to analyze data changes
analyze_changes() {
    echo "Analyzing data changes..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Recent deletions
    SELECT 
        table_name,
        old_data,
        changed_by,
        changed_at
    FROM audit_log
    WHERE operation = 'DELETE'
    AND changed_at > NOW() - INTERVAL '24 hours'
    ORDER BY changed_at DESC
    LIMIT 10;
    
    -- Most frequently updated records
    WITH updates AS (
        SELECT 
            table_name,
            new_data->>'id' as record_id,
            COUNT(*) as update_count
        FROM audit_log
        WHERE operation = 'UPDATE'
        AND changed_at > NOW() - INTERVAL '24 hours'
        GROUP BY table_name, new_data->>'id'
    )
    SELECT *
    FROM updates
    ORDER BY update_count DESC
    LIMIT 10;
    
    -- Suspicious activity (multiple operations in short time)
    SELECT 
        changed_by,
        table_name,
        operation,
        COUNT(*) as operation_count,
        MIN(changed_at) as first_operation,
        MAX(changed_at) as last_operation
    FROM audit_log
    WHERE changed_at > NOW() - INTERVAL '1 hour'
    GROUP BY changed_by, table_name, operation
    HAVING COUNT(*) > 100
    ORDER BY operation_count DESC;
EOF
}

# Function to generate audit report
generate_report() {
    local report_file="$AUDIT_DIR/audit_report_$(date '+%Y%m%d_%H%M%S').txt"
    
    {
        echo "Database Audit Report"
        echo "===================="
        echo "Environment: $ENV"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo
        
        echo "1. User Activity"
        echo "---------------"
        analyze_activity
        echo
        
        echo "2. Schema Changes"
        echo "----------------"
        analyze_schema
        echo
        
        echo "3. Data Changes"
        echo "--------------"
        analyze_changes
        
    } > "$report_file"
    
    echo "Report generated: $report_file"
}

# Process commands
case "${2:-report}" in
    "setup")
        setup_audit
        ;;
        
    "activity")
        analyze_activity
        ;;
        
    "schema")
        analyze_schema
        ;;
        
    "changes")
        analyze_changes
        ;;
        
    "report")
        generate_report
        ;;
        
    *)
        echo "Usage: $0 [environment] [setup|activity|schema|changes|report]"
        exit 1
        ;;
esac

exit 0
