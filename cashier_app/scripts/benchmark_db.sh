#!/bin/bash

# Database benchmark script
# Usage: ./benchmark_db.sh [environment] [benchmark-type]
# Example: ./benchmark_db.sh development write

# Set environment
ENV=${1:-development}
echo "Running database benchmarks in $ENV environment"

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

# Create benchmark results directory
BENCH_DIR="../logs/benchmarks"
mkdir -p "$BENCH_DIR"

# Function to log benchmark results
log_benchmark() {
    local benchmark=$1
    local metric=$2
    local value=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $benchmark: $metric = $value" >> "$BENCH_DIR/benchmark_results.log"
}

# Function to run write benchmark
benchmark_write() {
    echo "Running write benchmark..."
    
    # Create test table
    psql "$SUPABASE_DB_URL" << EOF
    DROP TABLE IF EXISTS benchmark_write;
    CREATE TABLE benchmark_write (
        id SERIAL PRIMARY KEY,
        data TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
EOF
    
    # Test different batch sizes
    for size in 100 1000 10000; do
        echo "Testing batch size: $size"
        
        # Single transaction
        local start_time=$(date +%s.%N)
        psql "$SUPABASE_DB_URL" << EOF > /dev/null 2>&1
        BEGIN;
        INSERT INTO benchmark_write (data)
        SELECT 'test_data_' || generate_series
        FROM generate_series(1, $size);
        COMMIT;
EOF
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc)
        local rate=$(echo "$size / $duration" | bc)
        
        log_benchmark "write" "batch_$size" "$rate rows/sec"
        echo "Batch $size: $rate rows/sec"
        
        # Clean up
        psql "$SUPABASE_DB_URL" -c "TRUNCATE benchmark_write;" > /dev/null 2>&1
    done
    
    # Clean up
    psql "$SUPABASE_DB_URL" -c "DROP TABLE benchmark_write;" > /dev/null 2>&1
}

# Function to run read benchmark
benchmark_read() {
    echo "Running read benchmark..."
    
    # Create test table with indexes
    psql "$SUPABASE_DB_URL" << EOF
    DROP TABLE IF EXISTS benchmark_read;
    CREATE TABLE benchmark_read (
        id SERIAL PRIMARY KEY,
        data TEXT,
        category TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    CREATE INDEX idx_benchmark_read_category ON benchmark_read(category);
    CREATE INDEX idx_benchmark_read_created_at ON benchmark_read(created_at);
    
    -- Insert test data
    INSERT INTO benchmark_read (data, category)
    SELECT 
        'test_data_' || generate_series,
        'category_' || (generate_series % 10)
    FROM generate_series(1, 100000);
EOF
    
    # Test different query types
    echo "Testing index scan..."
    local start_time=$(date +%s.%N)
    psql "$SUPABASE_DB_URL" -c "SELECT COUNT(*) FROM benchmark_read WHERE category = 'category_1';" > /dev/null 2>&1
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    log_benchmark "read" "index_scan" "$duration seconds"
    echo "Index scan: $duration seconds"
    
    echo "Testing sequential scan..."
    start_time=$(date +%s.%N)
    psql "$SUPABASE_DB_URL" -c "SELECT COUNT(*) FROM benchmark_read WHERE data LIKE '%500%';" > /dev/null 2>&1
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)
    log_benchmark "read" "sequential_scan" "$duration seconds"
    echo "Sequential scan: $duration seconds"
    
    echo "Testing join..."
    start_time=$(date +%s.%N)
    psql "$SUPABASE_DB_URL" -c "
        SELECT r1.category, COUNT(*)
        FROM benchmark_read r1
        JOIN benchmark_read r2 ON r1.category = r2.category
        GROUP BY r1.category;
    " > /dev/null 2>&1
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)
    log_benchmark "read" "join" "$duration seconds"
    echo "Join: $duration seconds"
    
    # Clean up
    psql "$SUPABASE_DB_URL" -c "DROP TABLE benchmark_read;" > /dev/null 2>&1
}

# Function to run concurrency benchmark
benchmark_concurrency() {
    echo "Running concurrency benchmark..."
    
    # Create test table
    psql "$SUPABASE_DB_URL" << EOF
    DROP TABLE IF EXISTS benchmark_concurrency;
    CREATE TABLE benchmark_concurrency (
        id SERIAL PRIMARY KEY,
        counter INTEGER DEFAULT 0
    );
    INSERT INTO benchmark_concurrency (counter) VALUES (0);
EOF
    
    # Test different concurrent connection counts
    for connections in 10 50 100; do
        echo "Testing with $connections concurrent connections..."
        
        local start_time=$(date +%s.%N)
        
        # Create concurrent connections
        for ((i=1; i<=$connections; i++)); do
            psql "$SUPABASE_DB_URL" << EOF > /dev/null 2>&1 &
            BEGIN;
            UPDATE benchmark_concurrency 
            SET counter = counter + 1 
            WHERE id = 1;
            COMMIT;
EOF
        done
        
        # Wait for all processes to complete
        wait
        
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc)
        local rate=$(echo "$connections / $duration" | bc)
        
        # Get final counter value
        local final_count=$(psql "$SUPABASE_DB_URL" -t -c "SELECT counter FROM benchmark_concurrency WHERE id = 1;")
        
        log_benchmark "concurrency" "connections_$connections" "$rate transactions/sec (count: $final_count)"
        echo "Concurrent connections $connections: $rate transactions/sec (final count: $final_count)"
        
        # Reset counter
        psql "$SUPABASE_DB_URL" -c "UPDATE benchmark_concurrency SET counter = 0 WHERE id = 1;" > /dev/null 2>&1
    done
    
    # Clean up
    psql "$SUPABASE_DB_URL" -c "DROP TABLE benchmark_concurrency;" > /dev/null 2>&1
}

# Function to generate benchmark report
generate_report() {
    local report_file="$BENCH_DIR/benchmark_report_$(date '+%Y%m%d_%H%M%S').txt"
    
    {
        echo "Database Benchmark Report"
        echo "========================"
        echo "Environment: $ENV"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo
        
        echo "Write Performance"
        echo "----------------"
        benchmark_write
        echo
        
        echo "Read Performance"
        echo "---------------"
        benchmark_read
        echo
        
        echo "Concurrency Performance"
        echo "----------------------"
        benchmark_concurrency
        
    } > "$report_file"
    
    echo "Report generated: $report_file"
}

# Process commands
case "${2:-all}" in
    "write")
        benchmark_write
        ;;
        
    "read")
        benchmark_read
        ;;
        
    "concurrency")
        benchmark_concurrency
        ;;
        
    "all")
        generate_report
        ;;
        
    *)
        echo "Usage: $0 [environment] [write|read|concurrency|all]"
        exit 1
        ;;
esac

exit 0
