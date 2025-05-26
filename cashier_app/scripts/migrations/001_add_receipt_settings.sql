-- Migration: Add receipt settings
-- Description: Add receipt customization settings to stores table and create receipt templates table

-- Enable versioning
CREATE TABLE IF NOT EXISTS schema_versions (
    version INTEGER PRIMARY KEY,
    description TEXT NOT NULL,
    applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Start transaction
BEGIN;

-- Add receipt settings to stores table
ALTER TABLE stores ADD COLUMN IF NOT EXISTS receipt_settings JSONB DEFAULT '{
    "header": "",
    "footer": "",
    "show_logo": true,
    "show_tax": true,
    "show_store_info": true,
    "paper_size": "80mm",
    "font_size": "normal"
}'::jsonb;

-- Create receipt templates table
CREATE TABLE receipt_templates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id UUID REFERENCES stores(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    content TEXT NOT NULL,
    is_default BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Add indexes
CREATE INDEX idx_receipt_templates_store_id ON receipt_templates(store_id);

-- Add RLS policies
ALTER TABLE receipt_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view receipt templates of their stores" ON receipt_templates
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM store_users
            WHERE store_users.store_id = store_id
            AND store_users.user_id = auth.uid()
        )
    );

CREATE POLICY "Managers can manage receipt templates" ON receipt_templates
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM store_users
            WHERE store_users.store_id = store_id
            AND store_users.user_id = auth.uid()
            AND store_users.role IN ('owner', 'manager')
        )
    );

-- Add trigger for updated_at
CREATE TRIGGER update_receipt_templates_updated_at
    BEFORE UPDATE ON receipt_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Insert default template
INSERT INTO receipt_templates (
    store_id,
    name,
    description,
    content,
    is_default
) 
SELECT 
    id as store_id,
    'Default Template',
    'Default receipt template',
    '{{store_name}}
{{store_address}}
{{store_phone}}

Receipt: {{transaction_number}}
Date: {{date}}
Cashier: {{cashier_name}}

--------------------------------
{{items}}
--------------------------------
Subtotal: {{subtotal}}
Tax: {{tax}}
Total: {{total}}

Payment Method: {{payment_method}}

Thank you for shopping!
{{store_name}}',
    true
FROM stores;

-- Record migration
INSERT INTO schema_versions (version, description) 
VALUES (1, 'Add receipt settings and templates');

COMMIT;

-- Rollback script
/*
BEGIN;

DROP TABLE IF EXISTS receipt_templates;
ALTER TABLE stores DROP COLUMN IF EXISTS receipt_settings;

DELETE FROM schema_versions WHERE version = 1;

COMMIT;
*/
