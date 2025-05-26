-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Drop existing tables if they exist
DROP TABLE IF EXISTS transactions_items;
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS store_users;
DROP TABLE IF EXISTS stores;
DROP TABLE IF EXISTS subscriptions;
DROP TABLE IF EXISTS users;

-- Create users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email TEXT UNIQUE NOT NULL,
    encrypted_password TEXT NOT NULL,
    full_name TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('admin', 'manager', 'cashier')),
    phone TEXT,
    avatar_url TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create stores table
CREATE TABLE stores (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    address TEXT,
    phone TEXT,
    email TEXT,
    tax_id TEXT,
    logo_url TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create store_users table (many-to-many relationship)
CREATE TABLE store_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id UUID REFERENCES stores(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('owner', 'manager', 'cashier')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(store_id, user_id)
);

-- Create products table
CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id UUID REFERENCES stores(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    sku TEXT,
    barcode TEXT,
    category TEXT,
    price DECIMAL(10,2) NOT NULL CHECK (price >= 0),
    cost DECIMAL(10,2) CHECK (cost >= 0),
    stock INTEGER NOT NULL DEFAULT 0,
    min_stock INTEGER DEFAULT 0,
    image_url TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create customers table
CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id UUID REFERENCES stores(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    address TEXT,
    notes TEXT,
    points INTEGER DEFAULT 0,
    total_spent DECIMAL(12,2) DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create transactions table
CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id UUID REFERENCES stores(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    transaction_number TEXT NOT NULL,
    subtotal DECIMAL(10,2) NOT NULL,
    tax DECIMAL(10,2) DEFAULT 0,
    discount DECIMAL(10,2) DEFAULT 0,
    total DECIMAL(10,2) NOT NULL,
    payment_method TEXT NOT NULL CHECK (payment_method IN ('cash', 'card', 'transfer')),
    payment_status TEXT NOT NULL CHECK (payment_status IN ('pending', 'completed', 'cancelled')),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create transactions_items table
CREATE TABLE transactions_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id UUID REFERENCES transactions(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id) ON DELETE SET NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    price DECIMAL(10,2) NOT NULL CHECK (price >= 0),
    subtotal DECIMAL(10,2) NOT NULL CHECK (subtotal >= 0),
    discount DECIMAL(10,2) DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create subscriptions table
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id UUID REFERENCES stores(id) ON DELETE CASCADE,
    plan TEXT NOT NULL CHECK (plan IN ('basic', 'pro', 'premium')),
    status TEXT NOT NULL CHECK (status IN ('active', 'cancelled', 'expired')),
    start_date TIMESTAMP WITH TIME ZONE NOT NULL,
    end_date TIMESTAMP WITH TIME ZONE NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    payment_method TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_products_store_id ON products(store_id);
CREATE INDEX idx_products_category ON products(category);
CREATE INDEX idx_transactions_store_id ON transactions(store_id);
CREATE INDEX idx_transactions_customer_id ON transactions(customer_id);
CREATE INDEX idx_transactions_created_at ON transactions(created_at);
CREATE INDEX idx_customers_store_id ON customers(store_id);
CREATE INDEX idx_store_users_store_id ON store_users(store_id);
CREATE INDEX idx_store_users_user_id ON store_users(user_id);

-- Create functions
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_stores_updated_at
    BEFORE UPDATE ON stores
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_products_updated_at
    BEFORE UPDATE ON products
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_customers_updated_at
    BEFORE UPDATE ON customers
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_subscriptions_updated_at
    BEFORE UPDATE ON subscriptions
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Create RLS policies
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE stores ENABLE ROW LEVEL SECURITY;
ALTER TABLE store_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;

-- Users policies
CREATE POLICY "Users can view their own data" ON users
    FOR SELECT USING (auth.uid() = id);

-- Stores policies
CREATE POLICY "Users can view stores they belong to" ON stores
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM store_users
            WHERE store_users.store_id = id
            AND store_users.user_id = auth.uid()
        )
    );

-- Products policies
CREATE POLICY "Users can view products of their stores" ON products
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM store_users
            WHERE store_users.store_id = store_id
            AND store_users.user_id = auth.uid()
        )
    );

-- Insert sample data
INSERT INTO users (email, encrypted_password, full_name, role)
VALUES (
    'admin@example.com',
    crypt('admin123', gen_salt('bf')),
    'System Admin',
    'admin'
);

-- Create functions for common operations
CREATE OR REPLACE FUNCTION create_transaction(
    p_store_id UUID,
    p_user_id UUID,
    p_customer_id UUID,
    p_items JSONB,
    p_payment_method TEXT,
    p_notes TEXT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_transaction_id UUID;
    v_item JSONB;
    v_subtotal DECIMAL(10,2) := 0;
    v_tax DECIMAL(10,2) := 0;
    v_total DECIMAL(10,2) := 0;
    v_transaction_number TEXT;
BEGIN
    -- Generate transaction number
    SELECT CONCAT(
        TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD'),
        '-',
        LPAD(COALESCE(
            (SELECT COUNT(*) + 1 FROM transactions 
             WHERE DATE(created_at) = CURRENT_DATE)::TEXT,
            '1'
        ), 4, '0')
    ) INTO v_transaction_number;

    -- Calculate totals
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_subtotal := v_subtotal + (v_item->>'quantity')::INTEGER * (v_item->>'price')::DECIMAL;
    END LOOP;

    v_tax := v_subtotal * 0.1; -- 10% tax
    v_total := v_subtotal + v_tax;

    -- Create transaction
    INSERT INTO transactions (
        store_id,
        user_id,
        customer_id,
        transaction_number,
        subtotal,
        tax,
        total,
        payment_method,
        payment_status,
        notes
    ) VALUES (
        p_store_id,
        p_user_id,
        p_customer_id,
        v_transaction_number,
        v_subtotal,
        v_tax,
        v_total,
        p_payment_method,
        'completed',
        p_notes
    ) RETURNING id INTO v_transaction_id;

    -- Create transaction items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        INSERT INTO transactions_items (
            transaction_id,
            product_id,
            quantity,
            price,
            subtotal
        ) VALUES (
            v_transaction_id,
            (v_item->>'product_id')::UUID,
            (v_item->>'quantity')::INTEGER,
            (v_item->>'price')::DECIMAL,
            (v_item->>'quantity')::INTEGER * (v_item->>'price')::DECIMAL
        );

        -- Update product stock
        UPDATE products
        SET stock = stock - (v_item->>'quantity')::INTEGER
        WHERE id = (v_item->>'product_id')::UUID;
    END LOOP;

    -- Update customer total spent
    IF p_customer_id IS NOT NULL THEN
        UPDATE customers
        SET total_spent = total_spent + v_total,
            points = points + (v_total::INTEGER / 100) -- 1 point per 100 spent
        WHERE id = p_customer_id;
    END IF;

    RETURN v_transaction_id;
END;
$$ LANGUAGE plpgsql;
