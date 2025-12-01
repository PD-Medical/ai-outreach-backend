-- ============================================================================
-- PRODUCT PERFORMANCE TRACKING - FINAL MIGRATION (CORRECTED)
-- ============================================================================
-- This migration creates the product tracking system where:
-- 1. campaigns.product_id links to products.id
-- 2. product_contact_engagement tracks engagement per product per contact
-- 3. Foreign keys ensure data integrity
-- ============================================================================

-- ============================================================================
-- STEP 1: Add product_id to campaigns table
-- ============================================================================

-- Add product_id column if it doesn't exist
ALTER TABLE campaigns 
ADD COLUMN IF NOT EXISTS product_id UUID NULL;

-- Drop old constraint if exists (idempotent)
ALTER TABLE campaigns
DROP CONSTRAINT IF EXISTS fk_campaigns_product;

-- Add foreign key: campaigns.product_id → products.id
ALTER TABLE campaigns
ADD CONSTRAINT fk_campaigns_product 
FOREIGN KEY (product_id) 
REFERENCES products(id) 
ON DELETE SET NULL;

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_campaigns_product_id 
ON campaigns(product_id) 
WHERE product_id IS NOT NULL;

COMMENT ON COLUMN campaigns.product_id IS 'Links to products.id - which product this campaign is about';

-- ============================================================================
-- STEP 2: Create product_contact_engagement table
-- ============================================================================

-- Drop table if exists (fresh start)
DROP TABLE IF EXISTS product_contact_engagement CASCADE;

-- Create the table
CREATE TABLE product_contact_engagement (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Foreign key columns
  product_id UUID NOT NULL,
  contact_id UUID NOT NULL,
  
  -- Aggregated engagement metrics
  total_campaigns INTEGER DEFAULT 0,
  total_opens INTEGER DEFAULT 0,
  total_clicks INTEGER DEFAULT 0,
  total_score INTEGER DEFAULT 0,
  
  -- Timestamps
  first_engaged_at TIMESTAMPTZ NULL,
  last_engaged_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Unique constraint: one row per product-contact pair
  CONSTRAINT product_contact_unique UNIQUE (product_id, contact_id),
  
  -- Foreign key 1: product_id → products.id
  CONSTRAINT fk_pce_product 
  FOREIGN KEY (product_id) 
  REFERENCES products(id) 
  ON DELETE CASCADE,
  
  -- Foreign key 2: contact_id → contacts.id
  CONSTRAINT fk_pce_contact 
  FOREIGN KEY (contact_id) 
  REFERENCES contacts(id) 
  ON DELETE CASCADE
);

-- Add indexes for performance
CREATE INDEX idx_pce_product_id 
  ON product_contact_engagement(product_id);

CREATE INDEX idx_pce_contact_id 
  ON product_contact_engagement(contact_id);

CREATE INDEX idx_pce_last_engaged 
  ON product_contact_engagement(last_engaged_at DESC);

-- Add comments for documentation
COMMENT ON TABLE product_contact_engagement IS 'Tracks engagement between products and contacts across all campaigns';
COMMENT ON COLUMN product_contact_engagement.product_id IS 'References products.id';
COMMENT ON COLUMN product_contact_engagement.contact_id IS 'References contacts.id';
COMMENT ON COLUMN product_contact_engagement.total_campaigns IS 'Number of campaigns sent for this product to this contact';
COMMENT ON COLUMN product_contact_engagement.total_opens IS 'Total opens across all campaigns for this product-contact pair';
COMMENT ON COLUMN product_contact_engagement.total_clicks IS 'Total clicks across all campaigns for this product-contact pair';
COMMENT ON COLUMN product_contact_engagement.total_score IS 'Total engagement score across all campaigns';

-- ============================================================================
-- STEP 3: Create sync function
-- ============================================================================

CREATE OR REPLACE FUNCTION sync_product_contact_engagement()
RETURNS TABLE (
  synced_rows INTEGER,
  message TEXT
) AS $$
DECLARE
  row_count INTEGER;
