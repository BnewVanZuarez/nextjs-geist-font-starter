-- Migration: Add payment integrations
-- Description: Add support for payment gateways and payment logs

BEGIN;

-- Create payment_gateways table
CREATE TABLE payment_gateways (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id UUID REFERENCES stores(id) ON DELETE CASCADE,
    provider TEXT NOT NULL CHECK (provider IN ('stripe', 'paypal', 'midtrans')),
    config JSONB NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create payment_logs table
CREATE TABLE payment_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id UUID REFERENCES transactions(id) ON DELETE CASCADE,
    gateway_id UUID REFERENCES payment_gateways(id) ON DELETE SET NULL,
    amount DECIMAL(10,2) NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending', 'success', 'failed')),
    provider_reference TEXT,
    response_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Add payment gateway reference to transactions
ALTER TABLE transactions 
ADD COLUMN payment_gateway_id UUID REFERENCES payment_gateways(id) ON DELETE SET NULL,
ADD COLUMN payment_reference TEXT;

-- Add indexes
CREATE INDEX idx_payment_gateways_store_id ON payment_gateways(store_id);
CREATE INDEX idx_payment_logs_transaction_id ON payment_logs(transaction_id);
CREATE INDEX idx_payment_logs_gateway_id ON payment_logs(gateway_id);
CREATE INDEX idx_payment_logs_status ON payment_logs(status);

-- Add RLS policies
ALTER TABLE payment_gateways ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_logs ENABLE ROW LEVEL SECURITY;

-- Payment gateways policies
CREATE POLICY "Users can view payment gateways of their stores" ON payment_gateways
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM store_users
            WHERE store_users.store_id = store_id
            AND store_users.user_id = auth.uid()
        )
    );

CREATE POLICY "Managers can manage payment gateways" ON payment_gateways
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM store_users
            WHERE store_users.store_id = store_id
            AND store_users.user_id = auth.uid()
            AND store_users.role IN ('owner', 'manager')
        )
    );

-- Payment logs policies
CREATE POLICY "Users can view payment logs of their stores" ON payment_logs
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM transactions t
            JOIN store_users su ON t.store_id = su.store_id
            WHERE t.id = transaction_id
            AND su.user_id = auth.uid()
        )
    );

-- Add trigger for updated_at
CREATE TRIGGER update_payment_gateways_updated_at
    BEFORE UPDATE ON payment_gateways
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Record migration
INSERT INTO schema_versions (version, description) 
VALUES (2, 'Add payment integrations');

COMMIT;

-- Rollback script
/*
BEGIN;

ALTER TABLE transactions 
DROP COLUMN IF EXISTS payment_gateway_id,
DROP COLUMN IF EXISTS payment_reference;

DROP TABLE IF EXISTS payment_logs;
DROP TABLE IF EXISTS payment_gateways;

DELETE FROM schema_versions WHERE version = 2;

COMMIT;
*/
