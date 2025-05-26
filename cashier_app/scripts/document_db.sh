#!/bin/bash

# Database documentation script
# Usage: ./document_db.sh [environment] [operation]
# Example: ./document_db.sh development schema

# Set environment
ENV=${1:-development}
echo "Generating database documentation for $ENV environment"

# Load environment variables
if [ -f "../.env.$ENV" ]; then
    source "../.env.$ENV"
else
    echo "Error: Environment file .env.$ENV not found"
    exit 1
fi

# Create documentation directory
DOC_DIR="../docs/database"
mkdir -p "$DOC_DIR"

# Function to log documentation operations
log_doc() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$DOC_DIR/documentation.log"
}

# Function to generate schema documentation
generate_schema() {
    echo "Generating schema documentation..."
    
    local schema_file="$DOC_DIR/schema.md"
    
    {
        echo "# Database Schema Documentation"
        echo "Generated on: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Environment: $ENV"
        echo
        echo "## Tables"
        echo
        
        # Get list of tables
        psql "$SUPABASE_DB_URL" -t -c "
            SELECT tablename 
            FROM pg_tables 
            WHERE schemaname = 'public'
            ORDER BY tablename;
        " | while read -r table; do
            if [ ! -z "$table" ]; then
                table=$(echo "$table" | xargs)  # Trim whitespace
                echo "### $table"
                echo
                echo "#### Columns"
                echo
                echo "| Column | Type | Nullable | Default | Description |"
                echo "|--------|------|----------|----------|-------------|"
                
                # Get column information
                psql "$SUPABASE_DB_URL" -t -c "
                    SELECT 
                        column_name,
                        data_type,
                        is_nullable,
                        column_default,
                        (
                            SELECT description 
                            FROM pg_description 
                            JOIN pg_class ON pg_description.objoid = pg_class.oid 
                            JOIN pg_attribute ON pg_attribute.attrelid = pg_class.oid 
                            WHERE pg_attribute.attname = columns.column_name 
                            AND pg_class.relname = columns.table_name
                            LIMIT 1
                        ) as description
                    FROM information_schema.columns
                    WHERE table_name = '$table'
                    ORDER BY ordinal_position;
                " | while read -r line; do
                    if [ ! -z "$line" ]; then
                        IFS='|' read -r col type null def desc <<< "$line"
                        echo "| $col | $type | $null | ${def:-None} | ${desc:-} |"
                    fi
                done
                
                echo
                echo "#### Indexes"
                echo
                echo "| Name | Columns | Type | Definition |"
                echo "|------|---------|------|------------|"
                
                # Get index information
                psql "$SUPABASE_DB_URL" -t -c "
                    SELECT
                        indexname,
                        string_agg(attname, ', ') as columns,
                        indexdef
                    FROM pg_indexes
                    JOIN pg_attribute ON attrelid = (
                        SELECT oid FROM pg_class WHERE relname = '$table'
                    )
                    WHERE tablename = '$table'
                    GROUP BY indexname, indexdef;
                " | while read -r line; do
                    if [ ! -z "$line" ]; then
                        IFS='|' read -r name cols def <<< "$line"
                        type=$(echo "$def" | grep -o 'USING [a-z]\+' || echo 'btree')
                        echo "| $name | $cols | $type | $def |"
                    fi
                done
                
                echo
                echo "#### Constraints"
                echo
                echo "| Name | Type | Definition |"
                echo "|------|------|------------|"
                
                # Get constraint information
                psql "$SUPABASE_DB_URL" -t -c "
                    SELECT
                        conname,
                        contype,
                        pg_get_constraintdef(oid)
                    FROM pg_constraint
                    WHERE conrelid = '$table'::regclass;
                " | while read -r line; do
                    if [ ! -z "$line" ]; then
                        IFS='|' read -r name type def <<< "$line"
                        echo "| $name | $type | $def |"
                    fi
                done
                
                echo
            fi
        done
        
        echo "## Relationships"
        echo
        echo "| Table | Column | References |"
        echo "|-------|---------|------------|"
        
        # Get foreign key relationships
        psql "$SUPABASE_DB_URL" -t -c "
            SELECT
                tc.table_name,
                kcu.column_name,
                ccu.table_name AS foreign_table_name,
                ccu.column_name AS foreign_column_name
            FROM information_schema.table_constraints AS tc
            JOIN information_schema.key_column_usage AS kcu
                ON tc.constraint_name = kcu.constraint_name
                AND tc.table_schema = kcu.table_schema
            JOIN information_schema.constraint_column_usage AS ccu
                ON ccu.constraint_name = tc.constraint_name
                AND ccu.table_schema = tc.table_schema
            WHERE tc.constraint_type = 'FOREIGN KEY'
            ORDER BY tc.table_name;
        " | while read -r line; do
            if [ ! -z "$line" ]; then
                IFS='|' read -r table col ftable fcol <<< "$line"
                echo "| $table | $col | $ftable($fcol) |"
            fi
        done
        
    } > "$schema_file"
    
    log_doc "schema" "success" "Generated schema documentation"
    echo "Schema documentation generated: $schema_file"
}

