#!/bin/bash

# Database test script
# Usage: ./test_db.sh [environment] [test-type]
# Example: ./test_db.sh development performance

# Set environment
ENV=${1:-development}
echo "Running database tests in $ENV environment"

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

# Create test results directory
TEST_DIR="../logs/tests"
mkdir -p "$TEST_DIR"

# Function to log test results
log_test() {
    local test=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $test: $status - $message" >> "$TEST_DIR/test_results.log"
}

# Function to test database connection
test_connection() {
    echo "Testing database connection..."
    
    local start_time=$(date +%s.%N)
    if psql "$SUPABASE_DB_URL" -c "SELECT 1;" > /dev/null 2>&1; then
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc)
        log_test "connection" "success" "Connected in $duration seconds"
        echo "Connection successful (${duration}s)"
        return 0
    else
        log_test "connection" "error" "Connection failed"
        echo "Connection failed"
        return 1
    fi
}

# Function to test CRUD operations
test_crud() {
    echo "Testing CRUD operations..."
    
    # Create test table
    psql "$SUPABASE_DB_URL" << EOF
    DROP TABLE IF EXISTS test_crud;
    CREATE TABLE test_crud (
        id SERIAL PRIMARY KEY,
        name TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
EOF
    
    # Test INSERT
    local start_time=$(date +%s.%N)
    if psql "$SUPABASE_DB_URL" -c "INSERT INTO test_crud (name) VALUES ('test1'), ('test2'), ('test3');" > /dev/null 2>&1; then
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc)
        log_test "crud_insert" "success" "Inserted 3 rows in $duration seconds"
        echo "INSERT successful (${duration}s)"
    else
        log_test "crud_insert" "error" "Insert failed"
        echo "INSERT failed"
        return 1
    fi
    
    # Test SELECT
    start_time=$(date +%s.%N)
    if psql "$SUPABASE_DB_URL" -c "SELECT * FROM test_crud;" > /dev/null 2>&1; then
        end_time=$(date +%s.%N)
        duration=$(echo "$end_time - $start_time" | bc)
        log_test "crud_select" "success" "Selected rows in $duration seconds"
        echo "SELECT successful (${duration}s)"
    else
        log_test "crud_select" "error" "Select failed"
        echo "SELECT failed"
        return 1
    fi
    
    # Test UPDATE
    start_time=$(date +%s.%N)
    if psql "$SUPABASE_DB_URL" -c "UPDATE test_crud SET name = 'updated' WHERE id = 1;" > /dev/null 2>&1; then
        end_time=$(date +%s.%N)
        duration=$(echo "$end_time - $start_time" | bc)
        log_test "crud_update" "success" "Updated row in $duration seconds"
        echo "UPDATE successful (${duration}s)"
    else
        log_test "crud_update" "error" "Update failed"
        echo "UPDATE failed"
        return 1
    fi
    
    # Test DELETE
    start_time=$(date +%s.%N)
    if psql "$SUPABASE_DB_URL" -c "DELETE FROM test_crud WHERE id = 3;" > /dev/null 2>&1; then
        end_time=$(date +%s.%N)
        duration=$(echo "$end_time - $start_time" | bc)
        log_test "crud_delete" "success" "Deleted row in $duration seconds"
        echo "DELETE successful (${duration}s)"
    else
        log_test "crud_delete" "error" "Delete failed"
        echo "DELETE failed"
        return 1
    fi
    
    # Clean up
    psql "$SUPABASE_DB_URL" -c "DROP TABLE test_crud;" > /dev/null 2>&1
    
    return 0
}

# Function to test performance
test_performance() {
    echo "Testing database performance..."
    
    # Create test table
    psql "$SUPABASE_DB_URL" << EOF
    DROP TABLE IF EXISTS test_performance;
    CREATE TABLE test_performance (
        id SERIAL PRIMARY KEY,
        data TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    CREATE INDEX idx_test_performance_created_at ON test_performance(created_at);
EOF
    
    # Test bulk insert
    local start_time=$(date +%s.%N)
    psql "$SUPABASE_DB_URL" << EOF > /dev/null 2>&1
    INSERT INTO test_performance (data)
    SELECT 'test_data_' || generate_series
    FROM generate_series(1, 10000);
EOF
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    log_test "performance_insert" "info" "Inserted 10000 rows in $duration seconds"
    echo "Bulk INSERT: ${duration}s for 10000 rows"
    
    # Test index scan
    start_time=$(date +%s.%N)
    psql "$SUPABASE_DB_URL" -c "SELECT * FROM test_performance WHERE created_at > NOW() - INTERVAL '1 hour';" > /dev/null 2>&1
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)
    log_test "performance_select" "info" "Index scan completed in $duration seconds"
    echo "Index scan: ${duration}s"
    
    # Test sequential scan
    start_time=$(date +%s.%N)
    psql "$SUPABASE_DB_URL" -c "SELECT * FROM test_performance WHERE data LIKE '%500%';" > /dev/null 2>&1
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)
    log_test "performance_seqscan" "info" "Sequential scan completed in $duration seconds"
    echo "Sequential scan: ${duration}s"
    
    # Clean up
    psql "$SUPABASE_DB_URL" -c "DROP TABLE test_performance;" > /dev/null 2>&1
}

# Function to test concurrency
test_concurrency() {
    echo "Testing database concurrency..."
    
    # Create test table
    psql "$SUPABASE_DB_URL" << EOF
    DROP TABLE IF EXISTS test_concurrency;
    CREATE TABLE test_concurrency (
        id SERIAL PRIMARY KEY,
        counter INTEGER DEFAULT 0
    );
    INSERT INTO test_concurrency (counter) VALUES (0);
EOF
    
    # Function to increment counter
    increment_counter() {
        psql "$SUPABASE_DB_URL" << EOF > /dev/null 2>&1
        BEGIN;
        UPDATE test_concurrency 
        SET counter = counter + 1 
        WHERE id = 1;
        COMMIT;
EOF
    }
    
    # Run concurrent updates
    local start_time=$(date +%s.%N)
    for i in {1..10}; do
        increment_counter &
    done
    wait
    
    # Check final count
    local final_count=$(psql "$SUPABASE_DB_URL" -t -c "SELECT counter FROM test_concurrency WHERE id = 1;")
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    
    log_test "concurrency" "info" "Final count: $final_count in $duration seconds"
    echo "Concurrency test: ${duration}s, Final count: $final_count"
    
    # Clean up
    psql "$SUPABASE_DB_URL" -c "DROP TABLE test_concurrency;" > /dev/null 2>&1
}

# Function to generate test report
generate_report() {
    local report_file="$TEST_DIR/test_report_$(date '+%Y%m%d_%H%M%S').txt"
    
    {
        echo "Database Test Report"
        echo "==================="
        echo "Environment: $ENV"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo
        
        echo "Connection Test"
        echo "--------------"
        test_connection
        echo
        
        echo "CRUD Test"
        echo "---------"
        test_crud
        echo
        
        echo "Performance Test"
        echo "----------------"
        test_performance
        echo
        
        echo "Concurrency Test"
        echo "----------------"
        test_concurrency
        
    } > "$report_file"
    
    echo "Report generated: $report_file"
}

# Process commands
case "${2:-all}" in
    "connection")
        test_connection
        ;;
        
    "crud")
        test_crud
        ;;
        
    "performance")
        test_performance
        ;;
        
    "concurrency")
        test_concurrency
        ;;
        
    "all")
        generate_report
        ;;
        
    *)
        echo "Usage: $0 [environment] [connection|crud|performance|concurrency|all]"
        exit 1
        ;;
esac

exit 0
