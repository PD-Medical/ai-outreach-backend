-- ============================================================================
-- PDMedical Products - COMPLETE INTEGRATED SCHEMA WITH PRICING
-- ============================================================================
-- This schema INTEGRATES with your EXISTING tables and includes pricing
-- ✅ Uses existing: contacts, organizations, campaigns
-- ✅ Creates: product_categories, products (with pricing), contact_product_interests
-- ============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================================================
-- 1. PRODUCT CATEGORIES (NEW TABLE)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.product_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Insert categories from Excel
INSERT INTO public.product_categories (category_name, description) VALUES
    ('General', 'General medical equipment and supplies'),
    ('Infection Control', 'Products for infection prevention and control'),
    ('Birthing/Biomed', 'Birthing and biomedical equipment'),
    ('Birthing', 'Birthing-specific products'),
    ('Biomed', 'Biomedical equipment and services'),
    ('Emergency', 'Emergency medical equipment'),
    ('TUBE CONNECTORS', 'Tube connectors and related products'),
    ('TUBE ADAPTORS', 'Tube adaptors'),
    ('Y-TUBE CONNECTORS', 'Y-shaped tube connectors'),
    ('SPIGOTS', 'Spigot products'),
    ('MISCELLANEOUS', 'Miscellaneous products'),
    ('PPE', 'Personal Protective Equipment')
ON CONFLICT (category_name) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_product_categories_active 
    ON public.product_categories(is_active);

-- ============================================================================
-- 2. PRODUCTS WITH PRICING (NEW TABLE - includes pricing from Section 2)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_code VARCHAR(100) UNIQUE NOT NULL,
    product_name VARCHAR(500),
    category_id UUID REFERENCES public.product_categories(id) ON DELETE SET NULL,
    category_name VARCHAR(100),
    
    -- Product Information (Section 1 data)
    market_potential TEXT,
    background_history TEXT,
    key_contacts_reference TEXT,
    forecast_notes TEXT,
    
    -- Sales Priority
    sales_priority INTEGER CHECK (sales_priority BETWEEN 1 AND 3),
    sales_priority_label VARCHAR(20),
    sales_instructions TEXT,
    sales_timing_notes TEXT,
    sales_status VARCHAR(50) DEFAULT 'active',
    
    -- Pricing Information (Section 2 data)
    unit_price DECIMAL(12, 2),
    hsv_price DECIMAL(12, 2),
    qty_per_box INTEGER,
    moq INTEGER,
    currency VARCHAR(3) DEFAULT 'AUD',
    
    -- Status
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_products_code ON public.products(product_code);
CREATE INDEX IF NOT EXISTS idx_products_category ON public.products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_priority ON public.products(sales_priority) 
    WHERE sales_priority IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_products_status ON public.products(sales_status);
CREATE INDEX IF NOT EXISTS idx_products_active ON public.products(is_active);
CREATE INDEX IF NOT EXISTS idx_products_name_search 
    ON public.products USING gin(to_tsvector('english', COALESCE(product_name, '')));
CREATE INDEX IF NOT EXISTS idx_products_category_name ON public.products(category_name);
CREATE INDEX IF NOT EXISTS idx_products_unit_price ON public.products(unit_price) 
    WHERE unit_price IS NOT NULL;