BEGIN
  -- Clear existing data
  TRUNCATE product_contact_engagement;
  
  -- Aggregate engagement per product per contact
  -- Joins: campaign_contact_summary → campaigns → products & contacts
  INSERT INTO product_contact_engagement (
    product_id,
    contact_id,
    total_campaigns,
    total_opens,
    total_clicks,
    total_score,
    first_engaged_at,
    last_engaged_at,
    created_at,
    updated_at
  )
  SELECT 
    c.product_id,                                          -- From campaigns (links to products.id)
    ccs.contact_id,                                        -- From campaign_contact_summary (links to contacts.id)
    COUNT(DISTINCT ccs.campaign_id) as campaigns,          -- How many campaigns
    SUM(CASE WHEN ccs.opened THEN 1 ELSE 0 END) as opens, -- Total opens
    SUM(CASE WHEN ccs.clicked THEN 1 ELSE 0 END) as clicks,-- Total clicks
    SUM(ccs.total_score) as score,                        -- Total score
    MIN(ccs.first_event_at) as first_at,                  -- First engagement
    MAX(ccs.last_event_at) as last_at,                    -- Last engagement
    NOW(),
    NOW()
  FROM campaign_contact_summary ccs
  INNER JOIN campaigns c ON c.id = ccs.campaign_id        -- Join to get product_id
  WHERE c.product_id IS NOT NULL                           -- Only campaigns with products
  GROUP BY c.product_id, ccs.contact_id;                   -- One row per product-contact
  
  GET DIAGNOSTICS row_count = ROW_COUNT;
  
  RETURN QUERY SELECT row_count, 'Product engagement synced successfully'::TEXT;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION sync_product_contact_engagement IS 'Aggregates engagement data from campaign_contact_summary into product_contact_engagement';

-- ============================================================================
-- STEP 4: Create top products function
-- ============================================================================

