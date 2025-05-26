#!/bin/bash

# Database user management script
# Usage: ./manage_db_users.sh [environment] [operation]
# Example: ./manage_db_users.sh development create-role app_user

# Set environment
ENV=${1:-development}
echo "Managing database users for $ENV environment"

# Load environment variables
if [ -f "../.env.$ENV" ]; then
    source "../.env.$ENV"
else
    echo "Error: Environment file .env.$ENV not found"
    exit 1
fi

# Create user management logs directory
USER_DIR="../logs/users"
mkdir -p "$USER_DIR"

# Function to log user management operations
log_user_mgmt() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$USER_DIR/user_management.log"
}

# Function to create role
create_role() {
    local role_name=$1
    local role_type=${2:-standard}
    
    if [ -z "$role_name" ]; then
        echo "Error: Role name not specified"
        echo "Usage: $0 $ENV create-role <role_name> [role_type]"
        return 1
    fi
    
    echo "Creating role: $role_name (type: $role_type)..."
    
    case "$role_type" in
        "admin")
            psql "$SUPABASE_DB_URL" << EOF
            DO \$\$
            BEGIN
                IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$role_name') THEN
                    CREATE ROLE $role_name WITH
                        LOGIN
                        PASSWORD '${role_name}_$(openssl rand -base64 12)'
                        SUPERUSER
                        CREATEDB
                        CREATEROLE
                        REPLICATION;
                    RAISE NOTICE 'Created admin role: $role_name';
                ELSE
                    RAISE NOTICE 'Role already exists: $role_name';
                END IF;
            END
            \$\$;
EOF
            ;;
            
        "readonly")
            psql "$SUPABASE_DB_URL" << EOF
            DO \$\$
            BEGIN
                IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$role_name') THEN
                    CREATE ROLE $role_name WITH
                        LOGIN
                        PASSWORD '${role_name}_$(openssl rand -base64 12)'
                        NOSUPERUSER
                        NOCREATEDB
                        NOCREATEROLE
                        NOREPLICATION;
                        
                    -- Grant read-only access to all tables
                    GRANT CONNECT ON DATABASE ${SUPABASE_DB_URL##*/} TO $role_name;
                    GRANT USAGE ON SCHEMA public TO $role_name;
                    GRANT SELECT ON ALL TABLES IN SCHEMA public TO $role_name;
                    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO $role_name;
                    
                    RAISE NOTICE 'Created read-only role: $role_name';
                ELSE
                    RAISE NOTICE 'Role already exists: $role_name';
                END IF;
            END
            \$\$;
EOF
            ;;
            
        "standard")
            psql "$SUPABASE_DB_URL" << EOF
            DO \$\$
            BEGIN
                IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$role_name') THEN
                    CREATE ROLE $role_name WITH
                        LOGIN
                        PASSWORD '${role_name}_$(openssl rand -base64 12)'
                        NOSUPERUSER
                        NOCREATEDB
                        NOCREATEROLE
                        NOREPLICATION;
                        
                    -- Grant standard access to all tables
                    GRANT CONNECT ON DATABASE ${SUPABASE_DB_URL##*/} TO $role_name;
                    GRANT USAGE ON SCHEMA public TO $role_name;
                    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO $role_name;
                    ALTER DEFAULT PRIVILEGES IN SCHEMA public 
                        GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO $role_name;
                    
                    RAISE NOTICE 'Created standard role: $role_name';
                ELSE
                    RAISE NOTICE 'Role already exists: $role_name';
                END IF;
            END
            \$\$;
EOF
            ;;
            
        *)
            echo "Error: Invalid role type. Use 'admin', 'readonly', or 'standard'"
            return 1
            ;;
    esac
    
    log_user_mgmt "create-role" "success" "Created $role_type role: $role_name"
    echo "Role created successfully"
}

# Function to modify role permissions
modify_permissions() {
    local role_name=$1
    local permission=$2
    local object_type=$3
    local object_name=$4
    
    if [ -z "$role_name" ] || [ -z "$permission" ] || [ -z "$object_type" ] || [ -z "$object_name" ]; then
        echo "Error: Missing parameters"
        echo "Usage: $0 $ENV modify-permissions <role_name> <permission> <object_type> <object_name>"
        echo "Example: $0 $ENV modify-permissions app_user SELECT TABLE users"
        return 1
    fi
    
    echo "Modifying permissions for role: $role_name..."
    
    psql "$SUPABASE_DB_URL" << EOF
    GRANT $permission ON $object_type $object_name TO $role_name;
EOF
    
    log_user_mgmt "modify-permissions" "success" "Granted $permission on $object_type $object_name to $role_name"
    echo "Permissions modified successfully"
}

# Function to revoke permissions
revoke_permissions() {
    local role_name=$1
    local permission=$2
    local object_type=$3
    local object_name=$4
    
    if [ -z "$role_name" ] || [ -z "$permission" ] || [ -z "$object_type" ] || [ -z "$object_name" ]; then
        echo "Error: Missing parameters"
        echo "Usage: $0 $ENV revoke-permissions <role_name> <permission> <object_type> <object_name>"
        return 1
    fi
    
    echo "Revoking permissions from role: $role_name..."
    
    psql "$SUPABASE_DB_URL" << EOF
    REVOKE $permission ON $object_type $object_name FROM $role_name;
EOF
    
    log_user_mgmt "revoke-permissions" "success" "Revoked $permission on $object_type $object_name from $role_name"
    echo "Permissions revoked successfully"
}

