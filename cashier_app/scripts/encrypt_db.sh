#!/bin/bash

# Database encryption script
# Usage: ./encrypt_db.sh [environment] [operation]
# Example: ./encrypt_db.sh development rotate-keys

# Set environment
ENV=${1:-development}
echo "Managing database encryption for $ENV environment"

# Load environment variables
if [ -f "../.env.$ENV" ]; then
    source "../.env.$ENV"
else
    echo "Error: Environment file .env.$ENV not found"
    exit 1
fi

# Create encryption directory
ENCRYPT_DIR="../encryption"
mkdir -p "$ENCRYPT_DIR/keys"
mkdir -p "$ENCRYPT_DIR/backup"

# Create encryption logs directory
LOG_DIR="../logs/encryption"
mkdir -p "$LOG_DIR"

# Function to log encryption operations
log_encryption() {
    local operation=$1
    local status=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $ENV - $operation: $status - $message" >> "$LOG_DIR/encryption.log"
}

# Function to generate encryption keys
generate_keys() {
    echo "Generating encryption keys..."
    
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local key_file="$ENCRYPT_DIR/keys/master_key_${timestamp}.key"
    
    # Generate master key
    openssl rand -base64 32 > "$key_file"
    chmod 600 "$key_file"
    
    # Create key metadata
    cat > "${key_file}.meta" << EOF
{
    "key_id": "key_${timestamp}",
    "created_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
    "environment": "$ENV",
    "status": "active",
    "algorithm": "AES-256-GCM",
    "key_type": "master"
}
EOF
    
    # Update current key symlink
    ln -sf "$key_file" "$ENCRYPT_DIR/keys/current_master.key"
    
    log_encryption "generate" "success" "Generated new master key: key_${timestamp}"
    echo "Generated new master key: key_${timestamp}"
}

# Function to rotate encryption keys
rotate_keys() {
    echo "Rotating encryption keys..."
    
    # Backup current keys
    local backup_dir="$ENCRYPT_DIR/backup/keys_$(date '+%Y%m%d_%H%M%S')"
    mkdir -p "$backup_dir"
    cp -r "$ENCRYPT_DIR/keys/"* "$backup_dir/"
    
    # Generate new master key
    generate_keys
    
    # Re-encrypt sensitive data with new key
    psql "$SUPABASE_DB_URL" << EOF
    -- Begin key rotation transaction
    BEGIN;
    
    -- Create temporary table for re-encryption
    CREATE TEMP TABLE temp_encrypted_data AS
    SELECT id, data
    FROM encrypted_data;
    
    -- Re-encrypt data with new key
    UPDATE encrypted_data e
    SET data = pgp_sym_encrypt(
        pgp_sym_decrypt(t.data::bytea, (
            SELECT key_data
            FROM encryption_keys
            WHERE status = 'active'
            ORDER BY created_at DESC
            LIMIT 1
        )),
        (
            SELECT key_data
            FROM encryption_keys
            WHERE status = 'current'
            ORDER BY created_at DESC
            LIMIT 1
        )
    )
    FROM temp_encrypted_data t
    WHERE e.id = t.id;
    
    -- Update key status
    UPDATE encryption_keys
    SET status = 'archived'
    WHERE status = 'active';
    
    UPDATE encryption_keys
    SET status = 'active'
    WHERE status = 'current';
    
    -- Drop temporary table
    DROP TABLE temp_encrypted_data;
    
    COMMIT;
EOF
    
    log_encryption "rotate" "success" "Rotated encryption keys"
    echo "Key rotation completed"
}

