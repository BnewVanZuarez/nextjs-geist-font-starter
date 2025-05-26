-- Seed database with initial test data
BEGIN;

-- Insert test users
INSERT INTO users (id, email, encrypted_password, full_name, role, phone)
VALUES
    ('11111111-1111-1111-1111-111111111111', 'admin@example.com', crypt('admin123', gen_salt('bf')), 'System Admin', 'admin', '+1234567890'),
    ('22222222-2222-2222-2222-222222222222', 'manager@example.com', crypt('manager123', gen_salt('bf')), 'Store Manager', 'manager', '+1234567891'),
    ('33333333-3333-3333-3333-333333333333', 'cashier@example.com', crypt('cashier123', gen_salt('bf')), 'Store Cashier', 'cashier', '+1234567892');

-- Insert test stores
INSERT INTO stores (id, name, address, phone, email, tax_id)
VALUES
    ('44444444-4444-4444-4444-444444444444', 'Main Store', '123 Main St, City', '+1234567893', 'main@example.com', 'TAX123'),
    ('55555555-5555-5555-5555-555555555555', 'Branch Store', '456 Branch St, City', '+1234567894', 'branch@example.com', 'TAX456');

-- Link users to stores
INSERT INTO store_users (store_id, user_id, role)
VALUES
    ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 'owner'),
    ('44444444-4444-4444-4444-444444444444', '22222222-2222-2222-2222-222222222222', 'manager'),
    ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333', 'cashier'),
    ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', 'owner');

-- Insert test products
INSERT INTO products (id, store_id, name, description, sku, barcode, category, price, cost, stock, min_stock)
VALUES
    ('66666666-6666-6666-6666-666666666666', '44444444-4444-4444-4444-444444444444', 'Product 1', 'Description 1', 'SKU001', 'BARCODE001', 'Category 1', 19.99, 10.00, 100, 10),
    ('77777777-7777-7777-7777-777777777777', '44444444-4444-4444-4444-444444444444', 'Product 2', 'Description 2', 'SKU002', 'BARCODE002', 'Category 1', 29.99, 15.00, 50, 5),
    ('88888888-8888-8888-8888-888888888888', '44444444-4444-4444-4444-444444444444', 'Product 3', 'Description 3', 'SKU003', 'BARCODE003', 'Category 2', 39.99, 20.00, 75, 8),
    ('99999999-9999-9999-9999-999999999999', '55555555-5555-5555-5555-555555555555', 'Product 4', 'Description 4', 'SKU004', 'BARCODE004', 'Category 2', 49.99, 25.00, 60, 6);

-- Insert test customers
INSERT INTO customers (id, store_id, name, email, phone, address)
VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '44444444-4444-4444-4444-444444444444', 'Customer 1', 'customer1@example.com', '+1234567895', '789 Customer St, City'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '44444444-4444-4444-4444-444444444444', 'Customer 2', 'customer2@example.com', '+1234567896', '012 Customer St, City'),
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', '55555555-5555-5555-5555-555555555555', 'Customer 3', 'customer3@example.com', '+1234567897', '345 Customer St, City');

-- Insert test transactions
INSERT INTO transactions (
    id, 
    store_id, 
    customer_id, 
    user_id, 
    transaction_number, 
    subtotal, 
    tax, 
    total, 
    payment_method, 
    payment_status
)
VALUES
    (
        'dddddddd-dddd-dddd-dddd-dddddddddddd',
        '44444444-4444-4444-4444-444444444444',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        '33333333-3333-3333-3333-333333333333',
        'TRX-001',
        49.98,
        5.00,
        54.98,
        'cash',
        'completed'
    ),
    (
        'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
        '44444444-4444-4444-4444-444444444444',
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        '33333333-3333-3333-3333-333333333333',
        'TRX-002',
        89.97,
        9.00,
        98.97,
        'card',
        'completed'
    );

-- Insert test transaction items
INSERT INTO transactions_items (transaction_id, product_id, quantity, price, subtotal)
VALUES
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', '66666666-6666-6666-6666-666666666666', 1, 19.99, 19.99),
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', '77777777-7777-7777-7777-777777777777', 1, 29.99, 29.99),
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '88888888-8888-8888-8888-888888888888', 1, 39.99, 39.99),
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '77777777-7777-7777-7777-777777777777', 1, 29.99, 29.99),
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '66666666-6666-6666-6666-666666666666', 1, 19.99, 19.99);

-- Insert test subscriptions
INSERT INTO subscriptions (
    id,
    store_id,
    plan,
    status,
    start_date,
    end_date,
    price,
    payment_method
)
VALUES
    (
        'ffffffff-ffff-ffff-ffff-ffffffffffff',
        '44444444-4444-4444-4444-444444444444',
        'premium',
        'active',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP + INTERVAL '1 year',
        299.99,
        'card'
    ),
    (
        'gggggggg-gggg-gggg-gggg-gggggggggggg',
        '55555555-5555-5555-5555-555555555555',
        'basic',
        'active',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP + INTERVAL '1 year',
        99.99,
        'card'
    );

-- Insert receipt templates (if table exists)
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_tables WHERE tablename = 'receipt_templates') THEN
        INSERT INTO receipt_templates (
            store_id,
            name,
            description,
            content,
            is_default
        )
        VALUES
        (
            '44444444-4444-4444-4444-444444444444',
            'Default Template',
            'Default receipt template for main store',
            'Thank you for shopping at {{store_name}}!\n\nReceipt: {{transaction_number}}\nDate: {{date}}\nCashier: {{cashier_name}}\n\n{{items}}\n\nSubtotal: {{subtotal}}\nTax: {{tax}}\nTotal: {{total}}\n\nPayment Method: {{payment_method}}\n\nVisit us again!',
            true
        );
    END IF;
END $$;

-- Insert payment gateways (if table exists)
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_tables WHERE tablename = 'payment_gateways') THEN
        INSERT INTO payment_gateways (
            store_id,
            provider,
            config,
            is_active
        )
        VALUES
        (
            '44444444-4444-4444-4444-444444444444',
            'stripe',
            '{"public_key": "pk_test_example", "secret_key": "sk_test_example"}'::jsonb,
            true
        );
    END IF;
END $$;

COMMIT;
