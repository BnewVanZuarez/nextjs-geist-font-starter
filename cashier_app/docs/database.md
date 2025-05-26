# Database Documentation

## Overview

The Kasir App uses PostgreSQL through Supabase for data storage. The database is designed to support multi-store operations with comprehensive user management, inventory tracking, and transaction processing.

## Schema

### Core Tables

#### users
Stores user account information.
```sql
CREATE TABLE users (
    id UUID PRIMARY KEY,
    email TEXT UNIQUE,
    encrypted_password TEXT,
    full_name TEXT,
    role TEXT,
    phone TEXT,
    avatar_url TEXT,
    is_active BOOLEAN,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE
);
```

#### stores
Stores business/store information.
```sql
CREATE TABLE stores (
    id UUID PRIMARY KEY,
    name TEXT,
    address TEXT,
    phone TEXT,
    email TEXT,
    tax_id TEXT,
    logo_url TEXT,
    receipt_settings JSONB,
    is_active BOOLEAN,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE
);
```

#### store_users
Links users to stores with role assignments.
```sql
CREATE TABLE store_users (
    id UUID PRIMARY KEY,
    store_id UUID REFERENCES stores,
    user_id UUID REFERENCES users,
    role TEXT,
    created_at TIMESTAMP WITH TIME ZONE
);
```

### Inventory Management

#### products
Stores product information.
```sql
CREATE TABLE products (
    id UUID PRIMARY KEY,
    store_id UUID REFERENCES stores,
    name TEXT,
    description TEXT,
    sku TEXT,
    barcode TEXT,
    category TEXT,
    price DECIMAL(10,2),
    cost DECIMAL(10,2),
    stock INTEGER,
    min_stock INTEGER,
    image_url TEXT,
    is_active BOOLEAN,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE
);
```

### Sales Management

#### transactions
Records sales transactions.
```sql
CREATE TABLE transactions (
    id UUID PRIMARY KEY,
    store_id UUID REFERENCES stores,
    customer_id UUID REFERENCES customers,
    user_id UUID REFERENCES users,
    transaction_number TEXT,
    subtotal DECIMAL(10,2),
    tax DECIMAL(10,2),
    discount DECIMAL(10,2),
    total DECIMAL(10,2),
    payment_method TEXT,
    payment_status TEXT,
    payment_gateway_id UUID,
    payment_reference TEXT,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE
);
```

#### transactions_items
Records items in each transaction.
```sql
CREATE TABLE transactions_items (
    id UUID PRIMARY KEY,
    transaction_id UUID REFERENCES transactions,
    product_id UUID REFERENCES products,
    quantity INTEGER,
    price DECIMAL(10,2),
    subtotal DECIMAL(10,2),
    discount DECIMAL(10,2),
    created_at TIMESTAMP WITH TIME ZONE
);
```

### Customer Management

#### customers
Stores customer information.
```sql
CREATE TABLE customers (
    id UUID PRIMARY KEY,
    store_id UUID REFERENCES stores,
    name TEXT,
    email TEXT,
    phone TEXT,
    address TEXT,
    notes TEXT,
    points INTEGER,
    total_spent DECIMAL(12,2),
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE
);
```

### Subscription Management

#### subscriptions
Tracks store subscriptions.
```sql
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY,
    store_id UUID REFERENCES stores,
    plan TEXT,
    status TEXT,
    start_date TIMESTAMP WITH TIME ZONE,
    end_date TIMESTAMP WITH TIME ZONE,
    price DECIMAL(10,2),
    payment_method TEXT,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE
);
```

### Payment Processing

#### payment_gateways
Stores payment gateway configurations.
```sql
CREATE TABLE payment_gateways (
    id UUID PRIMARY KEY,
    store_id UUID REFERENCES stores,
    provider TEXT,
    config JSONB,
    is_active BOOLEAN,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE
);
```

