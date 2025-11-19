-- ============================================================================
-- PDMedical Parent Products - COMPLETE CLEANUP + IMPLEMENTATION
-- This script: 1) Cleans up incorrect data, 2) Implements correct 7 super parents
-- ============================================================================

-- ============================================================================
-- STEP 1: BACKUP REMINDER
-- ============================================================================
-- ⚠️ IMPORTANT: Run this first in a separate session:
-- pg_dump -U postgres pdmedical > backup_$(date +%Y%m%d_%H%M%S).sql

-- ============================================================================
-- STEP 2: CLEANUP - Remove incorrect data
-- ============================================================================

-- Drop parent_products table if it exists (will cascade and clear product links)
DROP TABLE IF EXISTS public.parent_products CASCADE;

-- Clear parent_product_id from products (safe - keeps all products)
ALTER TABLE public.products DROP COLUMN IF EXISTS parent_product_id;

-- Clean up incorrect product_categories (keep only the 5 main ones)
DELETE FROM public.product_categories 
WHERE category_name NOT IN ('General', 'Infection Control', 'Birthing/Biomed', 'Birthing', 'Biomed');

-- Ensure the 5 main categories exist
INSERT INTO public.product_categories (category_name, description) VALUES
    ('General', 'General medical equipment and supplies'),
    ('Infection Control', 'Products for infection prevention and control'),
    ('Birthing/Biomed', 'Birthing and biomedical equipment'),
    ('Birthing', 'Birthing-specific products'),
    ('Biomed', 'Biomedical equipment and services')
ON CONFLICT (category_name) DO NOTHING;

-- ============================================================================
-- STEP 3: CREATE parent_products table (Fresh)
-- ============================================================================

CREATE TABLE public.parent_products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_code VARCHAR(100) UNIQUE NOT NULL,
    parent_name VARCHAR(255) NOT NULL,
    
    -- Self-referencing for hierarchy
    parent_parent_id UUID REFERENCES public.parent_products(id) ON DELETE CASCADE,
    
    -- Category reference
    category_id UUID REFERENCES public.product_categories(id) ON DELETE SET NULL,
    category_name VARCHAR(100),
    
    -- Hierarchy level
    hierarchy_level INTEGER DEFAULT 1 CHECK (hierarchy_level IN (1, 2)),
    
    -- Sales Information
    sales_priority INTEGER CHECK (sales_priority BETWEEN 1 AND 3),
    sales_priority_label VARCHAR(20),
    sales_instructions TEXT,
    sales_timing_notes TEXT,
    
    -- Additional fields
    description TEXT,
    display_order INTEGER,
    is_active BOOLEAN DEFAULT true,
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create indexes
CREATE INDEX idx_parent_products_category ON public.parent_products(category_id);
CREATE INDEX idx_parent_products_priority ON public.parent_products(sales_priority);
CREATE INDEX idx_parent_products_code ON public.parent_products(parent_code);
CREATE INDEX idx_parent_products_parent_parent ON public.parent_products(parent_parent_id);
CREATE INDEX idx_parent_products_level ON public.parent_products(hierarchy_level);

-- ============================================================================
-- STEP 4: ADD parent_product_id to products table
-- ============================================================================

ALTER TABLE public.products 
    ADD COLUMN parent_product_id UUID REFERENCES public.parent_products(id) ON DELETE SET NULL;

CREATE INDEX idx_products_parent ON public.products(parent_product_id);

-- ============================================================================
-- STEP 5: INSERT 7 Super Parents + 20 Sub-Parents
-- ============================================================================

DO $$
DECLARE
    cat_general UUID;
    cat_infection_control UUID;
    cat_birthing_biomed UUID;
    
    -- Super Parent IDs
    super_tubes UUID;
    super_midogas UUID;
    super_misc UUID;
    super_devices UUID;
    super_ppe UUID;
    super_gas_alarms UUID;
    super_safe_sharps UUID;
