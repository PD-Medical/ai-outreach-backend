-- ============================================================================
-- PRODUCT ENHANCEMENTS MIGRATION
-- ============================================================================
-- This migration adds:
-- 1. New columns to products table (product_type, description, website_url)
-- 2. New product_documents table for brochure/document linking
-- 3. New permissions (view_products, manage_products)
-- 4. RLS policies on products and product_documents tables
-- ============================================================================

-- ============================================================================
-- PHASE 1: SCHEMA CHANGES
-- ============================================================================

-- 1.1 Add new columns to products table
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS product_type VARCHAR(50);
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS website_url VARCHAR(500);

-- Add constraint for product_type values (only if not exists)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'products_product_type_check'
    ) THEN
        ALTER TABLE public.products ADD CONSTRAINT products_product_type_check
            CHECK (product_type IS NULL OR product_type IN ('main_unit', 'accessory', 'spare_part', 'consumable', 'service', 'kit'));
    END IF;
END $$;

-- Add index for filtering by product_type
CREATE INDEX IF NOT EXISTS idx_products_type ON public.products(product_type);

-- 1.2 Create product_documents table
CREATE TABLE IF NOT EXISTS public.product_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    document_type VARCHAR(50) NOT NULL,
    storage_path TEXT NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    file_size_bytes INTEGER,
    mime_type VARCHAR(100) DEFAULT 'application/pdf',
    description TEXT,
    is_primary BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),

    CONSTRAINT product_documents_type_check
        CHECK (document_type IN ('brochure', 'spec_sheet', 'manual', 'catalogue', 'safety_data'))
);

-- Create indexes for product_documents
CREATE INDEX IF NOT EXISTS idx_product_documents_product ON public.product_documents(product_id);
CREATE INDEX IF NOT EXISTS idx_product_documents_type ON public.product_documents(document_type);
CREATE INDEX IF NOT EXISTS idx_product_documents_primary ON public.product_documents(product_id, is_primary) WHERE is_primary = true;

-- Updated_at trigger for product_documents
DROP TRIGGER IF EXISTS set_updated_at ON public.product_documents;
CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON public.product_documents
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- 1.3 Add new permission columns to role_permissions table
ALTER TABLE public.role_permissions ADD COLUMN IF NOT EXISTS view_products BOOLEAN DEFAULT true;
ALTER TABLE public.role_permissions ADD COLUMN IF NOT EXISTS manage_products BOOLEAN DEFAULT false;

-- Update default role permissions
UPDATE public.role_permissions SET view_products = true, manage_products = true WHERE role = 'admin';
UPDATE public.role_permissions SET view_products = true, manage_products = true WHERE role = 'sales';
UPDATE public.role_permissions SET view_products = true, manage_products = false WHERE role = 'accounts';
UPDATE public.role_permissions SET view_products = true, manage_products = false WHERE role = 'management';

-- ============================================================================
-- PHASE 2: ROW LEVEL SECURITY
-- ============================================================================

-- 2.1 Enable RLS on products table
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS products_select_policy ON public.products;
DROP POLICY IF EXISTS products_insert_policy ON public.products;
DROP POLICY IF EXISTS products_update_policy ON public.products;
DROP POLICY IF EXISTS products_delete_policy ON public.products;

-- Create RLS policies for products
CREATE POLICY products_select_policy ON public.products
    FOR SELECT USING (public.has_permission('view_products'));

CREATE POLICY products_insert_policy ON public.products
    FOR INSERT WITH CHECK (public.has_permission('manage_products'));

CREATE POLICY products_update_policy ON public.products
    FOR UPDATE USING (public.has_permission('manage_products'));

CREATE POLICY products_delete_policy ON public.products
    FOR DELETE USING (public.has_permission('manage_products'));

-- 2.2 Enable RLS on product_documents table
ALTER TABLE public.product_documents ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS product_documents_select_policy ON public.product_documents;
DROP POLICY IF EXISTS product_documents_insert_policy ON public.product_documents;
DROP POLICY IF EXISTS product_documents_update_policy ON public.product_documents;
DROP POLICY IF EXISTS product_documents_delete_policy ON public.product_documents;

-- Create RLS policies for product_documents
CREATE POLICY product_documents_select_policy ON public.product_documents
    FOR SELECT USING (public.has_permission('view_products'));

CREATE POLICY product_documents_insert_policy ON public.product_documents
    FOR INSERT WITH CHECK (public.has_permission('manage_products'));

CREATE POLICY product_documents_update_policy ON public.product_documents
    FOR UPDATE USING (public.has_permission('manage_products'));

CREATE POLICY product_documents_delete_policy ON public.product_documents
    FOR DELETE USING (public.has_permission('manage_products'));

-- ============================================================================
-- NOTE: Data population (product_type, description, website_url, product_documents)
-- is now handled by seed.sql. Removed Phases 3-6 to avoid duplicates.
-- ============================================================================