#### payment_logs
Records payment processing logs.
```sql
CREATE TABLE payment_logs (
    id UUID PRIMARY KEY,
    transaction_id UUID REFERENCES transactions,
    gateway_id UUID REFERENCES payment_gateways,
    amount DECIMAL(10,2),
    status TEXT,
    provider_reference TEXT,
    response_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE
);
```

## Relationships

### Store-centric Relationships
- A store can have multiple users (through store_users)
- A store can have multiple products
- A store can have multiple customers
- A store can have multiple transactions
- A store can have one active subscription
- A store can have multiple payment gateways

### User-centric Relationships
- A user can belong to multiple stores (through store_users)
- A user can process multiple transactions
- A user's role determines their permissions in each store

### Transaction-centric Relationships
- A transaction belongs to one store
- A transaction can have multiple items
- A transaction can be associated with one customer
- A transaction is processed by one user
- A transaction can have one payment gateway

## Row Level Security (RLS)

### Store Access
```sql
CREATE POLICY "Users can view stores they belong to" ON stores
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM store_users
            WHERE store_users.store_id = id
            AND store_users.user_id = auth.uid()
        )
    );
```

### Product Access
```sql
CREATE POLICY "Users can view products of their stores" ON products
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM store_users
            WHERE store_users.store_id = store_id
            AND store_users.user_id = auth.uid()
        )
    );
```

## Functions

### Transaction Processing
```sql
CREATE OR REPLACE FUNCTION create_transaction(
    p_store_id UUID,
    p_user_id UUID,
    p_customer_id UUID,
    p_items JSONB,
    p_payment_method TEXT,
    p_notes TEXT DEFAULT NULL
) RETURNS UUID
```

## Indexes

### Performance Indexes
```sql
CREATE INDEX idx_products_store_id ON products(store_id);
CREATE INDEX idx_transactions_store_id ON transactions(store_id);
CREATE INDEX idx_transactions_created_at ON transactions(created_at);
CREATE INDEX idx_customers_store_id ON customers(store_id);
```

## Maintenance

### Regular Tasks
1. Run VACUUM ANALYZE regularly
2. Monitor table bloat
3. Update table statistics
4. Check index usage
5. Monitor long-running queries

### Backup Strategy
1. Daily full backups
2. Point-in-time recovery enabled
3. Backup retention: 30 days
4. Regular backup testing

## Security

### Data Protection
- Encrypted passwords using pgcrypto
- Row Level Security (RLS) policies
- Role-based access control
- Audit logging

### Best Practices
1. Use parameterized queries
2. Implement connection pooling
3. Regular security audits
4. Monitor failed login attempts

## Performance

### Optimization Tips
1. Use appropriate indexes
2. Regular VACUUM and ANALYZE
3. Monitor query performance
4. Use connection pooling
5. Implement caching where appropriate

### Common Issues
1. Table bloat
2. Index bloat
3. Long-running queries
4. Connection exhaustion

## Scripts

### Database Management
- `db.sh`: Main database management script
- `setup_db.sql`: Initial database setup
- `run_migrations.sh`: Run database migrations
- `run_seeder.sh`: Seed test data
- `backup_db.sh`: Manage backups
- `maintain_db.sh`: Database maintenance

## Environment Setup

### Development
```bash
./db.sh development setup
./db.sh development migrate
./db.sh development seed
```

### Production
```bash
./db.sh production setup
./db.sh production migrate
```

## Troubleshooting

### Common Issues
1. Connection failures
2. Migration errors
3. Performance issues
4. Data inconsistencies

### Diagnostic Queries
```sql
-- Check table sizes
SELECT pg_size_pretty(pg_total_relation_size('table_name'));

-- Check index usage
SELECT * FROM pg_stat_user_indexes;

-- Check long-running queries
SELECT * FROM pg_stat_activity WHERE state = 'active';
```

## Resources

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Supabase Documentation](https://supabase.io/docs)
- [Database Best Practices](docs/best-practices.md)
- [Maintenance Guide](docs/maintenance.md)
