#!/bin/bash

# Database security script
# Usage: ./secure_db.sh [environment] [operation]
# Example: ./secure_db.sh development audit

# Set environment
ENV=${1:-development}
echo "Running database security operations in $ENV environment"

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

# Create security logs directory
SECURITY_DIR="../logs/security"
mkdir -p "$SECURITY_DIR"

# Function to log security operations
log_security() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$SECURITY_DIR/security.log"
}

# Function to audit security settings
audit_security() {
    echo "Auditing database security settings..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Check database roles and permissions
    SELECT 
        r.rolname, 
        r.rolsuper, 
        r.rolinherit,
        r.rolcreaterole,
        r.rolcreatedb,
        r.rolcanlogin,
        r.rolreplication,
        r.rolconnlimit,
        r.rolvaliduntil
    FROM pg_roles r
    ORDER BY rolname;
    
    -- Check table permissions
    SELECT 
        schemaname,
        tablename,
        tableowner,
        array_agg(privilege_type) as privileges,
        grantee
    FROM information_schema.table_privileges
    WHERE table_schema = 'public'
    GROUP BY schemaname, tablename, tableowner, grantee
    ORDER BY schemaname, tablename;
    
    -- Check active connections
    SELECT 
        datname,
        usename,
        application_name,
        client_addr,
        backend_start,
        state,
        query
    FROM pg_stat_activity
    WHERE datname = current_database();
    
    -- Check Row Level Security policies
    SELECT 
        schemaname,
        tablename,
        polname,
        roles,
        cmd,
        qual
    FROM pg_policies
    WHERE schemaname = 'public'
    ORDER BY tablename, polname;
EOF
}

# Function to setup security policies
setup_policies() {
    echo "Setting up security policies..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Enable Row Level Security on all tables
    DO \$\$
    DECLARE
        t text;
    BEGIN
        FOR t IN 
            SELECT tablename 
            FROM pg_tables 
            WHERE schemaname = 'public'
        LOOP
            EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
        END LOOP;
    END;
    \$\$;
    
    -- Setup RLS policies for users table
    CREATE POLICY "Users can view their own data" ON users
        FOR SELECT
        USING (auth.uid() = id);
        
    CREATE POLICY "Users can update their own data" ON users
        FOR UPDATE
        USING (auth.uid() = id);
    
    -- Setup RLS policies for stores table
    CREATE POLICY "Users can view stores they belong to" ON stores
        FOR SELECT
        USING (
            EXISTS (
                SELECT 1 FROM store_users
                WHERE store_users.store_id = id
                AND store_users.user_id = auth.uid()
            )
        );
    
    CREATE POLICY "Store owners can manage their stores" ON stores
        FOR ALL
        USING (
            EXISTS (
                SELECT 1 FROM store_users
                WHERE store_users.store_id = id
                AND store_users.user_id = auth.uid()
                AND store_users.role = 'owner'
            )
        );
    
    -- Setup RLS policies for products table
    CREATE POLICY "Users can view products of their stores" ON products
        FOR SELECT
        USING (
            EXISTS (
                SELECT 1 FROM store_users
                WHERE store_users.store_id = store_id
                AND store_users.user_id = auth.uid()
            )
        );
    
    CREATE POLICY "Managers can manage products" ON products
        FOR ALL
        USING (
            EXISTS (
                SELECT 1 FROM store_users
                WHERE store_users.store_id = store_id
                AND store_users.user_id = auth.uid()
                AND store_users.role IN ('owner', 'manager')
            )
        );
EOF
    
    log_security "policies" "success" "Security policies configured"
    echo "Security policies setup completed"
}

# Function to manage access controls
manage_access() {
    echo "Managing access controls..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Revoke public access
    REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
    REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
    REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
    
    -- Grant access to authenticated users
    GRANT USAGE ON SCHEMA public TO authenticated;
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
    GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated;
    
    -- Grant specific function access
    GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
    
    -- Create application roles if they don't exist
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_readonly') THEN
            CREATE ROLE app_readonly;
        END IF;
        
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_readwrite') THEN
            CREATE ROLE app_readwrite;
        END IF;
    END
    \$\$;
    
    -- Setup role permissions
    GRANT USAGE ON SCHEMA public TO app_readonly;
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_readonly;
    
    GRANT USAGE ON SCHEMA public TO app_readwrite;
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_readwrite;
    GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app_readwrite;
EOF
    
    log_security "access" "success" "Access controls configured"
    echo "Access control management completed"
}

