-- ============================================================================
-- PDMedical Parent Products - Link Missing Products
-- Purpose: Attach remaining products (28) to their correct parent_product hierarchies
-- ============================================================================

-- TUBE CONNECTORS
UPDATE public.products SET parent_product_id = (SELECT id FROM public.parent_products WHERE parent_code = 'TUBE_CONNECTORS_SUB')
WHERE product_code IN ('TC47PP-S', 'TC710PP-S', 'TC1014PP-S', 'TC47PP', 'TC710PP')
  AND parent_product_id IS NULL;

-- MIDOGAS UNIT
UPDATE public.products SET parent_product_id = (SELECT id FROM public.parent_products WHERE parent_code = 'MIDOGAS_UNIT')
WHERE product_code IN ('MA139', 'WARRANTY', 'DM524')
  AND parent_product_id IS NULL;

-- MIDOGAS-MINI
UPDATE public.products SET parent_product_id = (SELECT id FROM public.parent_products WHERE parent_code = 'MIDOGAS_MINI')
WHERE product_code IN ('MA140', 'MA140MSH')
  AND parent_product_id IS NULL;

-- BIOMED products (Blender Service)
UPDATE public.products SET parent_product_id = (SELECT id FROM public.parent_products WHERE parent_code = 'MIDOGAS_SERVICING')
WHERE product_code IN ('BSK-029', 'O2B', 'MSK-025')
  AND parent_product_id IS NULL;

-- SHARPS CADDY
UPDATE public.products SET parent_product_id = (SELECT id FROM public.parent_products WHERE parent_code = 'SHARPS_CADDY')
WHERE product_code LIKE 'SC-%' 
  AND product_code NOT IN ('SC-CONT-1.4L')
  AND parent_product_id IS NULL;

-- SHARPS CONTAINER
UPDATE public.products SET parent_product_id = (SELECT id FROM public.parent_products WHERE parent_code = 'SHARPS_CONTAINER')
WHERE product_code IN ('SC-CONT-1.4L', 'CC-CONT-1.3L')
  AND parent_product_id IS NULL;

-- INSTRUMENT TRAYS
UPDATE public.products SET parent_product_id = (SELECT id FROM public.parent_products WHERE parent_code = 'INSTRUMENT_TRAYS')
WHERE product_code LIKE 'ST_%'
  AND parent_product_id IS NULL;

-- SCALPEL BLADE REMOVER
UPDATE public.products SET parent_product_id = (SELECT id FROM public.parent_products WHERE parent_code = 'SCALPEL_BLADE_REMOVER')
WHERE product_code IN ('SBR1', 'SBR2')
  AND parent_product_id IS NULL;

-- BARIATRIC PAN (to MISCELLANEOUS)
UPDATE public.products SET parent_product_id = (SELECT id FROM public.parent_products WHERE parent_code = 'MISCELLANEOUS')
WHERE product_code IN ('BAR_PAN_G', 'BAR_PAN_P')
  AND parent_product_id IS NULL;

-- LINKETTES (to MISCELLANEOUS)
UPDATE public.products SET parent_product_id = (SELECT id FROM public.parent_products WHERE parent_code = 'MISCELLANEOUS')
WHERE product_code = 'DAVM633'
  AND parent_product_id IS NULL;

-- Catch-all: Link any remaining products by matching product_code patterns

-- PPE products
UPDATE public.products SET parent_product_id = (SELECT id FROM public.parent_products WHERE parent_code = 'PPE_CADDY')
WHERE product_code LIKE 'PPE-C%'
  AND parent_product_id IS NULL;

UPDATE public.products SET parent_product_id = (SELECT id FROM public.parent_products WHERE parent_code = 'PPE_ACCESSORIES')
WHERE product_code LIKE 'PPE-%'
  AND product_code NOT LIKE 'PPE-C%'
  AND parent_product_id IS NULL;

-- MIDOGAS products by code pattern
UPDATE public.products SET parent_product_id = (SELECT id FROM public.parent_products WHERE parent_code = 'MEDICAL_GAS_HOSE')
WHERE product_code LIKE 'MGHA-%'
  AND parent_product_id IS NULL;

UPDATE public.products SET parent_product_id = (SELECT id FROM public.parent_products WHERE parent_code = 'MIDOGAS_MOBILE_STAND')
WHERE (product_code LIKE 'MA142-%' OR product_code LIKE 'MA139MS%' OR product_code LIKE 'GBH-%')
  AND parent_product_id IS NULL;

UPDATE public.products SET parent_product_id = (SELECT id FROM public.parent_products WHERE parent_code = 'MIDOGAS_SPARE_PARTS')
WHERE product_code IN ('707820', 'DM489', 'DM492', 'DM493', '512258')
  AND parent_product_id IS NULL;

-- Components and assemblies
UPDATE public.products SET parent_product_id = (SELECT id FROM public.parent_products WHERE parent_code = 'COMPONENTS')
WHERE product_code LIKE '512%'
  AND parent_product_id IS NULL;

UPDATE public.products SET parent_product_id = (SELECT id FROM public.parent_products WHERE parent_code = 'SUB_ASSEMBLIES')
WHERE product_code LIKE 'DM%'
  AND product_code NOT IN ('DM524', 'DM489', 'DM492', 'DM493')
  AND parent_product_id IS NULL;

-- Breathing circuits
UPDATE public.products SET parent_product_id = (SELECT id FROM public.parent_products WHERE parent_code = 'BREATHING_CIRCUITS')
WHERE product_code LIKE 'MA143-%'
  AND parent_product_id IS NULL;

-- Gas alarms
UPDATE public.products SET parent_product_id = (SELECT id FROM public.parent_products WHERE parent_code = 'GAS_ALARM_SYSTEMS')
WHERE (product_code LIKE 'GAP%' OR product_code LIKE 'EOL-%')
  AND parent_product_id IS NULL;

-- ============================================================================
-- VERIFICATION
-- ============================================================================

SELECT '✅ Products Linked' as status, COUNT(*) as count 
FROM public.products 
WHERE parent_product_id IS NOT NULL;

SELECT '⚠️ Products Still Unlinked' as status, COUNT(*) as count 
FROM public.products 
WHERE parent_product_id IS NULL;

SELECT 
    product_code,
    product_name,
    category_name
FROM public.products 
WHERE parent_product_id IS NULL
ORDER BY product_code;

SELECT 
    sp.parent_name as super_parent,
    COUNT(DISTINCT subp.id) as sub_parents,
    COUNT(DISTINCT p.id) as products
FROM public.parent_products sp
LEFT JOIN public.parent_products subp ON subp.parent_parent_id = sp.id
LEFT JOIN public.products p ON (p.parent_product_id = subp.id OR (subp.id IS NULL AND p.parent_product_id = sp.id))
WHERE sp.hierarchy_level = 1
GROUP BY sp.parent_name, sp.display_order
ORDER BY sp.display_order;

-- ============================================================================
-- DONE! ✅
-- ============================================================================

