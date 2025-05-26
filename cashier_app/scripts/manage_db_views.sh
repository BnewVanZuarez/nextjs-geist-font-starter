#!/bin/bash

# Database views management script
# Usage: ./manage_db_views.sh [environment] [operation]
# Example: ./manage_db_views.sh development create-view sales_summary

# Set environment
ENV=${1:-development}
echo "Managing database views for $ENV environment"

# Load environment variables
if [ -f "../.env.$ENV" ]; then
    source "../.env.$ENV"
else
    echo "Error: Environment file .env.$ENV not found"
    exit 1
fi

# Create views management logs directory
VIEW_DIR="../logs/views"
mkdir -p "$VIEW_DIR"

# Function to log view management operations
log_view() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$VIEW_DIR/views.log"
}

# Function to create view
create_view() {
    local view_name=$1
    local view_type=${2:-regular}
    
    if [ -z "$view_name" ]; then
        echo "Error: View name not specified"
        echo "Usage: $0 $ENV create-view <view_name> [regular|materialized]"
        return 1
    fi
    
    echo "Creating $view_type view: $view_name..."
    
    case "$view_name" in
        "sales_summary")
            psql "$SUPABASE_DB_URL" << EOF
            $([ "$view_type" = "materialized" ] && echo "CREATE MATERIALIZED VIEW" || echo "CREATE OR REPLACE VIEW") $view_name AS
            SELECT 
                DATE_TRUNC('day', t.created_at) as sale_date,
                s.name as store_name,
                COUNT(t.id) as transaction_count,
                SUM(t.total_amount) as total_sales,
                AVG(t.total_amount) as average_sale,
                COUNT(DISTINCT t.customer_id) as unique_customers
            FROM transactions t
            JOIN stores s ON t.store_id = s.id
            GROUP BY DATE_TRUNC('day', t.created_at), s.name;
            
            $([ "$view_type" = "materialized" ] && echo "CREATE UNIQUE INDEX ON $view_name (sale_date, store_name);")
EOF
            ;;
            
        "product_performance")
            psql "$SUPABASE_DB_URL" << EOF
            $([ "$view_type" = "materialized" ] && echo "CREATE MATERIALIZED VIEW" || echo "CREATE OR REPLACE VIEW") $view_name AS
            SELECT 
                p.id as product_id,
                p.name as product_name,
                p.category,
                COUNT(ti.id) as times_sold,
                SUM(ti.quantity) as total_quantity_sold,
                SUM(ti.price * ti.quantity) as total_revenue,
                AVG(ti.price) as average_price
            FROM products p
            LEFT JOIN transaction_items ti ON p.id = ti.product_id
            GROUP BY p.id, p.name, p.category;
            
            $([ "$view_type" = "materialized" ] && echo "CREATE UNIQUE INDEX ON $view_name (product_id);")
EOF
            ;;
            
        "customer_insights")
            psql "$SUPABASE_DB_URL" << EOF
            $([ "$view_type" = "materialized" ] && echo "CREATE MATERIALIZED VIEW" || echo "CREATE OR REPLACE VIEW") $view_name AS
            SELECT 
                c.id as customer_id,
                c.name as customer_name,
                COUNT(t.id) as total_transactions,
                SUM(t.total_amount) as total_spent,
                AVG(t.total_amount) as average_transaction_value,
                MAX(t.created_at) as last_transaction_date,
                COUNT(DISTINCT t.store_id) as visited_stores
            FROM customers c
            LEFT JOIN transactions t ON c.id = t.customer_id
            GROUP BY c.id, c.name;
            
            $([ "$view_type" = "materialized" ] && echo "CREATE UNIQUE INDEX ON $view_name (customer_id);")
EOF
            ;;
            
        "inventory_status")
            psql "$SUPABASE_DB_URL" << EOF
            $([ "$view_type" = "materialized" ] && echo "CREATE MATERIALIZED VIEW" || echo "CREATE OR REPLACE VIEW") $view_name AS
            SELECT 
                p.id as product_id,
                p.name as product_name,
                s.id as store_id,
                s.name as store_name,
                i.quantity as current_stock,
                i.min_stock_level,
                i.max_stock_level,
                CASE 
                    WHEN i.quantity <= i.min_stock_level THEN 'Low'
                    WHEN i.quantity >= i.max_stock_level THEN 'Excess'
                    ELSE 'Normal'
                END as stock_status
            FROM products p
            JOIN inventory i ON p.id = i.product_id
            JOIN stores s ON i.store_id = s.id;
            
            $([ "$view_type" = "materialized" ] && echo "CREATE UNIQUE INDEX ON $view_name (product_id, store_id);")
EOF
            ;;
            
        *)
            echo "Error: Unknown view template. Available templates: sales_summary, product_performance, customer_insights, inventory_status"
            return 1
            ;;
    esac
    
    log_view "create" "success" "Created $view_type view: $view_name"
    echo "View created successfully"
}

# Function to refresh materialized view
refresh_view() {
    local view_name=$1
    local concurrently=${2:-false}
    
    if [ -z "$view_name" ]; then
        echo "Error: View name not specified"
        echo "Usage: $0 $ENV refresh-view <view_name> [true|false]"
        return 1
    fi
    
    echo "Refreshing materialized view: $view_name..."
    
    if [ "$concurrently" = "true" ]; then
        psql "$SUPABASE_DB_URL" -c "REFRESH MATERIALIZED VIEW CONCURRENTLY $view_name;"
    else
        psql "$SUPABASE_DB_URL" -c "REFRESH MATERIALIZED VIEW $view_name;"
    fi
    
    log_view "refresh" "success" "Refreshed materialized view: $view_name"
    echo "View refreshed successfully"
}