# Function to setup audit logging
setup_audit() {
    echo "Setting up audit logging..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Create audit log table
    CREATE TABLE IF NOT EXISTS audit_log (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        table_name TEXT NOT NULL,
        operation TEXT NOT NULL,
        old_data JSONB,
        new_data JSONB,
        user_id UUID,
        ip_address TEXT,
        timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    );
    
    -- Create audit trigger function
    CREATE OR REPLACE FUNCTION audit_trigger_func()
    RETURNS TRIGGER AS \$\$
    DECLARE
        audit_row audit_log;
    BEGIN
        audit_row = ROW(
            uuid_generate_v4(),
            TG_TABLE_NAME,
            TG_OP,
            CASE WHEN TG_OP = 'DELETE' THEN row_to_json(OLD) ELSE NULL END,
            CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN row_to_json(NEW) ELSE NULL END,
            auth.uid(),
            inet_client_addr()::text,
            CURRENT_TIMESTAMP
        );
        
        INSERT INTO audit_log VALUES (audit_row.*);
        RETURN NULL;
    END;
    \$\$ LANGUAGE plpgsql;
    
    -- Apply audit triggers to all tables
    DO \$\$
    DECLARE
        t text;
    BEGIN
        FOR t IN 
            SELECT tablename 
            FROM pg_tables 
            WHERE schemaname = 'public'
            AND tablename != 'audit_log'
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
    
    log_security "audit" "success" "Audit logging configured"
    echo "Audit logging setup completed"
}

# Function to check for vulnerabilities
check_vulnerabilities() {
    echo "Checking for security vulnerabilities..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Check for weak passwords
    SELECT rolname, rolvaliduntil 
    FROM pg_roles 
    WHERE rolcanlogin = true 
    AND rolvaliduntil IS NULL;
    
    -- Check for public schemas
    SELECT nspname 
    FROM pg_namespace 
    WHERE nspname NOT IN ('pg_catalog', 'information_schema')
    AND has_schema_privilege('public', nspname, 'USAGE');
    
    -- Check for tables without RLS
    SELECT tablename 
    FROM pg_tables 
    WHERE schemaname = 'public' 
    AND NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE schemaname = 'public' 
        AND tablename = pg_tables.tablename
    );
    
    -- Check for exposed sensitive columns
    SELECT table_schema, table_name, column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
    AND column_name IN ('password', 'secret', 'token', 'key', 'credit_card');
EOF
}

# Function to generate security report
generate_report() {
    local report_file="$SECURITY_DIR/security_report_$(date '+%Y%m%d_%H%M%S').txt"
    
    {
        echo "Database Security Report"
        echo "======================="
        echo "Environment: $ENV"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo
        
        echo "1. Security Audit"
        echo "---------------"
        audit_security
        echo
        
        echo "2. Access Control Status"
        echo "---------------------"
        manage_access
        echo
        
        echo "3. Audit Log Status"
        echo "-----------------"
        setup_audit
        echo
        
        echo "4. Vulnerability Check"
        echo "-------------------"
        check_vulnerabilities
        
    } > "$report_file"
    
    echo "Report generated: $report_file"
}

# Process commands
case "${2:-report}" in
    "audit")
        audit_security
        ;;
        
    "policies")
        setup_policies
        ;;
        
    "access")
        manage_access
        ;;
        
    "audit-log")
        setup_audit
        ;;
        
    "vulnerabilities")
        check_vulnerabilities
        ;;
        
    "report")
        generate_report
        ;;
        
    *)
        echo "Usage: $0 [environment] [audit|policies|access|audit-log|vulnerabilities|report]"
        exit 1
        ;;
esac

exit 0