# Function to list roles and permissions
list_roles() {
    echo "Listing roles and permissions..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- List all roles
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
    WHERE r.rolname !~ '^pg_'
    ORDER BY r.rolname;
    
    -- List role memberships
    SELECT 
        pg_get_userbyid(member) as member,
        pg_get_userbyid(roleid) as granted_role
    FROM pg_auth_members;
    
    -- List table permissions
    SELECT
        grantor.rolname as grantor,
        grantee.rolname as grantee,
        table_schema,
        table_name,
        string_agg(privilege_type, ', ') as privileges
    FROM information_schema.table_privileges
    JOIN pg_roles grantor ON grantor.oid = table_privileges.grantor::regrole::oid
    JOIN pg_roles grantee ON grantee.oid = table_privileges.grantee::regrole::oid
    WHERE table_schema = 'public'
    GROUP BY grantor.rolname, grantee.rolname, table_schema, table_name
    ORDER BY table_schema, table_name, grantee.rolname;
EOF
}

# Function to rotate role password
rotate_password() {
    local role_name=$1
    
    if [ -z "$role_name" ]; then
        echo "Error: Role name not specified"
        echo "Usage: $0 $ENV rotate-password <role_name>"
        return 1
    fi
    
    echo "Rotating password for role: $role_name..."
    
    local new_password="${role_name}_$(openssl rand -base64 12)"
    
    psql "$SUPABASE_DB_URL" << EOF
    ALTER ROLE $role_name WITH PASSWORD '$new_password';
EOF
    
    # Save password to secure file
    echo "$role_name:$new_password" >> "$USER_DIR/credentials.txt"
    chmod 600 "$USER_DIR/credentials.txt"
    
    log_user_mgmt "rotate-password" "success" "Rotated password for role: $role_name"
    echo "Password rotated successfully"
}

# Function to delete role
delete_role() {
    local role_name=$1
    
    if [ -z "$role_name" ]; then
        echo "Error: Role name not specified"
        echo "Usage: $0 $ENV delete-role <role_name>"
        return 1
    fi
    
    echo "Deleting role: $role_name..."
    
    psql "$SUPABASE_DB_URL" << EOF
    DROP ROLE IF EXISTS $role_name;
EOF
    
    log_user_mgmt "delete-role" "success" "Deleted role: $role_name"
    echo "Role deleted successfully"
}

# Function to audit role activities
audit_roles() {
    echo "Auditing role activities..."
    
    local audit_file="$USER_DIR/role_audit_$(date '+%Y%m%d_%H%M%S').md"
    
    {
        echo "# Role Audit Report"
        echo "Generated on: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Environment: $ENV"
        echo
        
        echo "## Role Overview"
        echo
        psql "$SUPABASE_DB_URL" -c "
            SELECT 
                rolname,
                rolsuper,
                rolcreaterole,
                rolcreatedb,
                rolcanlogin,
                rolreplication
            FROM pg_roles
            WHERE rolname !~ '^pg_'
            ORDER BY rolname;
        "
        echo
        
        echo "## Permission Summary"
        echo
        psql "$SUPABASE_DB_URL" -c "
            SELECT 
                grantee.rolname as role,
                table_schema,
                table_name,
                string_agg(privilege_type, ', ') as privileges
            FROM information_schema.table_privileges
            JOIN pg_roles grantee ON grantee.oid = table_privileges.grantee::regrole::oid
            WHERE table_schema = 'public'
            GROUP BY grantee.rolname, table_schema, table_name
            ORDER BY role, table_schema, table_name;
        "
        echo
        
        echo "## Role Dependencies"
        echo
        psql "$SUPABASE_DB_URL" -c "
            WITH RECURSIVE role_members AS (
                SELECT 
                    member::regrole::text as member,
                    roleid::regrole::text as role,
                    1 as depth
                FROM pg_auth_members
                UNION ALL
                SELECT 
                    rm.member,
                    am.roleid::regrole::text,
                    rm.depth + 1
                FROM pg_auth_members am
                JOIN role_members rm ON rm.role = am.member::regrole::text
            )
            SELECT 
                member,
                role,
                depth
            FROM role_members
            ORDER BY member, depth, role;
        "
        
    } > "$audit_file"
    
    log_user_mgmt "audit" "success" "Generated role audit report"
    echo "Audit report generated: $audit_file"
}

# Process commands
case "${2:-list}" in
    "create-role")
        create_role "$3" "$4"
        ;;
        
    "modify-permissions")
        modify_permissions "$3" "$4" "$5" "$6"
        ;;
        
    "revoke-permissions")
        revoke_permissions "$3" "$4" "$5" "$6"
        ;;
        
    "list")
        list_roles
        ;;
        
    "rotate-password")
        rotate_password "$3"
        ;;
        
    "delete-role")
        delete_role "$3"
        ;;
        
    "audit")
        audit_roles
        ;;
        
    *)
        echo "Usage: $0 [environment] [create-role|modify-permissions|revoke-permissions|list|rotate-password|delete-role|audit] [args]"
        exit 1
        ;;
esac

exit 0
