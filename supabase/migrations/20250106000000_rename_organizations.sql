-- ============================================================================
-- Organizations Refactoring Migration
-- ============================================================================
-- This migration:
-- 1. Creates organization_types lookup table
-- 2. Renames customer_organizations to organizations
-- 3. Adds organization_type_id foreign key
-- 4. Adds healthcare-specific fields
-- 5. Makes domain NOT NULL
-- 6. Updates all foreign key constraints and indexes
-- ============================================================================

-- ============================================================================
-- ORGANIZATION TYPES LOOKUP TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.organization_types (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name character varying NOT NULL UNIQUE,
  description text,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  
  CONSTRAINT organization_types_pkey PRIMARY KEY (id)
);

-- Seed initial organization types
INSERT INTO public.organization_types (name, description) VALUES
  ('Hospital', 'Hospital or medical center'),
  ('Clinic', 'Medical clinic or practice'),
  ('Aged Care', 'Aged care or nursing home facility'),
  ('Pharmacy', 'Pharmacy or chemist'),
  ('Medical Supplier', 'Medical equipment or supplies vendor'),
  ('Other', 'Other organization type');

-- ============================================================================
-- RENAME TABLE
-- ============================================================================
ALTER TABLE public.customer_organizations RENAME TO organizations;

-- ============================================================================
-- ADD NEW COLUMNS
-- ============================================================================

-- Add organization_type_id foreign key
ALTER TABLE public.organizations ADD COLUMN organization_type_id uuid;
ALTER TABLE public.organizations ADD CONSTRAINT organizations_organization_type_id_fkey 
  FOREIGN KEY (organization_type_id) REFERENCES public.organization_types(id) ON DELETE SET NULL;

-- Add healthcare-specific fields from spreadsheet
ALTER TABLE public.organizations ADD COLUMN region character varying;
ALTER TABLE public.organizations ADD COLUMN hospital_category character varying;
ALTER TABLE public.organizations ADD COLUMN city character varying;
ALTER TABLE public.organizations ADD COLUMN state character varying;
ALTER TABLE public.organizations ADD COLUMN key_hospital character varying;
ALTER TABLE public.organizations ADD COLUMN street_address character varying;
ALTER TABLE public.organizations ADD COLUMN suburb character varying;
ALTER TABLE public.organizations ADD COLUMN facility_type character varying;
ALTER TABLE public.organizations ADD COLUMN bed_count integer;
ALTER TABLE public.organizations ADD COLUMN top_150_ranking integer;
ALTER TABLE public.organizations ADD COLUMN general_info text;
ALTER TABLE public.organizations ADD COLUMN products_sold text[];
ALTER TABLE public.organizations ADD COLUMN has_maternity boolean DEFAULT false;
ALTER TABLE public.organizations ADD COLUMN has_operating_theatre boolean DEFAULT false;

-- ============================================================================
-- MAKE DOMAIN NOT NULL
-- ============================================================================
-- First, update any NULL domains to 'unknown.local'
UPDATE public.organizations SET domain = 'unknown.local' WHERE domain IS NULL;
-- Then make the column NOT NULL
ALTER TABLE public.organizations ALTER COLUMN domain SET NOT NULL;

-- ============================================================================
-- RENAME CONSTRAINTS AND INDEXES
-- ============================================================================

-- Rename primary key constraint
ALTER TABLE public.organizations RENAME CONSTRAINT customer_organizations_pkey TO organizations_pkey;

-- Rename domain index
ALTER INDEX public.idx_customer_organizations_domain RENAME TO idx_organizations_domain;

-- ============================================================================
-- ADD NEW INDEXES
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_organizations_organization_type_id ON public.organizations(organization_type_id);
CREATE INDEX IF NOT EXISTS idx_organizations_state ON public.organizations(state);
CREATE INDEX IF NOT EXISTS idx_organizations_city ON public.organizations(city);
CREATE INDEX IF NOT EXISTS idx_organizations_facility_type ON public.organizations(facility_type);

-- ============================================================================
-- UPDATE FOREIGN KEY REFERENCES IN CONTACTS TABLE
-- ============================================================================
ALTER TABLE public.contacts RENAME COLUMN customer_organization_id TO organization_id;
ALTER TABLE public.contacts RENAME CONSTRAINT contacts_customer_organization_id_fkey TO contacts_organization_id_fkey;

-- Update contacts index
ALTER INDEX public.idx_contacts_customer_organization_id RENAME TO idx_contacts_organization_id;

-- ============================================================================
-- UPDATE FOREIGN KEY REFERENCES IN CONVERSATIONS TABLE
-- ============================================================================
ALTER TABLE public.conversations RENAME COLUMN customer_organization_id TO organization_id;
ALTER TABLE public.conversations RENAME CONSTRAINT conversations_customer_organization_id_fkey TO conversations_organization_id_fkey;

-- Update conversations index
ALTER INDEX public.idx_conversations_customer_organization_id RENAME TO idx_conversations_organization_id;

-- ============================================================================
-- UPDATE FOREIGN KEY REFERENCES IN EMAILS TABLE
-- ============================================================================
ALTER TABLE public.emails RENAME COLUMN customer_organization_id TO organization_id;
ALTER TABLE public.emails RENAME CONSTRAINT emails_customer_organization_id_fkey TO emails_organization_id_fkey;

-- Update emails index
ALTER INDEX public.idx_emails_customer_organization_id RENAME TO idx_emails_organization_id;

-- ============================================================================
-- ADD COMMENTS
-- ============================================================================
COMMENT ON TABLE public.organization_types IS 'Lookup table for organization types (Hospital, Clinic, Aged Care, etc.)';
COMMENT ON TABLE public.organizations IS 'Customer organizations with healthcare-specific fields';
COMMENT ON COLUMN public.organizations.region IS 'Geographic region (if any)';
COMMENT ON COLUMN public.organizations.hospital_category IS 'Hospital category classification';
COMMENT ON COLUMN public.organizations.city IS 'City or county';
COMMENT ON COLUMN public.organizations.state IS 'State (NSW, VIC, QLD, etc.)';
COMMENT ON COLUMN public.organizations.key_hospital IS 'Key hospital rank';
COMMENT ON COLUMN public.organizations.street_address IS 'Street address';
COMMENT ON COLUMN public.organizations.suburb IS 'Suburb';
COMMENT ON COLUMN public.organizations.facility_type IS 'Facility type (Public, Private, Ramsay, Healthscope, etc.)';
COMMENT ON COLUMN public.organizations.bed_count IS 'Number of beds';
COMMENT ON COLUMN public.organizations.top_150_ranking IS 'Top 150 ranking position';
COMMENT ON COLUMN public.organizations.general_info IS 'General information (freeform text)';
COMMENT ON COLUMN public.organizations.products_sold IS 'Array of products sold to this organization';
COMMENT ON COLUMN public.organizations.has_maternity IS 'Has maternity services';
COMMENT ON COLUMN public.organizations.has_operating_theatre IS 'Has operating theatre';