# Function to generate ERD
generate_erd() {
    echo "Generating Entity Relationship Diagram..."
    
    local erd_file="$DOC_DIR/erd.dot"
    local erd_png="$DOC_DIR/erd.png"
    
    {
        echo "digraph database_erd {"
        echo "  rankdir=LR;"
        echo "  node [shape=record];"
        
        # Generate nodes for tables
        psql "$SUPABASE_DB_URL" -t -c "
            SELECT tablename 
            FROM pg_tables 
            WHERE schemaname = 'public'
            ORDER BY tablename;
        " | while read -r table; do
            if [ ! -z "$table" ]; then
                table=$(echo "$table" | xargs)
                echo "  $table [label=\"{$table|"
                
                # Get columns
                psql "$SUPABASE_DB_URL" -t -c "
                    SELECT column_name, data_type
                    FROM information_schema.columns
                    WHERE table_name = '$table'
                    ORDER BY ordinal_position;
                " | while read -r line; do
                    if [ ! -z "$line" ]; then
                        IFS='|' read -r col type <<< "$line"
                        echo "$col : $type\\l"
                    fi
                done
                
                echo "}\"];"
            fi
        done
        
        # Generate edges for relationships
        psql "$SUPABASE_DB_URL" -t -c "
            SELECT
                tc.table_name,
                kcu.column_name,
                ccu.table_name AS foreign_table_name,
                ccu.column_name AS foreign_column_name
            FROM information_schema.table_constraints AS tc
            JOIN information_schema.key_column_usage AS kcu
                ON tc.constraint_name = kcu.constraint_name
                AND tc.table_schema = kcu.table_schema
            JOIN information_schema.constraint_column_usage AS ccu
                ON ccu.constraint_name = tc.constraint_name
                AND ccu.table_schema = tc.table_schema
            WHERE tc.constraint_type = 'FOREIGN KEY'
            ORDER BY tc.table_name;
        " | while read -r line; do
            if [ ! -z "$line" ]; then
                IFS='|' read -r table col ftable fcol <<< "$line"
                echo "  $table -> $ftable [label=\"$col -> $fcol\"];"
            fi
        done
        
        echo "}"
        
    } > "$erd_file"
    
    # Generate PNG if graphviz is installed
    if command -v dot &> /dev/null; then
        dot -Tpng "$erd_file" -o "$erd_png"
        log_doc "erd" "success" "Generated ERD diagram"
        echo "ERD generated: $erd_png"
    else
        log_doc "erd" "warning" "Graphviz not installed, only DOT file generated"
        echo "ERD DOT file generated: $erd_file (install graphviz to generate PNG)"
    fi
}

# Function to generate query documentation
generate_queries() {
    echo "Generating query documentation..."
    
    local queries_file="$DOC_DIR/queries.md"
    
    {
        echo "# Database Queries Documentation"
        echo "Generated on: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Environment: $ENV"
        echo
        
        echo "## Common Queries"
        echo
        
        # Document functions
        echo "### Functions"
        echo
        psql "$SUPABASE_DB_URL" -t -c "
            SELECT 
                p.proname as function_name,
                pg_get_function_arguments(p.oid) as arguments,
                pg_get_function_result(p.oid) as return_type,
                d.description
            FROM pg_proc p
            LEFT JOIN pg_description d ON p.oid = d.objoid
            WHERE p.pronamespace = 'public'::regnamespace
            ORDER BY p.proname;
        " | while read -r line; do
            if [ ! -z "$line" ]; then
                IFS='|' read -r name args ret desc <<< "$line"
                echo "#### $name"
                echo
                echo "Arguments: \`$args\`"
                echo
                echo "Returns: \`$ret\`"
                echo
                if [ ! -z "$desc" ]; then
                    echo "Description: $desc"
                    echo
                fi
            fi
        done
        
        # Document views
        echo "### Views"
        echo
        psql "$SUPABASE_DB_URL" -t -c "
            SELECT 
                viewname,
                definition
            FROM pg_views
            WHERE schemaname = 'public'
            ORDER BY viewname;
        " | while read -r line; do
            if [ ! -z "$line" ]; then
                IFS='|' read -r name def <<< "$line"
                echo "#### $name"
                echo
                echo "\`\`\`sql"
                echo "$def"
                echo "\`\`\`"
                echo
            fi
        done
        
    } > "$queries_file"
    
    log_doc "queries" "success" "Generated query documentation"
    echo "Query documentation generated: $queries_file"
}

