-- ============================================================================
-- PDMedical Products Database Schema - INTEGRATED VERSION
-- Fully integrated with existing contacts, organizations, and campaigns tables
-- ============================================================================

-- STEP 1: Add missing fields to existing tables
-- ============================================================================

-- Add missing fields to contacts table
ALTER TABLE public.contacts 
  ADD COLUMN IF NOT EXISTS lead_score INTEGER DEFAULT 0 CHECK (lead_score >= 0 AND lead_score <= 100),
  ADD COLUMN IF NOT EXISTS lead_classification VARCHAR(50) CHECK (lead_classification IN ('hot', 'warm', 'cold')),
  ADD COLUMN IF NOT EXISTS engagement_level VARCHAR(50);

-- Add product_id to existing campaigns table
ALTER TABLE public.campaigns 
  ADD COLUMN IF NOT EXISTS product_id UUID;

-- Create index for product campaigns
CREATE INDEX IF NOT EXISTS idx_campaigns_product_id 
  ON public.campaigns(product_id) 
  WHERE product_id IS NOT NULL;

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================================================
-- STEP 2: Product Schema (No Duplicate Tables)
-- ============================================================================

-- 1. PRODUCT CATEGORIES TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS product_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category_name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Insert categories found in the Excel data
INSERT INTO product_categories (category_name, description) VALUES
    ('General', 'General medical equipment and supplies'),
    ('Infection Control', 'Products for infection prevention and control'),
    ('Birthing/Biomed', 'Birthing and biomedical equipment'),
    ('Birthing', 'Birthing-specific products'),
    ('Biomed', 'Biomedical equipment and services'),
    ('Emergency', 'Emergency medical equipment')
ON CONFLICT (category_name) DO NOTHING;

-- ============================================================================
-- 2. MAIN PRODUCTS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_code VARCHAR(100) UNIQUE NOT NULL,
    product_name VARCHAR(500),
    category_id UUID REFERENCES product_categories(id) ON DELETE SET NULL,
    category_name VARCHAR(100),
    market_potential TEXT,
    background_history TEXT,
    key_contacts_reference TEXT,
    forecast_notes TEXT,
    sales_priority INTEGER,
    sales_priority_label VARCHAR(20),
    sales_instructions TEXT,
    sales_timing_notes TEXT,
    sales_status VARCHAR(50) DEFAULT 'active',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    last_modified_by UUID
);

CREATE INDEX IF NOT EXISTS idx_products_code ON products(product_code);
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_priority ON products(sales_priority) WHERE sales_priority IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_products_status ON products(sales_status);
CREATE INDEX IF NOT EXISTS idx_products_active ON products(is_active);
CREATE INDEX IF NOT EXISTS idx_products_name_search ON products USING gin(to_tsvector('english', product_name));

-- ============================================================================
-- 3. PRODUCT VARIANTS / SKUS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID REFERENCES products(id) ON DELETE CASCADE,
    sku VARCHAR(150) UNIQUE NOT NULL,
    variant_name VARCHAR(255),
    size VARCHAR(100),
    color VARCHAR(100),
    material VARCHAR(150),
    configuration TEXT,
    unit_price DECIMAL(12, 2),
    bulk_price DECIMAL(12, 2),
    cost_price DECIMAL(12, 2),
    currency VARCHAR(3) DEFAULT 'AUD',
    stock_on_hand INTEGER DEFAULT 0,
    reorder_level INTEGER DEFAULT 0,
    reorder_quantity INTEGER DEFAULT 0,
    weight_kg DECIMAL(10, 2),
    dimensions_cm VARCHAR(50),
    is_consumable BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_variants_product ON product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_variants_sku ON product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_variants_active ON product_variants(is_active);

-- ============================================================================
-- 4. PRODUCT SPECIFICATIONS / ATTRIBUTES
-- ============================================================================
CREATE TABLE IF NOT EXISTS product_specifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID REFERENCES products(id) ON DELETE CASCADE,
    spec_category VARCHAR(100),
    spec_name VARCHAR(200) NOT NULL,
    spec_value TEXT,
    spec_unit VARCHAR(50),
    display_order INTEGER DEFAULT 0,
    is_visible_to_customer BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_specs_product ON product_specifications(product_id);