-- ============================================================================
-- 3. CONTACT PRODUCT INTERESTS (NEW TABLE - links contacts to products)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.contact_product_interests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contact_id UUID NOT NULL REFERENCES public.contacts(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    interest_level VARCHAR(50) DEFAULT 'medium' CHECK (interest_level IN ('low', 'medium', 'high')),
    status VARCHAR(50) DEFAULT 'prospecting' CHECK (status IN ('prospecting', 'quoted', 'negotiating', 'won', 'lost')),
    source VARCHAR(50) DEFAULT 'excel_import',
    campaign_id UUID REFERENCES public.campaigns(id) ON DELETE SET NULL,
    first_interaction_date DATE DEFAULT CURRENT_DATE,
    last_interaction_date DATE DEFAULT CURRENT_DATE,
    quoted_price DECIMAL(12, 2),
    quoted_quantity INTEGER,
    quote_date DATE,
    next_followup_date DATE,
    expected_close_date DATE,
    probability_percentage DECIMAL(5, 2),
    lead_score_contribution INTEGER DEFAULT 0 CHECK (lead_score_contribution >= 0 AND lead_score_contribution <= 50),
    notes TEXT,
    lost_reason TEXT,
    competitor_chosen VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    UNIQUE(contact_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_contact_interests_contact 
    ON public.contact_product_interests(contact_id);
CREATE INDEX IF NOT EXISTS idx_contact_interests_org 
    ON public.contact_product_interests(organization_id);
CREATE INDEX IF NOT EXISTS idx_contact_interests_product 
    ON public.contact_product_interests(product_id);
CREATE INDEX IF NOT EXISTS idx_contact_interests_status 
    ON public.contact_product_interests(status);
CREATE INDEX IF NOT EXISTS idx_contact_interests_level 
    ON public.contact_product_interests(interest_level);
CREATE INDEX IF NOT EXISTS idx_contact_interests_campaign 
    ON public.contact_product_interests(campaign_id) WHERE campaign_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_contact_interests_followup 
    ON public.contact_product_interests(next_followup_date) WHERE next_followup_date IS NOT NULL;

-- ============================================================================
-- 4. ADD PRODUCT_ID TO CAMPAIGNS (Optional - for product-specific campaigns)
-- ============================================================================
ALTER TABLE public.campaigns 
    ADD COLUMN IF NOT EXISTS product_id UUID REFERENCES public.products(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_campaigns_product_id 
    ON public.campaigns(product_id) WHERE product_id IS NOT NULL;

-- ============================================================================
-- VIEWS FOR COMMON QUERIES
-- ============================================================================

-- View 1: Products with Contact Stats and Pricing
CREATE OR REPLACE VIEW public.v_products_with_stats AS
SELECT 
    p.id,
    p.product_code,
    p.product_name,
    p.category_name,
    p.sales_priority,
    p.sales_priority_label,
    p.sales_instructions,
    p.sales_timing_notes,
    p.market_potential,
    p.unit_price,
    p.hsv_price,
    p.qty_per_box,
    p.moq,
    p.currency,
    p.is_active,
    COUNT(DISTINCT cpi.contact_id) as interested_contacts_count,
    COUNT(DISTINCT cpi.organization_id) as interested_organizations_count,
    COUNT(DISTINCT CASE WHEN cpi.status = 'quoted' THEN cpi.id END) as active_quotes_count,
    SUM(CASE WHEN cpi.status = 'quoted' THEN cpi.quoted_price * cpi.quoted_quantity ELSE 0 END) as total_quoted_value,
    STRING_AGG(DISTINCT c.email, ', ' ORDER BY c.email) as contact_emails
FROM public.products p
LEFT JOIN public.contact_product_interests cpi ON p.id = cpi.product_id
LEFT JOIN public.contacts c ON cpi.contact_id = c.id
GROUP BY p.id, p.product_code, p.product_name, p.category_name, p.sales_priority, 
         p.sales_priority_label, p.sales_instructions, p.sales_timing_notes, p.market_potential, 
         p.unit_price, p.hsv_price, p.qty_per_box, p.moq, p.currency, p.is_active;

-- View 2: Products with Pricing
CREATE OR REPLACE VIEW public.v_products_pricing AS
SELECT 
    p.product_code,
    p.product_name,
    p.category_name,
    p.unit_price,
    p.hsv_price,
    p.qty_per_box,
    p.moq,
    p.currency,
    CASE 
        WHEN p.hsv_price IS NOT NULL AND p.unit_price IS NOT NULL 
        THEN ROUND(((p.hsv_price - p.unit_price) / p.unit_price * 100)::NUMERIC, 2)
        ELSE NULL
    END as price_increase_percentage
FROM public.products p
WHERE p.unit_price IS NOT NULL
ORDER BY p.unit_price DESC;

-- View 3: Contacts with Product Interests
CREATE OR REPLACE VIEW public.v_contacts_with_interests AS
SELECT 
    c.id as contact_id,
    c.email,
    c.first_name,
    c.last_name,
    c.lead_score,
    c.lead_classification,
    c.engagement_level,
    o.name as organization_name,
    o.domain as organization_domain,
    COUNT(cpi.product_id) as products_interested_in,
    STRING_AGG(p.product_name, ', ' ORDER BY p.product_name) as product_names,
    STRING_AGG(p.product_code, ', ' ORDER BY p.product_code) as product_codes,
    MAX(cpi.last_interaction_date) as last_product_interaction_date
FROM public.contacts c
LEFT JOIN public.organizations o ON c.organization_id = o.id
LEFT JOIN public.contact_product_interests cpi ON c.id = cpi.contact_id
LEFT JOIN public.products p ON cpi.product_id = p.id
GROUP BY c.id, c.email, c.first_name, c.last_name, c.lead_score, 
         c.lead_classification, c.engagement_level, o.name, o.domain;

-- View 4: Sales Priority Dashboard
CREATE OR REPLACE VIEW public.v_sales_priority_dashboard AS
SELECT 
    p.product_code,
    p.product_name,
    p.category_name,
    p.sales_priority,
    p.sales_priority_label,
    p.sales_instructions,
    p.sales_timing_notes,
    p.market_potential,
    p.unit_price,
    COUNT(DISTINCT cpi.contact_id) as interested_contacts,
    COUNT(DISTINCT cpi.organization_id) as interested_organizations,
    COUNT(DISTINCT CASE WHEN cpi.status = 'quoted' THEN cpi.id END) as active_quotes,
    SUM(CASE WHEN cpi.status = 'quoted' THEN cpi.quoted_price * cpi.quoted_quantity ELSE 0 END) as total_quoted_value,
    MIN(cpi.next_followup_date) as next_followup_date
FROM public.products p
LEFT JOIN public.contact_product_interests cpi ON p.id = cpi.product_id
WHERE p.is_active = true 
  AND p.sales_status = 'active'
  AND p.sales_priority IS NOT NULL
GROUP BY p.product_code, p.product_name, p.category_name, p.sales_priority, 
         p.sales_priority_label, p.sales_instructions, p.sales_timing_notes, p.market_potential, p.unit_price
ORDER BY p.sales_priority ASC, p.product_name ASC;

-- View 5: Products by Category
CREATE OR REPLACE VIEW public.v_products_by_category AS
SELECT 
    COALESCE(p.category_name, 'Uncategorized') as category,
    COUNT(*) as product_count,
    COUNT(DISTINCT cpi.contact_id) as total_interested_contacts,
    COUNT(CASE WHEN p.sales_priority = 1 THEN 1 END) as priority_1_count,
    COUNT(CASE WHEN p.sales_priority = 2 THEN 1 END) as priority_2_count,
    COUNT(CASE WHEN p.sales_priority = 3 THEN 1 END) as priority_3_count,
    AVG(p.unit_price) as avg_unit_price,
    MIN(p.unit_price) as min_unit_price,
    MAX(p.unit_price) as max_unit_price
FROM public.products p
LEFT JOIN public.contact_product_interests cpi ON p.id = cpi.product_id
WHERE p.is_active = true
GROUP BY COALESCE(p.category_name, 'Uncategorized')
ORDER BY category;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS update_products_updated_at ON public.products;
CREATE TRIGGER update_products_updated_at 
    BEFORE UPDATE ON public.products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_categories_updated_at ON public.product_categories;
CREATE TRIGGER update_categories_updated_at 
    BEFORE UPDATE ON public.product_categories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_interests_updated_at ON public.contact_product_interests;
CREATE TRIGGER update_interests_updated_at 
    BEFORE UPDATE ON public.contact_product_interests
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Auto-update contact lead score
CREATE OR REPLACE FUNCTION update_contact_lead_score_from_interest()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.contacts
    SET lead_score = LEAST(100, GREATEST(0, lead_score + COALESCE(NEW.lead_score_contribution, 0)))
    WHERE id = NEW.contact_id;
    RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS trigger_update_lead_score_from_interest ON public.contact_product_interests;
CREATE TRIGGER trigger_update_lead_score_from_interest
    AFTER INSERT OR UPDATE OF lead_score_contribution ON public.contact_product_interests
    FOR EACH ROW EXECUTE FUNCTION update_contact_lead_score_from_interest();

-- ============================================================================
-- COMMENTS (Documentation)
-- ============================================================================

COMMENT ON TABLE public.products IS 'Complete products table with info from both Excel sections (product info + pricing)';
COMMENT ON TABLE public.product_categories IS 'Product categories from Excel';
COMMENT ON TABLE public.contact_product_interests IS 'Links existing contacts to products';

COMMENT ON COLUMN public.products.market_potential IS 'From Section 1: Market potential description';
COMMENT ON COLUMN public.products.background_history IS 'From Section 1: Product background and history';
COMMENT ON COLUMN public.products.key_contacts_reference IS 'From Section 1: Raw text containing contact information';
COMMENT ON COLUMN public.products.unit_price IS 'From Section 2: Standard unit price in AUD';
COMMENT ON COLUMN public.products.hsv_price IS 'From Section 2: HSV (Hospital) price in AUD';
COMMENT ON COLUMN public.products.qty_per_box IS 'From Section 2: Quantity per box/package';
COMMENT ON COLUMN public.products.moq IS 'From Section 2: Minimum Order Quantity';