# Function to generate permissions documentation
generate_permissions() {
    echo "Generating permissions documentation..."
    
    local perms_file="$DOC_DIR/permissions.md"
    
    {
        echo "# Database Permissions Documentation"
        echo "Generated on: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Environment: $ENV"
        echo
        
        echo "## Roles"
        echo
        echo "| Role | Attributes | Member of |"
        echo "|------|------------|-----------|"
        
        psql "$SUPABASE_DB_URL" -t -c "
            SELECT 
                r.rolname,
                ARRAY(
                    SELECT b.rolname 
                    FROM pg_auth_members m 
                    JOIN pg_roles b ON (m.roleid = b.oid) 
                    WHERE m.member = r.oid
                ) as member_of,
                ARRAY(
                    SELECT unnest(ARRAY[
                        CASE WHEN r.rolsuper THEN 'SUPERUSER' END,
                        CASE WHEN r.rolinherit THEN 'INHERIT' END,
                        CASE WHEN r.rolcreaterole THEN 'CREATEROLE' END,
                        CASE WHEN r.rolcreatedb THEN 'CREATEDB' END,
                        CASE WHEN r.rolcanlogin THEN 'LOGIN' END,
                        CASE WHEN r.rolreplication THEN 'REPLICATION' END
                    ])
                ) as attributes
            FROM pg_roles r
            WHERE r.rolname !~ '^pg_';
        " | while read -r line; do
            if [ ! -z "$line" ]; then
                IFS='|' read -r name attrs members <<< "$line"
                echo "| $name | ${attrs:-None} | ${members:-None} |"
            fi
        done
        
        echo
        echo "## Table Permissions"
        echo
        
        psql "$SUPABASE_DB_URL" -t -c "
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
        " | while read -r line; do
            if [ ! -z "$line" ]; then
                IFS='|' read -r schema table owner privs grantee <<< "$line"
                echo "### $table"
                echo
                echo "Owner: $owner"
                echo
                echo "| Grantee | Privileges |"
                echo "|---------|------------|"
                echo "| $grantee | $privs |"
                echo
            fi
        done
        
        echo "## Row Level Security Policies"
        echo
        
        psql "$SUPABASE_DB_URL" -t -c "
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
        " | while read -r line; do
            if [ ! -z "$line" ]; then
                IFS='|' read -r schema table name roles cmd qual <<< "$line"
                echo "### $table - $name"
                echo
                echo "Command: $cmd"
                echo
                echo "Roles: $roles"
                echo
                echo "Using:"
                echo "\`\`\`sql"
                echo "$qual"
                echo "\`\`\`"
                echo
            fi
        done
        
    } > "$perms_file"
    
    log_doc "permissions" "success" "Generated permissions documentation"
    echo "Permissions documentation generated: $perms_file"
}

# Function to generate full documentation
generate_all() {
    generate_schema
    generate_erd
    generate_queries
    generate_permissions
    
    # Generate index file
    local index_file="$DOC_DIR/index.md"
    
    {
        echo "# Database Documentation"
        echo "Generated on: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Environment: $ENV"
        echo
        echo "## Contents"
        echo
        echo "1. [Schema Documentation](schema.md)"
        echo "2. [Entity Relationship Diagram](erd.png)"
        echo "3. [Query Documentation](queries.md)"
        echo "4. [Permissions Documentation](permissions.md)"
        
    } > "$index_file"
    
    log_doc "all" "success" "Generated complete documentation"
    echo "Documentation index generated: $index_file"
}

# Process commands
case "${2:-all}" in
    "schema")
        generate_schema
        ;;
        
    "erd")
        generate_erd
        ;;
        
    "queries")
        generate_queries
        ;;
        
    "permissions")
        generate_permissions
        ;;
        
    "all")
        generate_all
        ;;
        
    *)
        echo "Usage: $0 [environment] [schema|erd|queries|permissions|all]"
        exit 1
        ;;
esac

exit 0