BEGIN
    -- Get category IDs
    SELECT id INTO cat_general FROM public.product_categories WHERE category_name = 'General';
    SELECT id INTO cat_infection_control FROM public.product_categories WHERE category_name = 'Infection Control';
    SELECT id INTO cat_birthing_biomed FROM public.product_categories WHERE category_name = 'Birthing/Biomed';

    -- ========================================================================
    -- LEVEL 1: 7 SUPER PARENTS
    -- ========================================================================
    
    INSERT INTO public.parent_products (
        parent_code, parent_name, category_id, category_name,
        hierarchy_level, sales_priority, sales_priority_label, display_order
    ) VALUES
    ('TUBE_CONNECTORS', 'Tube Connectors', 
        cat_general, 'General', 1, 1, '#1', 1),
    ('MIDOGAS', 'MIDOGAS Products', 
        cat_birthing_biomed, 'Birthing/Biomed', 1, NULL, NULL, 2),
    ('MISCELLANEOUS', 'Miscellaneous Products', 
        cat_general, 'General', 1, NULL, NULL, 3),
    ('DEVICES', 'Devices and Components', 
        cat_general, 'General', 1, NULL, NULL, 4),
    ('PPE', 'PPE Products', 
        cat_infection_control, 'Infection Control', 1, NULL, NULL, 5),
    ('GAS_ALARM_SYSTEMS', 'Gas Alarm Systems', 
        cat_general, 'General', 1, NULL, NULL, 6),
    ('SAFE_SHARPS_HANDLING', 'Safe Sharps Handling', 
        cat_infection_control, 'Infection Control', 1, NULL, NULL, 7);
    
    -- Get Super Parent IDs
    SELECT id INTO super_tubes FROM public.parent_products WHERE parent_code = 'TUBE_CONNECTORS';
    SELECT id INTO super_midogas FROM public.parent_products WHERE parent_code = 'MIDOGAS';
    SELECT id INTO super_misc FROM public.parent_products WHERE parent_code = 'MISCELLANEOUS';
    SELECT id INTO super_devices FROM public.parent_products WHERE parent_code = 'DEVICES';
    SELECT id INTO super_ppe FROM public.parent_products WHERE parent_code = 'PPE';
    SELECT id INTO super_gas_alarms FROM public.parent_products WHERE parent_code = 'GAS_ALARM_SYSTEMS';
    SELECT id INTO super_safe_sharps FROM public.parent_products WHERE parent_code = 'SAFE_SHARPS_HANDLING';

    -- ========================================================================
    -- LEVEL 2: SUB-PARENTS
    -- ========================================================================
    
    -- Under TUBE_CONNECTORS (4 sub-parents, all #1)
    INSERT INTO public.parent_products (
        parent_code, parent_name, parent_parent_id, category_id, category_name,
        hierarchy_level, sales_priority, sales_priority_label, display_order
    ) VALUES
    ('TUBE_CONNECTORS_SUB', 'Tube Connectors (Sterile & Non-Sterile)', 
        super_tubes, cat_general, 'General', 2, 1, '#1', 11),
    ('TUBE_ADAPTORS', 'Tube Adaptors', 
        super_tubes, cat_general, 'General', 2, 1, '#1', 12),
    ('Y_TUBE_CONNECTORS', 'Y-Tube Connectors', 
        super_tubes, cat_general, 'General', 2, 1, '#1', 13),
    ('SPIGOTS', 'Spigots', 
        super_tubes, cat_general, 'General', 2, 1, '#1', 14);
    
    -- Under MIDOGAS (6 sub-parents)
    INSERT INTO public.parent_products (
        parent_code, parent_name, parent_parent_id, category_id, category_name,
        hierarchy_level, sales_priority, sales_priority_label, 
        sales_instructions, sales_timing_notes, display_order
    ) VALUES
    ('MIDOGAS_UNIT', 'Midogas Analgesic Unit', 
        super_midogas, cat_birthing_biomed, 'Birthing/Biomed',
        2, 1, '#1', NULL, 'Wait until Tech area sorted', 21),
    ('MIDOGAS_MOBILE_STAND', 'Midogas Mobile Stands', 
        super_midogas, cat_birthing_biomed, 'Birthing/Biomed',
        2, 3, '#3', NULL, NULL, 22),
    ('MIDOGAS_SERVICING', 'Midogas Std Service', 
        super_midogas, cat_birthing_biomed, 'Birthing/Biomed',
        2, 2, '#2', NULL, NULL, 23),
    ('MEDICAL_GAS_HOSE', 'Medical Gas Hose Assemblies', 
        super_midogas, cat_birthing_biomed, 'Birthing/Biomed',
        2, NULL, NULL, NULL, NULL, 24),
    ('MIDOGAS_SPARE_PARTS', 'MIDOGAS Spare Parts', 
        super_midogas, cat_birthing_biomed, 'Birthing/Biomed',
        2, NULL, NULL, NULL, NULL, 25),
    ('MIDOGAS_MINI', 'Midogas-mini Products',
        super_midogas, cat_birthing_biomed, 'Birthing/Biomed',
        2, NULL, NULL, NULL, NULL, 26);
    
    -- Under DEVICES (4 sub-parents)
    INSERT INTO public.parent_products (
        parent_code, parent_name, parent_parent_id, category_id, category_name,
        hierarchy_level, display_order
    ) VALUES
    ('SUB_ASSEMBLIES', 'Sub-Assemblies', 
        super_devices, cat_general, 'General', 2, 41),
    ('COMPONENTS', 'Components', 
        super_devices, cat_general, 'General', 2, 42),
    ('SCAVENGE_UNIT', 'Scavenge Units', 
        super_devices, cat_general, 'General', 2, 43),
    ('BREATHING_CIRCUITS', 'Breathing Circuits', 
        super_devices, cat_general, 'General', 2, 44);
    
    -- Under PPE (2 sub-parents)
    INSERT INTO public.parent_products (
        parent_code, parent_name, parent_parent_id, category_id, category_name,
        hierarchy_level, sales_priority, sales_priority_label,
        sales_instructions, sales_timing_notes, display_order
    ) VALUES
    ('PPE_CADDY', 'PPE Caddy', 
        super_ppe, cat_infection_control, 'Infection Control',
        2, 2, '#2', 'X', 'Move onto these a week later', 51),
    ('PPE_ACCESSORIES', 'PPE Accessories and Consumables', 
        super_ppe, cat_infection_control, 'Infection Control',
        2, NULL, NULL, NULL, NULL, 52);
    
    -- Under SAFE_SHARPS_HANDLING (4 sub-parents)
    INSERT INTO public.parent_products (
        parent_code, parent_name, parent_parent_id, category_id, category_name,
        hierarchy_level, sales_priority, sales_priority_label,
        sales_instructions, display_order
    ) VALUES
    ('SHARPS_CADDY', 'Sharps Caddy', 
        super_safe_sharps, cat_infection_control, 'Infection Control',
        2, 1, '#1', NULL, 71),
    ('SHARPS_CONTAINER', 'Sharps Container 1.4L (Yellow)', 
        super_safe_sharps, cat_infection_control, 'Infection Control',
        2, 1, '#1', NULL, 72),
    ('INSTRUMENT_TRAYS', 'Tray General Purpose, Scalpel and Forcep Instrument Trays', 
        super_safe_sharps, cat_infection_control, 'Infection Control',
        2, 1, '#1', 'X', 73),
    ('SCALPEL_BLADE_REMOVER', 'Scalpel Blade Remover', 
        super_safe_sharps, cat_infection_control, 'Infection Control',
        2, 2, '#2', 'X', 74);

END $$;

-- ============================================================================
-- STEP 6: LINK Products to Parents (Based on category_name in products table)
-- ============================================================================

-- TUBE CONNECTORS
UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'TUBE_CONNECTORS_SUB')
WHERE category_name = 'TUBE CONNECTORS';

UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'TUBE_ADAPTORS')
WHERE category_name = 'TUBE ADAPTORS';

UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'Y_TUBE_CONNECTORS')
WHERE category_name = 'Y-TUBE CONNECTORS';

UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'SPIGOTS')
WHERE category_name = 'SPIGOTS';

-- MIDOGAS
UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'MIDOGAS_UNIT')
WHERE category_name = 'MIDOGAS UNIT';

UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'MIDOGAS_MOBILE_STAND')
WHERE category_name = 'MIDOGAS MOBILE STAND';

UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'MIDOGAS_SERVICING')
WHERE category_name = 'MIDOGAS SERVICING' OR category_name = 'Birthing/Biomed';

UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'MEDICAL_GAS_HOSE')
WHERE category_name = 'MEDICAL GAS HOSE ASSEMBLIES';

UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'MIDOGAS_SPARE_PARTS')
WHERE category_name = 'SPARE PARTS';

UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'MIDOGAS_MINI')
WHERE category_name = 'Biomed/Birthing' OR category_name = 'MA142-MMBGS';

-- DEVICES
UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'SUB_ASSEMBLIES')
WHERE category_name = 'SUB-ASSEMBLIES';

UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'COMPONENTS')
WHERE category_name = 'COMPONENTS';

UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'SCAVENGE_UNIT')
WHERE product_code = 'MA141M-9';

UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'BREATHING_CIRCUITS')
WHERE category_name = 'BREATHING CIRCUITS' 
   OR product_code IN ('MA143-BCS', 'MA143-PBCS', 'MA143-ESC', 'MA143-ST', 'MA143-BC')
   OR category_name = 'Emergency';

-- PPE
UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'PPE_CADDY')
WHERE product_code IN ('PPE-C', 'PPE-C1', 'PPE-C2', 'PPE-C3', 'PPE-CH', 'PPE-MC');

UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'PPE_ACCESSORIES')
WHERE product_code IN ('PPE-FFS', 'PPE-DFS', 'PPE-DG', 'PPE-DGF', 'PPE-DGL', 
                       'PPE-B', 'PPE-V', 'PPE-ASS', 'PPE-ADS', 'PPE-S');

-- SAFE SHARPS HANDLING
UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'SHARPS_CADDY')
WHERE product_code LIKE 'SC-%' AND category_name = 'SAFE SHARPS HANDLING' 
  AND product_code NOT IN ('SC-CONT-1.4L');

UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'SHARPS_CONTAINER')
WHERE product_code IN ('SC-CONT-1.4L', 'CC-CONT-1.3L');

UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'SCALPEL_BLADE_REMOVER')
WHERE product_code IN ('SBR1', 'SBR2');

UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'INSTRUMENT_TRAYS')
WHERE product_code LIKE 'ST_%';

-- GAS ALARM SYSTEMS (direct to super parent)
UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'GAS_ALARM_SYSTEMS')
WHERE category_name = 'GAS ALARM SYSTEMS';

-- MISCELLANEOUS (direct to super parent - only 3 products)
UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'MISCELLANEOUS')
WHERE product_code IN ('BAR_PAN_G', 'BAR_PAN_P', 'DAVM633')
   OR (category_name = 'MISCELLANEOUS' AND product_code NOT LIKE 'PPE-%');

-- BIOMED products
UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'MIDOGAS_SERVICING')
WHERE category_name = 'Biomed' AND product_code NOT IN ('MA140');

-- BIRTHING products  
UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'BREATHING_CIRCUITS')
WHERE category_name = 'Birthing';

-- GENERAL category catch-all
UPDATE public.products SET parent_product_id = (SELECT id FROM parent_products WHERE parent_code = 'TUBE_CONNECTORS_SUB')
WHERE category_name = 'General' AND parent_product_id IS NULL;

-- ============================================================================
-- STEP 7: CREATE VIEWS
-- ============================================================================

CREATE OR REPLACE VIEW public.v_complete_hierarchy AS
SELECT 
    sp.id as super_parent_id,
    sp.parent_code as super_parent_code,
    sp.parent_name as super_parent_name,
    subp.id as sub_parent_id,
    subp.parent_code as sub_parent_code,
    subp.parent_name as sub_parent_name,
    subp.sales_priority,
    subp.sales_priority_label,
    p.id as product_id,
    p.product_code,
    p.product_name,
    p.unit_price,
    p.category_name
FROM public.products p
LEFT JOIN public.parent_products subp ON p.parent_product_id = subp.id
LEFT JOIN public.parent_products sp ON subp.parent_parent_id = sp.id
WHERE p.is_active = true
ORDER BY sp.display_order, subp.display_order, p.product_code;

CREATE OR REPLACE VIEW public.v_super_parents_summary AS
SELECT 
    sp.id,
    sp.parent_code,
    sp.parent_name,
    sp.category_name,
    sp.display_order,
    COUNT(DISTINCT subp.id) as sub_parent_count,
    COUNT(DISTINCT p.id) as total_product_count
FROM public.parent_products sp
LEFT JOIN public.parent_products subp ON subp.parent_parent_id = sp.id
LEFT JOIN public.products p ON (p.parent_product_id = subp.id OR (subp.id IS NULL AND p.parent_product_id = sp.id))
WHERE sp.hierarchy_level = 1
GROUP BY sp.id, sp.parent_code, sp.parent_name, sp.category_name, sp.display_order
ORDER BY sp.display_order;

-- ============================================================================
-- STEP 8: VERIFICATION
-- ============================================================================

-- Check results
SELECT '✅ Super Parents' as check, COUNT(*) as count FROM parent_products WHERE hierarchy_level = 1;
SELECT '✅ Sub-Parents' as check, COUNT(*) as count FROM parent_products WHERE hierarchy_level = 2;
SELECT '✅ Products Linked' as check, COUNT(*) as count FROM products WHERE parent_product_id IS NOT NULL;
SELECT '⚠️ Products Unlinked' as check, COUNT(*) as count FROM products WHERE parent_product_id IS NULL;

-- Show summary
SELECT * FROM v_super_parents_summary;

-- ============================================================================
-- COMPLETE! ✅
-- ============================================================================
COMMENT ON TABLE public.parent_products IS '7 Super Parents + 20 Sub-Parents structure for product hierarchy';