# Function to setup encryption
setup_encryption() {
    echo "Setting up database encryption..."
    
    # Create encryption schema and tables
    psql "$SUPABASE_DB_URL" << EOF
    -- Create encryption schema
    CREATE SCHEMA IF NOT EXISTS encryption;
    
    -- Create encryption keys table
    CREATE TABLE IF NOT EXISTS encryption.keys (
        id SERIAL PRIMARY KEY,
        key_id TEXT UNIQUE NOT NULL,
        key_data BYTEA NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        expires_at TIMESTAMP WITH TIME ZONE,
        status TEXT NOT NULL DEFAULT 'current',
        algorithm TEXT NOT NULL,
        key_type TEXT NOT NULL,
        metadata JSONB
    );
    
    -- Create encrypted data table
    CREATE TABLE IF NOT EXISTS encryption.data_blocks (
        id SERIAL PRIMARY KEY,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        field_name TEXT NOT NULL,
        encrypted_data BYTEA NOT NULL,
        iv BYTEA NOT NULL,
        key_id TEXT REFERENCES encryption.keys(key_id),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(table_name, record_id, field_name)
    );
    
    -- Create encryption functions
    CREATE OR REPLACE FUNCTION encryption.encrypt_data(
        p_data TEXT,
        p_key_id TEXT DEFAULT NULL
    ) RETURNS BYTEA AS \$\$
    DECLARE
        v_key_data BYTEA;
        v_iv BYTEA;
    BEGIN
        -- Get latest key if not specified
        IF p_key_id IS NULL THEN
            SELECT key_data INTO v_key_data
            FROM encryption.keys
            WHERE status = 'current'
            ORDER BY created_at DESC
            LIMIT 1;
        ELSE
            SELECT key_data INTO v_key_data
            FROM encryption.keys
            WHERE key_id = p_key_id;
        END IF;
        
        -- Generate IV
        v_iv := gen_random_bytes(16);
        
        -- Return encrypted data with IV prepended
        RETURN v_iv || encrypt(
            convert_to(p_data, 'utf8'),
            v_key_data,
            'aes-256-cbc',
            v_iv
        );
    END;
    \$\$ LANGUAGE plpgsql SECURITY DEFINER;
    
    -- Create decryption function
    CREATE OR REPLACE FUNCTION encryption.decrypt_data(
        p_encrypted_data BYTEA
    ) RETURNS TEXT AS \$\$
    DECLARE
        v_key_data BYTEA;
        v_iv BYTEA;
        v_data BYTEA;
    BEGIN
        -- Extract IV and encrypted data
        v_iv := substring(p_encrypted_data from 1 for 16);
        v_data := substring(p_encrypted_data from 17);
        
        -- Get current key
        SELECT key_data INTO v_key_data
        FROM encryption.keys
        WHERE status = 'current'
        ORDER BY created_at DESC
        LIMIT 1;
        
        -- Return decrypted data
        RETURN convert_from(
            decrypt(v_data, v_key_data, 'aes-256-cbc', v_iv),
            'utf8'
        );
    END;
    \$\$ LANGUAGE plpgsql SECURITY DEFINER;
    
    -- Create trigger function for automatic encryption
    CREATE OR REPLACE FUNCTION encryption.encrypt_trigger()
    RETURNS TRIGGER AS \$\$
    DECLARE
        v_encrypted_data BYTEA;
    BEGIN
        IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
            -- Encrypt data and store in encryption.data_blocks
            v_encrypted_data := encryption.encrypt_data(NEW.data::TEXT);
            
            INSERT INTO encryption.data_blocks (
                table_name,
                record_id,
                field_name,
                encrypted_data,
                iv,
                key_id
            ) VALUES (
                TG_TABLE_NAME,
                NEW.id::TEXT,
                TG_ARGV[0],
                v_encrypted_data,
                substring(v_encrypted_data from 1 for 16),
                (
                    SELECT key_id
                    FROM encryption.keys
                    WHERE status = 'current'
                    ORDER BY created_at DESC
                    LIMIT 1
                )
            ) ON CONFLICT (table_name, record_id, field_name)
            DO UPDATE SET
                encrypted_data = v_encrypted_data,
                iv = substring(v_encrypted_data from 1 for 16),
                updated_at = CURRENT_TIMESTAMP;
        END IF;
        RETURN NEW;
    END;
    \$\$ LANGUAGE plpgsql;
EOF
    
    log_encryption "setup" "success" "Setup encryption schema and functions"
    echo "Encryption setup completed"
}

# Function to verify encryption
verify_encryption() {
    echo "Verifying encryption setup..."
    
    psql "$SUPABASE_DB_URL" << EOF
    -- Check encryption schema
    SELECT EXISTS (
        SELECT 1
        FROM information_schema.schemata
        WHERE schema_name = 'encryption'
    ) as encryption_schema_exists;
    
    -- Check encryption tables
    SELECT table_name, count(*)
    FROM information_schema.tables
    WHERE table_schema = 'encryption'
    GROUP BY table_name;
    
    -- Check encryption functions
    SELECT proname, prosrc
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'encryption';
    
    -- Check key status
    SELECT key_id, status, created_at
    FROM encryption.keys
    ORDER BY created_at DESC;
    
    -- Check encrypted data
    SELECT table_name, count(*)
    FROM encryption.data_blocks
    GROUP BY table_name;
EOF
}

# Function to backup encryption keys
backup_keys() {
    echo "Backing up encryption keys..."
    
    local backup_file="$ENCRYPT_DIR/backup/keys_$(date '+%Y%m%d_%H%M%S').gpg"
    
    # Export keys
    psql "$SUPABASE_DB_URL" -c "\COPY encryption.keys TO STDOUT" | gpg --symmetric --output "$backup_file"
    
    log_encryption "backup" "success" "Backed up encryption keys to $backup_file"
    echo "Keys backed up to: $backup_file"
}

# Function to restore encryption keys
restore_keys() {
    local backup_file=$1
    
    if [ ! -f "$backup_file" ]; then
        echo "Error: Backup file not found: $backup_file"
        return 1
    fi
    
    echo "Restoring encryption keys from $backup_file..."
    
    # Import keys
    gpg --decrypt "$backup_file" | psql "$SUPABASE_DB_URL" -c "\COPY encryption.keys FROM STDIN"
    
    log_encryption "restore" "success" "Restored encryption keys from $backup_file"
    echo "Keys restored from backup"
}

# Process commands
case "${2:-verify}" in
    "setup")
        setup_encryption
        ;;
        
    "generate")
        generate_keys
        ;;
        
    "rotate")
        rotate_keys
        ;;
        
    "verify")
        verify_encryption
        ;;
        
    "backup")
        backup_keys
        ;;
        
    "restore")
        if [ -z "$3" ]; then
            echo "Error: Backup file not specified"
            echo "Usage: $0 $ENV restore <backup_file>"
            exit 1
        fi
        restore_keys "$3"
        ;;
        
    *)
        echo "Usage: $0 [environment] [setup|generate|rotate|verify|backup|restore] [args]"
        exit 1
        ;;
esac

exit 0
