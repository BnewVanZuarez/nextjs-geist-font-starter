#!/bin/bash

# Database load testing script
# Usage: ./load_test_db.sh [environment] [operation]
# Example: ./load_test_db.sh development stress-test

# Set environment
ENV=${1:-development}
echo "Managing database load testing for $ENV environment"

# Load environment variables
if [ -f "../.env.$ENV" ]; then
    source "../.env.$ENV"
else
    echo "Error: Environment file .env.$ENV not found"
    exit 1
fi

# Create load test directory
LOAD_DIR="../logs/load_tests"
mkdir -p "$LOAD_DIR"

# Function to log load test operations
log_load_test() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$LOAD_DIR/load_tests.log"
}

# Function to generate test data
generate_test_data() {
    local records=${1:-1000}
    echo "Generating test data ($records records)..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Create test tables if they don't exist
    CREATE TABLE IF NOT EXISTS load_test_users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(50),
        email VARCHAR(100),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    CREATE TABLE IF NOT EXISTS load_test_transactions (
        id SERIAL PRIMARY KEY,
        user_id INTEGER REFERENCES load_test_users(id),
        amount DECIMAL(10,2),
        status VARCHAR(20),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    -- Generate test users
    INSERT INTO load_test_users (username, email)
    SELECT
        'user_' || i,
        'user_' || i || '@example.com'
    FROM generate_series(1, $records) i
    ON CONFLICT DO NOTHING;
    
    -- Generate test transactions
    INSERT INTO load_test_transactions (user_id, amount, status)
    SELECT
        u.id,
        random() * 1000,
        CASE (random() * 2)::integer
            WHEN 0 THEN 'completed'
            WHEN 1 THEN 'pending'
            ELSE 'failed'
        END
    FROM load_test_users u,
         generate_series(1, 5) -- 5 transactions per user
    ORDER BY random()
    LIMIT $records;
EOF
    
    log_load_test "generate" "success" "Generated $records test records"
    echo "Test data generation completed"
}

# Function to run concurrent queries
run_concurrent_queries() {
    local connections=${1:-10}
    local duration=${2:-60}
    echo "Running concurrent queries ($connections connections for $duration seconds)..."
    
    # Create pgbench tables and data
    pgbench -i "$SUPABASE_DB_URL"
    
    # Run custom test scenario
    cat > "$LOAD_DIR/custom_test.sql" << EOF
\set user_id random(1, 1000)
\set amount random(1, 1000)
BEGIN;
SELECT * FROM load_test_users WHERE id = :user_id;
INSERT INTO load_test_transactions (user_id, amount, status)
VALUES (:user_id, :amount, 'completed');
SELECT COUNT(*) FROM load_test_transactions WHERE user_id = :user_id;
COMMIT;
EOF
    
    # Run pgbench with custom script
    pgbench -c "$connections" -T "$duration" \
            -f "$LOAD_DIR/custom_test.sql" \
            "$SUPABASE_DB_URL"
    
    log_load_test "concurrent" "success" "Completed concurrent query test"
    echo "Concurrent query test completed"
}

# Function to run stress test
stress_test() {
    local max_connections=${1:-50}
    local step=${2:-5}
    local duration=${3:-30}
    
    echo "Running stress test (up to $max_connections connections)..."
    
    local results_file="$LOAD_DIR/stress_test_$(date '+%Y%m%d_%H%M%S').csv"
    echo "connections,tps,latency_ms" > "$results_file"
    
    for ((conn=step; conn<=max_connections; conn+=step)); do
        echo "Testing with $conn connections..."
        
        # Run pgbench
        local result=$(pgbench -c "$conn" -T "$duration" \
                              -P 5 "$SUPABASE_DB_URL" 2>&1)
        
        # Extract metrics
        local tps=$(echo "$result" | grep "tps" | awk '{print $3}')
        local latency=$(echo "$result" | grep "latency" | awk '{print $4}')
        
        # Save results
        echo "$conn,$tps,$latency" >> "$results_file"
        
        # Short pause between tests
        sleep 5
    done
    
    log_load_test "stress" "success" "Completed stress test"
    echo "Stress test results saved to: $results_file"
}

# Function to simulate peak load
simulate_peak_load() {
    local duration=${1:-300}  # 5 minutes default
    echo "Simulating peak load for $duration seconds..."
    
    # Create test scenario
    cat > "$LOAD_DIR/peak_load.sql" << EOF
\set user_id random(1, 1000)
\set amount random(1, 1000)
\set rand random(1, 100)

-- Mix of read and write operations
BEGIN;
SELECT * FROM load_test_users WHERE id = :user_id;

\if :rand <= 30
    -- 30% chance of insert
    INSERT INTO load_test_transactions (user_id, amount, status)
    VALUES (:user_id, :amount, 'completed');
\elif :rand <= 60
    -- 30% chance of update
    UPDATE load_test_transactions
    SET status = 'completed'
    WHERE user_id = :user_id AND status = 'pending'
    LIMIT 1;
\else
    -- 40% chance of select
    SELECT COUNT(*), SUM(amount)
    FROM load_test_transactions
    WHERE user_id = :user_id
    GROUP BY status;
\endif

COMMIT;
EOF
    
    # Run peak load test with multiple client connections
    pgbench -c 20 -j 4 -T "$duration" \
            -f "$LOAD_DIR/peak_load.sql" \
            "$SUPABASE_DB_URL"
    
    log_load_test "peak" "success" "Completed peak load simulation"
    echo "Peak load simulation completed"
}

# Function to monitor performance during test
monitor_performance() {
    echo "Monitoring database performance..."
    
    while true; do
        clear
        date
        
        psql "$SUPABASE_DB_URL" << EOF
        -- Active connections
        SELECT count(*), state
        FROM pg_stat_activity
        GROUP BY state;
        
        -- Transaction statistics
        SELECT datname,
               xact_commit,
               xact_rollback,
               blks_read,
               blks_hit,
               tup_returned,
               tup_fetched,
               tup_inserted,
               tup_updated,
               tup_deleted
        FROM pg_stat_database
        WHERE datname = current_database();
        
        -- Table statistics
        SELECT relname,
               seq_scan,
               idx_scan,
               n_tup_ins,
               n_tup_upd,
               n_tup_del,
               n_live_tup,
               n_dead_tup
        FROM pg_stat_user_tables
        WHERE schemaname = 'public'
        ORDER BY n_tup_ins + n_tup_upd + n_tup_del DESC
        LIMIT 5;
EOF
        
        sleep 5
    done
}

# Function to analyze test results
analyze_results() {
    local test_file=$1
    
    if [ ! -f "$test_file" ]; then
        echo "Error: Test results file not found: $test_file"
        return 1
    fi
    
    echo "Analyzing test results from $test_file..."
    
    # Generate report
    local report_file="$LOAD_DIR/analysis_$(date '+%Y%m%d_%H%M%S').md"
    
    {
        echo "# Load Test Analysis Report"
        echo "Generated on: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Environment: $ENV"
        echo
        
        echo "## Test Results Summary"
        echo
        echo "### Transactions per Second (TPS)"
        echo "\`\`\`"
        awk -F',' '
            NR>1 {
                sum_tps+=$2;
                if($2>max_tps) max_tps=$2;
                if($2<min_tps || min_tps=="") min_tps=$2;
            }
            END {
                print "Average TPS: " sum_tps/(NR-1);
                print "Maximum TPS: " max_tps;
                print "Minimum TPS: " min_tps;
            }
        ' "$test_file"
        echo "\`\`\`"
        echo
        
        echo "### Latency Analysis"
        echo "\`\`\`"
        awk -F',' '
            NR>1 {
                sum_lat+=$3;
                if($3>max_lat) max_lat=$3;
                if($3<min_lat || min_lat=="") min_lat=$3;
            }
            END {
                print "Average Latency: " sum_lat/(NR-1) " ms";
                print "Maximum Latency: " max_lat " ms";
                print "Minimum Latency: " min_lat " ms";
            }
        ' "$test_file"
        echo "\`\`\`"
        echo
        
        echo "## Database Statistics"
        echo
        psql "$SUPABASE_DB_URL" -c "
            SELECT datname,
                   xact_commit,
                   xact_rollback,
                   blks_read,
                   blks_hit,
                   tup_returned,
                   tup_fetched,
                   tup_inserted,
                   tup_updated,
                   tup_deleted
            FROM pg_stat_database
            WHERE datname = current_database();
        "
        
    } > "$report_file"
    
    log_load_test "analyze" "success" "Generated analysis report"
    echo "Analysis report generated: $report_file"
}

# Function to cleanup test data
cleanup_test_data() {
    echo "Cleaning up test data..."
    
    psql "$SUPABASE_DB_URL" << EOF
    DROP TABLE IF EXISTS load_test_transactions;
    DROP TABLE IF EXISTS load_test_users;
    DROP TABLE IF EXISTS pgbench_accounts;
    DROP TABLE IF EXISTS pgbench_branches;
    DROP TABLE IF EXISTS pgbench_history;
    DROP TABLE IF EXISTS pgbench_tellers;
EOF
    
    log_load_test "cleanup" "success" "Cleaned up test data"
    echo "Test data cleanup completed"
}

# Process commands
case "${2:-help}" in
    "generate")
        generate_test_data "${3:-1000}"
        ;;
        
    "concurrent")
        run_concurrent_queries "${3:-10}" "${4:-60}"
        ;;
        
    "stress")
        stress_test "${3:-50}" "${4:-5}" "${5:-30}"
        ;;
        
    "peak")
        simulate_peak_load "${3:-300}"
        ;;
        
    "monitor")
        monitor_performance
        ;;
        
    "analyze")
        if [ -z "$3" ]; then
            echo "Error: Results file not specified"
            echo "Usage: $0 $ENV analyze <results_file>"
            exit 1
        fi
        analyze_results "$3"
        ;;
        
    "cleanup")
        cleanup_test_data
        ;;
        
    *)
        echo "Usage: $0 [environment] [generate|concurrent|stress|peak|monitor|analyze|cleanup] [args]"
        exit 1
        ;;
esac

exit 0