CREATE INDEX IF NOT EXISTS idx_specs_category ON product_specifications(spec_category);

-- ============================================================================
-- 5. CONTACT PRODUCT INTERESTS (INTEGRATED - Uses existing campaigns table)
-- ============================================================================
CREATE TABLE IF NOT EXISTS contact_product_interests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id) ON DELETE CASCADE,
    interest_level VARCHAR(50) DEFAULT 'medium',
    status VARCHAR(50) DEFAULT 'prospecting',
    source VARCHAR(50),
    campaign_id UUID REFERENCES public.campaigns(id) ON DELETE SET NULL,
    first_interaction_date DATE,
    last_interaction_date DATE,
    interaction_count INTEGER DEFAULT 0,
    quoted_price DECIMAL(12, 2),
    quoted_quantity INTEGER,
    quote_date DATE,
    quote_valid_until DATE,
    quote_reference VARCHAR(100),
    quote_sent_by UUID,
    next_followup_date DATE,
    expected_close_date DATE,
    probability_percentage DECIMAL(5, 2),
    lead_score_contribution INTEGER DEFAULT 0,
    notes TEXT,
    lost_reason TEXT,
    competitor_chosen VARCHAR(255),
    email_opened_count INTEGER DEFAULT 0,
    email_clicked_count INTEGER DEFAULT 0,
    email_replied BOOLEAN DEFAULT false,
    last_email_sent_date DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    assigned_to UUID,
    UNIQUE(contact_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_contact_interests_contact ON contact_product_interests(contact_id);
CREATE INDEX IF NOT EXISTS idx_contact_interests_org ON contact_product_interests(organization_id);
CREATE INDEX IF NOT EXISTS idx_contact_interests_product ON contact_product_interests(product_id);
CREATE INDEX IF NOT EXISTS idx_contact_interests_status ON contact_product_interests(status);
CREATE INDEX IF NOT EXISTS idx_contact_interests_followup ON contact_product_interests(next_followup_date) WHERE next_followup_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_contact_interests_assigned ON contact_product_interests(assigned_to);
CREATE INDEX IF NOT EXISTS idx_contact_interests_campaign ON contact_product_interests(campaign_id) WHERE campaign_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_contact_interests_source ON contact_product_interests(source);

-- ============================================================================
-- 6. PRODUCT SALES TRANSACTIONS (INTEGRATED)
-- ============================================================================
CREATE TABLE IF NOT EXISTS product_sales (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID REFERENCES products(id) ON DELETE SET NULL,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES contacts(id) ON DELETE SET NULL,
    sale_date DATE NOT NULL,
    order_reference VARCHAR(150),
    invoice_reference VARCHAR(150),
    purchase_order_reference VARCHAR(150),
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(12, 2) NOT NULL,
    subtotal DECIMAL(12, 2) NOT NULL,
    discount_percentage DECIMAL(5, 2) DEFAULT 0,
    discount_amount DECIMAL(12, 2) DEFAULT 0,
    tax_amount DECIMAL(12, 2) DEFAULT 0,
    total_amount DECIMAL(12, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'AUD',
    delivery_date DATE,
    payment_status VARCHAR(50) DEFAULT 'pending',
    payment_date DATE,
    payment_terms VARCHAR(100),
    sales_person_id UUID,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_sales_product ON product_sales(product_id);
CREATE INDEX IF NOT EXISTS idx_sales_variant ON product_sales(variant_id);
CREATE INDEX IF NOT EXISTS idx_sales_organization ON product_sales(organization_id);
CREATE INDEX IF NOT EXISTS idx_sales_contact ON product_sales(contact_id);
CREATE INDEX IF NOT EXISTS idx_sales_date ON product_sales(sale_date);
CREATE INDEX IF NOT EXISTS idx_sales_payment_status ON product_sales(payment_status);
CREATE INDEX IF NOT EXISTS idx_sales_invoice ON product_sales(invoice_reference);
CREATE INDEX IF NOT EXISTS idx_sales_person ON product_sales(sales_person_id);

-- ============================================================================
-- Link campaigns to products (add foreign key constraint)
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'campaigns_product_id_fkey'
    ) THEN
        ALTER TABLE public.campaigns 
        ADD CONSTRAINT campaigns_product_id_fkey 
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL;
    END IF;
END $$;

-- ============================================================================
-- 9. PRODUCT FORECASTS & TARGETS
-- ============================================================================
CREATE TABLE IF NOT EXISTS product_forecasts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID REFERENCES products(id) ON DELETE CASCADE,
    forecast_period VARCHAR(50) NOT NULL,
    period_start_date DATE,
    period_end_date DATE,
    forecasted_quantity INTEGER,
    forecasted_revenue DECIMAL(12, 2),
    forecasted_margin_percentage DECIMAL(5, 2),
    actual_quantity INTEGER DEFAULT 0,
    actual_revenue DECIMAL(12, 2) DEFAULT 0,
    actual_margin_percentage DECIMAL(5, 2),
    quantity_variance INTEGER,
    revenue_variance DECIMAL(12, 2),
    variance_percentage DECIMAL(5, 2),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID
);

CREATE INDEX IF NOT EXISTS idx_forecasts_product ON product_forecasts(product_id);
CREATE INDEX IF NOT EXISTS idx_forecasts_period ON product_forecasts(forecast_period);
CREATE INDEX IF NOT EXISTS idx_forecasts_dates ON product_forecasts(period_start_date, period_end_date);

-- ============================================================================
-- 10. COMPETITOR PRODUCTS & ANALYSIS
-- ============================================================================
CREATE TABLE IF NOT EXISTS competitor_products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    our_product_id UUID REFERENCES products(id) ON DELETE CASCADE,
    competitor_name VARCHAR(255) NOT NULL,
    competitor_product_name VARCHAR(300),
    competitor_product_code VARCHAR(150),
    competitor_website VARCHAR(500),
    estimated_price DECIMAL(12, 2),
    estimated_market_share DECIMAL(5, 2),
    estimated_annual_volume INTEGER,
    competitor_strengths TEXT,
    competitor_weaknesses TEXT,
    our_advantages TEXT,
    our_disadvantages TEXT,
    competitive_strategy TEXT,
    price_positioning VARCHAR(50),
    notes TEXT,
    last_reviewed_date DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_competitor_our_product ON competitor_products(our_product_id);
CREATE INDEX IF NOT EXISTS idx_competitor_name ON competitor_products(competitor_name);

-- ============================================================================
-- 11. PRODUCT DOCUMENTS & MEDIA
-- ============================================================================
CREATE TABLE IF NOT EXISTS product_documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID REFERENCES products(id) ON DELETE CASCADE,
    document_type VARCHAR(50) NOT NULL,
    document_name VARCHAR(300) NOT NULL,
    file_url TEXT NOT NULL,
    file_path TEXT,
    file_size_bytes BIGINT,
    mime_type VARCHAR(100),
    file_extension VARCHAR(20),
    description TEXT,
    tags TEXT[],
    is_public BOOLEAN DEFAULT false,
    is_featured BOOLEAN DEFAULT false,
    display_order INTEGER DEFAULT 0,
    version VARCHAR(20),
    is_latest_version BOOLEAN DEFAULT true,
    replaces_document_id UUID REFERENCES product_documents(id) ON DELETE SET NULL,
    uploaded_by UUID,
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_documents_product ON product_documents(product_id);
CREATE INDEX IF NOT EXISTS idx_documents_type ON product_documents(document_type);
CREATE INDEX IF NOT EXISTS idx_documents_public ON product_documents(is_public);
CREATE INDEX IF NOT EXISTS idx_documents_featured ON product_documents(is_featured);

-- ============================================================================
-- 12. PRODUCT ACTIVITY LOG (Audit Trail - Uses existing campaigns table)
-- ============================================================================
CREATE TABLE IF NOT EXISTS product_activity_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID REFERENCES products(id) ON DELETE CASCADE,
    activity_type VARCHAR(100) NOT NULL,
    activity_category VARCHAR(50),
    activity_description TEXT,
    user_id UUID,
    user_email VARCHAR(255),
    user_name VARCHAR(255),
    contact_id UUID REFERENCES contacts(id) ON DELETE SET NULL,
    organization_id UUID REFERENCES organizations(id) ON DELETE SET NULL,
    campaign_id UUID REFERENCES public.campaigns(id) ON DELETE SET NULL,
    related_document_id UUID,
    old_value TEXT,
    new_value TEXT,
    metadata JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_activity_product ON product_activity_log(product_id);
CREATE INDEX IF NOT EXISTS idx_activity_type ON product_activity_log(activity_type);
CREATE INDEX IF NOT EXISTS idx_activity_category ON product_activity_log(activity_category);
CREATE INDEX IF NOT EXISTS idx_activity_user ON product_activity_log(user_id);
CREATE INDEX IF NOT EXISTS idx_activity_created ON product_activity_log(created_at);
CREATE INDEX IF NOT EXISTS idx_activity_contact ON product_activity_log(contact_id) WHERE contact_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_activity_org ON product_activity_log(organization_id) WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_activity_campaign ON product_activity_log(campaign_id) WHERE campaign_id IS NOT NULL;

-- ============================================================================
-- 13. PRODUCT REVIEWS & FEEDBACK
-- ============================================================================
CREATE TABLE IF NOT EXISTS product_reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID REFERENCES products(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES contacts(id) ON DELETE SET NULL,
    organization_id UUID REFERENCES organizations(id) ON DELETE SET NULL,
    reviewer_name VARCHAR(255),
    reviewer_email VARCHAR(255),
    reviewer_role VARCHAR(100),
    rating INTEGER CHECK (rating >= 1 AND rating <= 5),
    review_title VARCHAR(300),
    review_text TEXT,
    usage_context VARCHAR(100),
    usage_duration VARCHAR(100),
    ease_of_use_rating INTEGER CHECK (ease_of_use_rating >= 1 AND ease_of_use_rating <= 5),
    quality_rating INTEGER CHECK (quality_rating >= 1 AND quality_rating <= 5),
    value_for_money_rating INTEGER CHECK (value_for_money_rating >= 1 AND value_for_money_rating <= 5),
    pros TEXT,
    cons TEXT,
    would_recommend BOOLEAN,
    is_verified_purchase BOOLEAN DEFAULT false,
    is_approved BOOLEAN DEFAULT false,
    is_featured BOOLEAN DEFAULT false,
    reviewed_at DATE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_reviews_product ON product_reviews(product_id);
CREATE INDEX IF NOT EXISTS idx_reviews_contact ON product_reviews(contact_id);
CREATE INDEX IF NOT EXISTS idx_reviews_org ON product_reviews(organization_id);
CREATE INDEX IF NOT EXISTS idx_reviews_rating ON product_reviews(rating);
CREATE INDEX IF NOT EXISTS idx_reviews_approved ON product_reviews(is_approved);
CREATE INDEX IF NOT EXISTS idx_reviews_date ON product_reviews(reviewed_at);

-- ============================================================================
-- 14. PRODUCT SERVICE RECORDS (for Biomed products)
-- ============================================================================
CREATE TABLE IF NOT EXISTS product_service_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID REFERENCES products(id) ON DELETE SET NULL,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES contacts(id) ON DELETE SET NULL,
    equipment_serial_number VARCHAR(150),
    equipment_location TEXT,
    service_type VARCHAR(100),
    service_date DATE NOT NULL,
    service_reference VARCHAR(150),
    technician_id UUID,
    technician_name VARCHAR(255),
    service_description TEXT,
    parts_replaced TEXT,
    issues_found TEXT,
    actions_taken TEXT,
    labor_cost DECIMAL(10, 2),
    parts_cost DECIMAL(10, 2),
    total_cost DECIMAL(10, 2),
    next_service_due_date DATE,
    service_interval_months INTEGER,
    service_report_url TEXT,
    photos_urls TEXT[],
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_service_product ON product_service_records(product_id);
CREATE INDEX IF NOT EXISTS idx_service_organization ON product_service_records(organization_id);
CREATE INDEX IF NOT EXISTS idx_service_contact ON product_service_records(contact_id);
CREATE INDEX IF NOT EXISTS idx_service_date ON product_service_records(service_date);
CREATE INDEX IF NOT EXISTS idx_service_next_due ON product_service_records(next_service_due_date) WHERE next_service_due_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_service_technician ON product_service_records(technician_id);

-- ============================================================================
-- VIEWS FOR COMMON QUERIES
-- ============================================================================

-- View 1: Complete Product Information with metrics
CREATE OR REPLACE VIEW v_products_complete AS
SELECT 
    p.*,
    pc.category_name as category_full_name,
    COUNT(DISTINCT pv.id) as variant_count,
    COUNT(DISTINCT pd.id) as document_count,
    COUNT(DISTINCT cpi.id) as interested_contacts_count,
    COUNT(DISTINCT cpi.organization_id) as interested_organizations_count,
    COUNT(DISTINCT ps.id) as total_sales_count,
    SUM(ps.total_amount) as total_sales_revenue
FROM products p
LEFT JOIN product_categories pc ON p.category_id = pc.id
LEFT JOIN product_variants pv ON p.id = pv.product_id AND pv.is_active = true
LEFT JOIN product_documents pd ON p.id = pd.product_id
LEFT JOIN contact_product_interests cpi ON p.id = cpi.product_id
LEFT JOIN product_sales ps ON p.id = ps.product_id
WHERE p.is_active = true
GROUP BY p.id, pc.category_name;

-- View 2: Sales Priority Dashboard
CREATE OR REPLACE VIEW v_sales_priority_dashboard AS
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
    COUNT(DISTINCT cpi.contact_id) as interested_contacts,
    COUNT(DISTINCT cpi.organization_id) as interested_organizations,
    COUNT(DISTINCT CASE WHEN cpi.status = 'quoted' THEN cpi.id END) as active_quotes,
    SUM(CASE WHEN cpi.status = 'quoted' THEN cpi.quoted_price * cpi.quoted_quantity ELSE 0 END) as total_quoted_value,
    MAX(cpi.next_followup_date) as next_followup_date,
    AVG(c.lead_score) as avg_contact_lead_score
FROM products p
LEFT JOIN contact_product_interests cpi ON p.id = cpi.product_id
LEFT JOIN contacts c ON cpi.contact_id = c.id
WHERE p.is_active = true AND p.sales_status = 'active'
GROUP BY p.id, p.product_code, p.product_name, p.category_name, p.sales_priority, 
         p.sales_priority_label, p.sales_instructions, p.sales_timing_notes, p.market_potential
ORDER BY 
    CASE 
        WHEN p.sales_priority = 1 THEN 1
        WHEN p.sales_priority = 2 THEN 2
        WHEN p.sales_priority = 3 THEN 3
        ELSE 999
    END,
    p.product_name;

-- View 3: Product Sales Performance
CREATE OR REPLACE VIEW v_product_sales_performance AS
SELECT 
    p.id as product_id,
    p.product_code,
    p.product_name,
    p.category_name,
    COUNT(ps.id) as total_transactions,
    SUM(ps.quantity) as total_quantity_sold,
    SUM(ps.total_amount) as total_revenue,
    AVG(ps.unit_price) as avg_selling_price,
    MIN(ps.unit_price) as min_selling_price,
    MAX(ps.unit_price) as max_selling_price,
    MAX(ps.sale_date) as last_sale_date,
    COUNT(DISTINCT ps.organization_id) as unique_organizations,
    COUNT(DISTINCT ps.contact_id) as unique_contacts
FROM products p
LEFT JOIN product_sales ps ON p.id = ps.product_id
WHERE p.is_active = true
GROUP BY p.id, p.product_code, p.product_name, p.category_name;

-- View 4: Contacts Needing Follow-up
CREATE OR REPLACE VIEW v_contacts_needing_followup AS
SELECT 
    c.id as contact_id,
    c.email,
    c.first_name,
    c.last_name,
    c.lead_score,
    c.lead_classification,
    o.name as organization_name,
    p.product_code,
    p.product_name,
    cpi.status,
    cpi.interest_level,
    cpi.next_followup_date,
    cpi.quoted_price,
    cpi.quoted_quantity,
    cpi.assigned_to,
    cpi.notes,
    CURRENT_DATE - cpi.next_followup_date as days_overdue
FROM contacts c
INNER JOIN contact_product_interests cpi ON c.id = cpi.contact_id
INNER JOIN organizations o ON c.organization_id = o.id
INNER JOIN products p ON cpi.product_id = p.id
WHERE c.status = 'active'
  AND cpi.next_followup_date IS NOT NULL
  AND cpi.status IN ('prospecting', 'quoted', 'negotiating')
ORDER BY cpi.next_followup_date ASC;

-- View 5: Campaign Performance Dashboard (Uses existing campaigns table)
CREATE OR REPLACE VIEW v_campaign_performance AS
SELECT 
    c.id as campaign_id,
    c.name as campaign_name,
    c.subject as subject_line,
    c.provider,
    c.sent_at as sent_date,
    p.product_code,
    p.product_name,
    COUNT(DISTINCT ccs.contact_id) as total_recipients,
    COUNT(DISTINCT CASE WHEN ccs.opened = true THEN ccs.contact_id END) as emails_opened,
    COUNT(DISTINCT CASE WHEN ccs.clicked = true THEN ccs.contact_id END) as emails_clicked,
    COUNT(DISTINCT CASE WHEN ccs.converted = true THEN ccs.contact_id END) as conversions,
    SUM(ccs.total_score) as total_engagement_score,
    COUNT(DISTINCT cpi.id) as interests_generated,
    CASE 
        WHEN COUNT(DISTINCT ccs.contact_id) > 0 
        THEN ROUND((COUNT(DISTINCT CASE WHEN ccs.opened = true THEN ccs.contact_id END)::DECIMAL / COUNT(DISTINCT ccs.contact_id) * 100), 2)
        ELSE 0
    END as open_rate_percentage,
    CASE 
        WHEN COUNT(DISTINCT ccs.contact_id) > 0 
        THEN ROUND((COUNT(DISTINCT CASE WHEN ccs.clicked = true THEN ccs.contact_id END)::DECIMAL / COUNT(DISTINCT ccs.contact_id) * 100), 2)
        ELSE 0
    END as click_rate_percentage,
    CASE 
        WHEN COUNT(DISTINCT ccs.contact_id) > 0 
        THEN ROUND((COUNT(DISTINCT cpi.id)::DECIMAL / COUNT(DISTINCT ccs.contact_id) * 100), 2)
        ELSE 0
    END as conversion_rate_percentage
FROM public.campaigns c
LEFT JOIN products p ON c.product_id = p.id
LEFT JOIN public.campaign_contact_summary ccs ON c.id = ccs.campaign_id
LEFT JOIN contact_product_interests cpi ON c.id = cpi.campaign_id
WHERE c.product_id IS NOT NULL
GROUP BY c.id, c.name, c.subject, c.provider, c.sent_at, p.product_code, p.product_name
ORDER BY c.sent_at DESC;

-- View 6: Hot Contacts by Product
CREATE OR REPLACE VIEW v_hot_contacts_by_product AS
SELECT 
    c.id as contact_id,
    c.email,
    c.first_name,
    c.last_name,
    c.lead_score,
    c.lead_classification,
    c.engagement_level,
    o.name as organization_name,
    o.industry,
    p.product_code,
    p.product_name,
    p.sales_priority,
    cpi.interest_level,
    cpi.status,
    cpi.email_opened_count,
    cpi.email_clicked_count,
    cpi.last_interaction_date,
    camp.name as campaign_name,
    cpi.assigned_to
FROM contacts c
INNER JOIN contact_product_interests cpi ON c.id = cpi.contact_id
INNER JOIN organizations o ON c.organization_id = o.id
INNER JOIN products p ON cpi.product_id = p.id
LEFT JOIN public.campaigns camp ON cpi.campaign_id = camp.id
WHERE c.status = 'active'
  AND c.lead_classification IN ('hot', 'warm')
  AND cpi.status IN ('prospecting', 'quoted', 'negotiating')
  AND p.is_active = true
ORDER BY c.lead_score DESC, p.sales_priority ASC, cpi.last_interaction_date DESC;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Function: Update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS update_products_updated_at ON products;
CREATE TRIGGER update_products_updated_at 
    BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_categories_updated_at ON product_categories;
CREATE TRIGGER update_categories_updated_at 
    BEFORE UPDATE ON product_categories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_variants_updated_at ON product_variants;
CREATE TRIGGER update_variants_updated_at 
    BEFORE UPDATE ON product_variants
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_contact_interests_updated_at ON contact_product_interests;
CREATE TRIGGER update_contact_interests_updated_at 
    BEFORE UPDATE ON contact_product_interests
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_forecasts_updated_at ON product_forecasts;
CREATE TRIGGER update_forecasts_updated_at 
    BEFORE UPDATE ON product_forecasts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_competitor_products_updated_at ON competitor_products;
CREATE TRIGGER update_competitor_products_updated_at 
    BEFORE UPDATE ON competitor_products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_reviews_updated_at ON product_reviews;
CREATE TRIGGER update_reviews_updated_at 
    BEFORE UPDATE ON product_reviews
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function: Auto-update contact lead score when product interest changes
CREATE OR REPLACE FUNCTION update_contact_lead_score_from_product_interest()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE contacts
    SET lead_score = LEAST(100, GREATEST(0, lead_score + COALESCE(NEW.lead_score_contribution, 0)))
    WHERE id = NEW.contact_id;
    RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS trigger_update_lead_score_from_interest ON contact_product_interests;
CREATE TRIGGER trigger_update_lead_score_from_interest
    AFTER INSERT OR UPDATE OF lead_score_contribution ON contact_product_interests
    FOR EACH ROW EXECUTE FUNCTION update_contact_lead_score_from_product_interest();

-- Function: Log product interest activity
CREATE OR REPLACE FUNCTION log_product_interest_activity()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO product_activity_log 
            (product_id, activity_type, activity_category, activity_description, contact_id, organization_id, metadata)
        VALUES 
            (NEW.product_id, 'interest_created', 'sales', 
             'New contact interest created', NEW.contact_id, NEW.organization_id,
             jsonb_build_object('interest_level', NEW.interest_level, 'source', NEW.source));
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status IS DISTINCT FROM NEW.status THEN
            INSERT INTO product_activity_log 
                (product_id, activity_type, activity_category, activity_description, contact_id, organization_id, old_value, new_value)
            VALUES 
                (NEW.product_id, 'interest_status_changed', 'sales', 
                 'Interest status updated', NEW.contact_id, NEW.organization_id, OLD.status, NEW.status);
        END IF;
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS log_interest_changes ON contact_product_interests;
CREATE TRIGGER log_interest_changes
    AFTER INSERT OR UPDATE ON contact_product_interests
    FOR EACH ROW EXECUTE FUNCTION log_product_interest_activity();

-- ============================================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================================

ALTER TABLE product_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_specifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE contact_product_interests ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_forecasts ENABLE ROW LEVEL SECURITY;
ALTER TABLE competitor_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_activity_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_service_records ENABLE ROW LEVEL SECURITY;

-- Example RLS Policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' 
        AND tablename = 'products' 
        AND policyname = 'Allow authenticated read on products'
    ) THEN
        CREATE POLICY "Allow authenticated read on products" ON products
            FOR SELECT USING (auth.role() = 'authenticated');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' 
        AND tablename = 'products' 
        AND policyname = 'Allow authenticated write on products'
    ) THEN
        CREATE POLICY "Allow authenticated write on products" ON products
            FOR ALL USING (auth.role() = 'authenticated');
    END IF;
END $$;

-- ============================================================================
-- COMMENTS (Documentation)
-- ============================================================================

COMMENT ON TABLE products IS 'Main products table - integrated with contacts, organizations, and campaigns';
COMMENT ON TABLE contact_product_interests IS 'Links contacts to products - uses existing campaigns table';
COMMENT ON TABLE product_sales IS 'Sales transactions - fully integrated with contacts and organizations';
COMMENT ON COLUMN contact_product_interests.campaign_id IS 'References existing campaigns table (UUID)';
COMMENT ON COLUMN contact_product_interests.lead_score_contribution IS 'Points added to contact lead_score based on this interest';
COMMENT ON COLUMN public.campaigns.product_id IS 'Links campaigns to products for product-specific campaigns';

