#!/bin/bash

# Database seeder script
# Usage: ./run_seeder.sh [environment]
# Example: ./run_seeder.sh development

# Set environment
ENV=${1:-development}
echo "Running seeder for $ENV environment"

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

# Function to check if database is empty
check_empty_db() {
    local count=$(psql "$SUPABASE_DB_URL" -t -c "
        SELECT COUNT(*) 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_type = 'BASE TABLE'
        AND table_name IN ('users', 'stores', 'products');")
    
    if [ "$count" -eq "3" ]; then
        local data_count=$(psql "$SUPABASE_DB_URL" -t -c "
            SELECT (SELECT COUNT(*) FROM users) +
                   (SELECT COUNT(*) FROM stores) +
                   (SELECT COUNT(*) FROM products);")
        
        if [ "$data_count" -eq "0" ]; then
            return 0
        fi
    fi
    return 1
}

# Function to run seeder
run_seeder() {
    echo "Running database seeder..."
    
    if psql "$SUPABASE_DB_URL" -f "seed_db.sql"; then
        echo "Seeder completed successfully"
        return 0
    else
        echo "Error: Seeder failed"
        return 1
    fi
}

# Function to clear database
clear_database() {
    echo "Clearing database..."
    
    psql "$SUPABASE_DB_URL" << EOF
    DO \$\$
    DECLARE
        r RECORD;
    BEGIN
        -- Disable all triggers
        FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
            EXECUTE 'ALTER TABLE ' || quote_ident(r.tablename) || ' DISABLE TRIGGER ALL';
        END LOOP;

        -- Truncate all tables
        FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
            EXECUTE 'TRUNCATE TABLE ' || quote_ident(r.tablename) || ' CASCADE';
        END LOOP;

        -- Enable all triggers
        FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
            EXECUTE 'ALTER TABLE ' || quote_ident(r.tablename) || ' ENABLE TRIGGER ALL';
        END LOOP;
    END \$\$;
EOF

    if [ $? -eq 0 ]; then
        echo "Database cleared successfully"
        return 0
    else
        echo "Error: Failed to clear database"
        return 1
    fi
}

# Process command line arguments
case "${2:-seed}" in
    "seed")
        if ! check_empty_db; then
            read -p "Database is not empty. Do you want to clear it first? (y/N) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if ! clear_database; then
                    exit 1
                fi
            else
                echo "Seeding cancelled"
                exit 0
            fi
        fi
        
        if ! run_seeder; then
            exit 1
        fi
        ;;
        
    "clear")
        read -p "Are you sure you want to clear the database? This action cannot be undone. (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if ! clear_database; then
                exit 1
            fi
        else
            echo "Clear operation cancelled"
            exit 0
        fi
        ;;
        
    "refresh")
        if ! clear_database; then
            exit 1
        fi
        
        if ! run_seeder; then
            exit 1
        fi
        ;;
        
    "status")
        if check_empty_db; then
            echo "Database is empty"
        else
            echo "Database contains data"
            
            # Show table counts
            echo -e "\nTable counts:"
            psql "$SUPABASE_DB_URL" -c "
                SELECT 
                    table_name, 
                    (SELECT COUNT(*) FROM \"$table_name\") as count
                FROM information_schema.tables 
                WHERE table_schema = 'public' 
                AND table_type = 'BASE TABLE'
                ORDER BY table_name;"
        fi
        ;;
        
    *)
        echo "Usage: $0 [environment] [seed|clear|refresh|status]"
        exit 1
        ;;
esac

exit 0