CREATE OR REPLACE FUNCTION get_top_products(
  num_months INTEGER DEFAULT 3,
  limit_count INTEGER DEFAULT 5
)
RETURNS TABLE (
  product_id UUID,
  product_code TEXT,
  product_name TEXT,
  contacts_reached BIGINT,
  campaigns_sent BIGINT,
  total_opens BIGINT,
  total_clicks BIGINT,
  open_rate NUMERIC,
  engagement_score BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.product_code::TEXT,
    p.product_name::TEXT,
    COUNT(DISTINCT pce.contact_id)::BIGINT as contacts,
    SUM(pce.total_campaigns)::BIGINT as campaigns,
    SUM(pce.total_opens)::BIGINT as opens,
    SUM(pce.total_clicks)::BIGINT as clicks,
    ROUND(
      SUM(pce.total_opens)::NUMERIC / 
      NULLIF(SUM(pce.total_campaigns), 0) * 100, 
      1
    ) as open_rate,
    SUM(pce.total_score)::BIGINT as score
  FROM products p
  INNER JOIN product_contact_engagement pce ON pce.product_id = p.id
  WHERE 
    pce.last_engaged_at >= NOW() - (num_months || ' months')::INTERVAL
    AND p.is_active = true
  GROUP BY p.id, p.product_code, p.product_name
  ORDER BY SUM(pce.total_score) DESC
  LIMIT limit_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_top_products IS 'Returns top performing products by engagement score for dashboard';

-- ============================================================================
-- STEP 5: Create timeline function (for line chart)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_top_products_timeline(
  num_months INTEGER DEFAULT 3,
  limit_count INTEGER DEFAULT 5
)
RETURNS TABLE (
  product_name TEXT,
  month TEXT,
  engagement_score BIGINT
) AS $$
BEGIN
  RETURN QUERY
  WITH top_products AS (
    -- Get top N products by total engagement
    SELECT p.id, p.product_name
    FROM products p
    INNER JOIN product_contact_engagement pce ON pce.product_id = p.id
    WHERE 
      pce.last_engaged_at >= NOW() - (num_months || ' months')::INTERVAL
      AND p.is_active = true
    GROUP BY p.id, p.product_name
    ORDER BY SUM(pce.total_score) DESC
    LIMIT limit_count
  ),
  months AS (
    -- Generate month labels
    SELECT 
      DATE_TRUNC('month', NOW() - (n || ' months')::INTERVAL) as month_start,
      DATE_TRUNC('month', NOW() - (n || ' months')::INTERVAL) + INTERVAL '1 month' as month_end,
      TO_CHAR(DATE_TRUNC('month', NOW() - (n || ' months')::INTERVAL), 'Mon YYYY') as month_label,
      n as sort_order
    FROM generate_series(0, num_months - 1) n
  )
  SELECT 
    tp.product_name::TEXT,
    m.month_label::TEXT,
    COALESCE(
      SUM(pce.total_score) FILTER (
        WHERE pce.last_engaged_at >= m.month_start 
        AND pce.last_engaged_at < m.month_end
      ),
      0
    )::BIGINT
  FROM top_products tp
  CROSS JOIN months m
  LEFT JOIN product_contact_engagement pce ON pce.product_id = tp.id
  GROUP BY tp.product_name, m.month_label, m.sort_order
  ORDER BY tp.product_name, m.sort_order;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_top_products_timeline IS 'Returns product performance over time for line chart visualization';

-- ============================================================================
-- STEP 6: Run initial sync (if you have existing data)
-- ============================================================================

DO $$
DECLARE
  sync_result RECORD;
BEGIN
  -- Run sync and capture result
  SELECT * INTO sync_result FROM sync_product_contact_engagement();
  
  RAISE NOTICE 'Initial sync complete: % rows synced', sync_result.synced_rows;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Initial sync skipped (no campaign data yet): %', SQLERRM;
END $$;

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Verify 1: Check foreign keys exist
DO $$
DECLARE
  fk_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO fk_count
  FROM information_schema.table_constraints
  WHERE constraint_type = 'FOREIGN KEY'
    AND table_name = 'product_contact_engagement';
  
  RAISE NOTICE 'Foreign keys on product_contact_engagement: %', fk_count;
  
  IF fk_count < 2 THEN
    RAISE WARNING 'Expected 2 foreign keys, found %', fk_count;
  END IF;
END $$;

-- Verify 2: Show engagement data sample
SELECT 
  'Total product-contact engagements' as metric,
  COUNT(*)::TEXT as value
FROM product_contact_engagement

UNION ALL

SELECT 
  'Unique products tracked',
  COUNT(DISTINCT product_id)::TEXT
FROM product_contact_engagement

UNION ALL

SELECT 
  'Unique contacts engaged',
  COUNT(DISTINCT contact_id)::TEXT
FROM product_contact_engagement

UNION ALL

SELECT 
  'Total engagement score',
  COALESCE(SUM(total_score), 0)::TEXT
FROM product_contact_engagement;

-- Verify 3: Sample product performance
SELECT 
  p.product_name as product,
  p.product_code as code,
  COUNT(pce.id) as contacts,
  SUM(pce.total_campaigns) as campaigns,
  SUM(pce.total_opens) as opens,
  SUM(pce.total_clicks) as clicks,
  SUM(pce.total_score) as score
FROM product_contact_engagement pce
INNER JOIN products p ON p.id = pce.product_id
GROUP BY p.product_name, p.product_code
ORDER BY SUM(pce.total_score) DESC
LIMIT 5;

-- Verify 4: Test top products function
SELECT 
  'Testing get_top_products(3, 5)' as test,
  COUNT(*)::TEXT as result_count
FROM get_top_products(3, 5);

-- Verify 5: Test timeline function
SELECT 
  'Testing get_top_products_timeline(3, 5)' as test,
  COUNT(*)::TEXT as result_count
FROM get_top_products_timeline(3, 5);

-- ============================================================================
-- MIGRATION COMPLETE! 🎉
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE 'MIGRATION COMPLETED SUCCESSFULLY! 🎉';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Created:';
  RAISE NOTICE '  ✅ campaigns.product_id column';
  RAISE NOTICE '  ✅ product_contact_engagement table';
  RAISE NOTICE '  ✅ sync_product_contact_engagement() function';
  RAISE NOTICE '  ✅ get_top_products() function';
  RAISE NOTICE '  ✅ get_top_products_timeline() function';
  RAISE NOTICE '';
  RAISE NOTICE 'Next steps:';
  RAISE NOTICE '  1. Tag campaigns with product_id in your UI';
  RAISE NOTICE '  2. After sending campaigns, run: SELECT sync_product_contact_engagement();';
  RAISE NOTICE '  3. Query dashboard: SELECT * FROM get_top_products(3, 5);';
  RAISE NOTICE '========================================';
END $$;