# Function to drop view
drop_view() {
    local view_name=$1
    local view_type=${2:-regular}
    
    if [ -z "$view_name" ]; then
        echo "Error: View name not specified"
        echo "Usage: $0 $ENV drop-view <view_name> [regular|materialized]"
        return 1
    fi
    
    echo "Dropping $view_type view: $view_name..."
    
    if [ "$view_type" = "materialized" ]; then
        psql "$SUPABASE_DB_URL" -c "DROP MATERIALIZED VIEW IF EXISTS $view_name CASCADE;"
    else
        psql "$SUPABASE_DB_URL" -c "DROP VIEW IF EXISTS $view_name CASCADE;"
    fi
    
    log_view "drop" "success" "Dropped $view_type view: $view_name"
    echo "View dropped successfully"
}

# Function to list views
list_views() {
    echo "Listing database views..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Regular views
    SELECT 
        schemaname,
        viewname,
        definition
    FROM pg_views
    WHERE schemaname = 'public'
    ORDER BY viewname;
    
    -- Materialized views
    SELECT 
        schemaname,
        matviewname,
        definition,
        hasindexes,
        ispopulated
    FROM pg_matviews
    WHERE schemaname = 'public'
    ORDER BY matviewname;
EOF
}

# Function to analyze view usage
analyze_views() {
    echo "Analyzing view usage..."
    
    local report_file="$VIEW_DIR/view_analysis_$(date '+%Y%m%d_%H%M%S').md"
    
    {
        echo "# View Analysis Report"
        echo "Generated on: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Environment: $ENV"
        echo
        
        echo "## Regular Views"
        echo
        psql "$SUPABASE_DB_URL" << EOF
        SELECT 
            v.schemaname,
            v.viewname,
            pg_size_pretty(pg_relation_size(quote_ident(v.schemaname) || '.' || quote_ident(v.viewname))) as view_size,
            s.seq_scan,
            s.seq_tup_read,
            age(now(), s.last_scan) as last_scan_age
        FROM pg_views v
        LEFT JOIN pg_stat_user_tables s ON v.viewname = s.relname
        WHERE v.schemaname = 'public'
        ORDER BY v.viewname;
EOF
        
        echo
        echo "## Materialized Views"
        echo
        psql "$SUPABASE_DB_URL" << EOF
        SELECT 
            m.schemaname,
            m.matviewname,
            pg_size_pretty(pg_relation_size(quote_ident(m.schemaname) || '.' || quote_ident(m.matviewname))) as view_size,
            m.hasindexes,
            m.ispopulated,
            s.seq_scan,
            s.seq_tup_read,
            age(now(), s.last_scan) as last_scan_age
        FROM pg_matviews m
        LEFT JOIN pg_stat_user_tables s ON m.matviewname = s.relname
        WHERE m.schemaname = 'public'
        ORDER BY m.matviewname;
EOF
        
        echo
        echo "## View Dependencies"
        echo
        psql "$SUPABASE_DB_URL" << EOF
        WITH RECURSIVE view_deps AS (
            SELECT DISTINCT
                dependent_ns.nspname as dependent_schema,
                dependent_view.relname as dependent_view,
                source_ns.nspname as source_schema,
                source_table.relname as source_table,
                1 as depth
            FROM pg_depend
            JOIN pg_rewrite ON pg_depend.objid = pg_rewrite.oid
            JOIN pg_class as dependent_view ON pg_rewrite.ev_class = dependent_view.oid
            JOIN pg_class as source_table ON pg_depend.refobjid = source_table.oid
            JOIN pg_namespace dependent_ns ON dependent_view.relnamespace = dependent_ns.oid
            JOIN pg_namespace source_ns ON source_table.relnamespace = source_ns.oid
            WHERE source_ns.nspname = 'public'
            AND dependent_ns.nspname = 'public'
            AND source_table.relname != dependent_view.relname
            
            UNION ALL
            
            SELECT DISTINCT
                dependent_ns.nspname,
                dependent_view.relname,
                source_ns.nspname,
                source_table.relname,
                vd.depth + 1
            FROM pg_depend
            JOIN pg_rewrite ON pg_depend.objid = pg_rewrite.oid
            JOIN pg_class as dependent_view ON pg_rewrite.ev_class = dependent_view.oid
            JOIN pg_class as source_table ON pg_depend.refobjid = source_table.oid
            JOIN pg_namespace dependent_ns ON dependent_view.relnamespace = dependent_ns.oid
            JOIN pg_namespace source_ns ON source_table.relnamespace = source_ns.oid
            JOIN view_deps vd ON vd.dependent_view = source_table.relname
            WHERE source_ns.nspname = 'public'
            AND dependent_ns.nspname = 'public'
            AND source_table.relname != dependent_view.relname
        )
        SELECT 
            dependent_view,
            source_table,
            depth
        FROM view_deps
        ORDER BY depth, dependent_view, source_table;
EOF
        
    } > "$report_file"
    
    log_view "analyze" "success" "Generated view analysis report"
    echo "Analysis report generated: $report_file"
}

# Process commands
case "${2:-list}" in
    "create-view")
        create_view "$3" "$4"
        ;;
        
    "refresh-view")
        refresh_view "$3" "$4"
        ;;
        
    "drop-view")
        drop_view "$3" "$4"
        ;;
        
    "list")
        list_views
        ;;
        
    "analyze")
        analyze_views
        ;;
        
    *)
        echo "Usage: $0 [environment] [create-view|refresh-view|drop-view|list|analyze] [args]"
        exit 1
        ;;
esac

exit 0
