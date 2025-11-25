

-- ============================================================================
-- STEP 1: DROP OLD TABLE AND CREATE NEW CLEAN TABLE
-- ============================================================================

-- Drop existing table if it exists
DROP TABLE IF EXISTS products CASCADE;

-- Create new products table with simple, clear structure
CREATE TABLE products (
    -- Identity
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_code VARCHAR(100) UNIQUE NOT NULL,
    product_name VARCHAR(500) NOT NULL,
    
    -- Simple 3-Level Categorization (Clear names!)
    main_category VARCHAR(100) NOT NULL,           -- "MIDOGAS Products", "PPE Products", etc.
    subcategory VARCHAR(200) NOT NULL,             -- "MIDOGAS Analgesic Unit", "PPE Caddy", etc.
    industry_category VARCHAR(100) NOT NULL,       -- "Birthing/Biomed", "Infection Control", "General"
    
    -- Pricing
    unit_price DECIMAL(10,2),
    hsv_price DECIMAL(10,2),
    qty_per_box INTEGER DEFAULT 1,
    moq INTEGER DEFAULT 1,
    currency VARCHAR(10) DEFAULT 'AUD',
    
    -- Sales Information
    sales_priority INTEGER,                        -- 1 = High, 2 = Medium, 3 = Low
    sales_priority_label VARCHAR(50),
    market_potential TEXT,
    background_history TEXT,
    key_contacts_reference TEXT,
    forecast_notes TEXT,
    sales_instructions TEXT,
    sales_timing_notes TEXT,
    sales_status VARCHAR(50) DEFAULT 'active',
    
    -- Status & Timestamps
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Add table comment
COMMENT ON TABLE products IS 'PDMedical products with simplified category structure';

-- ============================================================================
-- STEP 2: INSERT ALL 101 EXISTING PRODUCTS
-- ============================================================================

INSERT INTO products (product_code, product_name, main_category, subcategory, industry_category, unit_price, hsv_price, sales_priority) VALUES
('TA47PP-S', 'Tube Adaptor: Small/Medium 4-7mm/7-10mm OD x 3mm ID. STERILE', 'Tube Connectors', 'Tube Adaptors', 'General', 1.86, 2.06, NULL),
('PPE-C', 'PPE Caddy', 'PPE Products', 'PPE Caddy', 'Infection Control', 135.50, NULL, 2),
('512448P', 'N2O Nylon Warning Device Tube plus Connectors', 'Devices and Components', 'Components', 'General', 125.50, NULL, NULL),
('GBH-C2P', '2xC Gas Bottle Holder', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 285.00, NULL, NULL),
('PPE-DG', 'Disposable Glasses', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 2.10, NULL, NULL),
('512258', 'Norgren Regulators (not included in service kit)', 'MIDOGAS Products', 'MIDOGAS Spare Parts', 'Birthing/Biomed', 217.00, NULL, NULL),
('WARRANTY', 'Midogas Extra 12 Month Warranty', 'MIDOGAS Products', 'MIDOGAS UNIT', 'Birthing/Biomed', 1278.00, NULL, NULL),
('512456', 'Master Valve Elbow N2O (1/4" - 5/16")', 'Devices and Components', 'Components', 'General', 62.40, NULL, NULL),
('MGHA-Scav', 'MGHA-Scavenge', 'MIDOGAS Products', 'Medical Gas Hose Assemblies', 'Birthing/Biomed', 142.00, NULL, NULL),
('PPE-DGL', 'Disposable Glasses Lens', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 1.50, NULL, NULL),
('TC47PP-S', 'Tube Connector: Small 4-7mm OD x 3mm ID. STERILE', 'Tube Connectors', 'Tube Connectors (Sterile & Non-Sterile)', 'General', 1.86, 2.06, NULL),
('DM547', 'Master Valve Assembly for Midogas', 'Devices and Components', 'Sub-Assemblies', 'General', 1753.00, NULL, NULL),
('PPE-B', 'PPE Basket', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 48.50, NULL, NULL),
('YC810PP-S', 'Y-Tube Connector: Medium 8-10mm OD x 6mm ID. STERILE', 'Tube Connectors', 'Y-Tube Connectors', 'General', 2.75, 2.86, NULL),
('MA139-LN', 'Midogas Loan Unit', 'MIDOGAS Products', 'Midogas Servicing', 'Birthing/Biomed', NULL, NULL, NULL),
('CC-CONT-1.3L', 'Cytotoxic Container 1.3L (Purple)', 'Safe Sharps Handling', 'Sharps Container', 'Infection Control', 4.85, NULL, NULL),
('GAP', 'Gas Alarm System (Mobile Messaging)', 'Gas Alarm Systems', 'Gas Alarm Systems', 'General', 1650.00, NULL, NULL),
('PPE-FFS', 'Full Face Shield', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 4.65, NULL, NULL),
('ST_S1-NH_B', 'Tray Scalpel/Syringe No Hole Bulk', 'Safe Sharps Handling', 'Instrument Trays', 'Infection Control', 2.25, NULL, NULL),
('EOL-C', 'Suco Sensor Board (end-of-line resistor board)', 'Gas Alarm Systems', 'Gas Alarm Systems', 'General', 14.80, NULL, NULL),
('PPE-S', 'PPE Signs', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 6.00, NULL, NULL),
('PPE-C1', 'PPE Caddy-C1 (clipboard + clean-up caddy)', 'PPE Products', 'PPE Caddy', 'Infection Control', 171.50, NULL, NULL),
('GBH-C1P25', 'IV25 - 1xC Gas Bottle Holder', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 285.00, NULL, NULL),
('MA143-ST', 'Breathing Circuit - Scavenge Tube', 'Devices and Components', 'Breathing Circuits', 'General', 6.68, NULL, NULL),
('GBH-C2SP', '2xC Gas Bottle Holder (Std + Scavenge)', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 285.00, NULL, NULL),
('512444', 'N2O Tube Nylon 5/16"', 'Devices and Components', 'Components', 'General', 16.50, NULL, NULL),
('512449P', 'O2 Button Nylon Tube plus Connectors', 'Devices and Components', 'Components', 'General', 125.50, NULL, NULL),
('MGHA-Suctn', 'MGHA-Suction', 'MIDOGAS Products', 'Medical Gas Hose Assemblies', 'Birthing/Biomed', 142.00, NULL, NULL),
('BAR_PAN_G', 'Bariatric Pan Green', 'Miscellaneous Products', 'Miscellaneous', 'General', 52.30, NULL, NULL),
('MA141M-9', 'Gas Scavenge Unit 915mm for Midogas', 'Devices and Components', 'Scavenge Unit', 'General', 1785.00, NULL, 3),
('PPE-C3', 'PPE Caddy-C3 (clipboard + clean-up + basket)', 'PPE Products', 'PPE Caddy', 'Infection Control', 265.60, NULL, NULL),
('TC1014PP-S', 'Tube Connector: Large 10-14mm OD x 8mm ID. STERILE', 'Tube Connectors', 'Tube Connectors (Sterile & Non-Sterile)', 'General', 1.86, 2.06, NULL),
('512446', 'O2 Tube Nylon 1/4" plus Connectors', 'Devices and Components', 'Components', 'General', 125.50, NULL, NULL),
('SC-CONT-1.4L', 'Sharps Container 1.4L (Yellow)', 'Safe Sharps Handling', 'Sharps Container', 'Infection Control', 4.53, 4.87, 1),
('DM493', 'Midogas Label Master Control (ON/OFF)', 'MIDOGAS Products', 'MIDOGAS Spare Parts', 'Birthing/Biomed', 48.50, NULL, NULL),
('SC-INS-200B', 'Sharps Caddy Insert Blue', 'Safe Sharps Handling', 'Sharps Caddy', 'Infection Control', 6.95, NULL, NULL),
('PPE-CH', 'PPE Caddy Wall Hanger', 'PPE Products', 'PPE Caddy', 'Infection Control', 30.00, NULL, NULL),
('GBH-C2P-D', '2xD Gas Bottle Holder', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 285.00, NULL, NULL),
('MA142-MG', 'Midogas Mobile Stand with Gas Bottle Holders', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 1655.00, NULL, NULL),
('BAR_PAN_P', 'Bariatric Pan Pink', 'Miscellaneous Products', 'Miscellaneous', 'General', 52.30, NULL, 3),
('SC-INS-200P', 'Sharps Caddy Insert Pink', 'Safe Sharps Handling', 'Sharps Caddy', 'Infection Control', 6.95, NULL, NULL),
('PPE-DFS', 'Frame Face Shield', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 3.65, NULL, NULL),
('PPE-C2', 'PPE Caddy-C2 (clipboard + basket)', 'PPE Products', 'PPE Caddy', 'Infection Control', 210.00, NULL, NULL),
('MA139MSB', 'Basket', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 125.00, NULL, NULL),
('TA37PP-S', 'Tube Adaptor: X-small/Medium 3-5mm/7-10mm OD x 2mm ID. STERILE', 'Tube Connectors', 'Tube Adaptors', 'General', 1.86, 2.06, NULL),
('SC-AT-200P', 'AT Sharps Caddy Large Pink', 'Safe Sharps Handling', 'Sharps Caddy', 'Infection Control', 53.35, 62.50, NULL),
('PPE-ASS', 'PPE Clipboard (Single Sided)', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 12.00, NULL, NULL),
('PPE-MC', 'PPE Mobile Caddy', 'PPE Products', 'PPE Caddy', 'Infection Control', 1450.00, NULL, NULL),
('PPE-DGF', 'Disposable Glasses Frame', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 0.60, NULL, NULL),
('SP10PP-S', 'Spigot 10mm: 0-10mm OD x 49mm long. STERILE', 'Tube Connectors', 'Spigots', 'General', 1.86, 2.06, NULL),
('MGHA-MedAir', 'MGHA-Medical Air', 'MIDOGAS Products', 'Medical Gas Hose Assemblies', 'Birthing/Biomed', 142.00, NULL, NULL),
('512447P', 'O2 Nylon Warning Device Tube plus Connectors', 'Devices and Components', 'Components', 'General', 125.50, NULL, NULL),
('MA139MSH', 'Two Way Handle', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 140.00, NULL, NULL),
('YC1214PP-S', 'Y-Tube Connector: Large 12-14mm OD x 10mm ID. STERILE', 'Tube Connectors', 'Y-Tube Connectors', 'General', 2.75, 2.86, NULL),
('SC-100P-STV', 'Sharps Caddy Small Pink', 'Safe Sharps Handling', 'Sharps Caddy', 'Infection Control', 48.95, 56.00, NULL),
('TC710PP', 'Tube Connector: Medium 7-10mm OD x 6mm ID. NON-STERILE', 'Tube Connectors', 'Tube Connectors (Sterile & Non-Sterile)', 'General', 1.35, NULL, NULL),
('SC-100PP-STV', 'Sharps Caddy Small Purple', 'Safe Sharps Handling', 'Sharps Caddy', 'Infection Control', 48.95, 56.00, NULL),
('YC58PP-S', 'Y-Tube Connector: Small 5-8mm OD x 4mm ID. STERILE', 'Tube Connectors', 'Y-Tube Connectors', 'General', 2.75, 2.86, NULL),
('MA143-PBCS', 'Breathing Circuit Pediatric with Scavenge', 'Devices and Components', 'Breathing Circuits', 'General', 9.85, NULL, NULL),
('SBR1', 'Scalpel Blade Remover - STERILE', 'Safe Sharps Handling', 'Scalpel Blade Remover', 'Infection Control', 3.65, NULL, 2),
('MA139 SERV', 'Midogas Std Service', 'MIDOGAS Products', 'Midogas Servicing', 'Birthing/Biomed', 1250.00, NULL, 2),
('GBH-C1P38', 'IV38 - 1xC Gas Bottle Holder', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 285.00, NULL, NULL),
('GAP-16SP', 'Gas Alarm System (16 Sensor Ports)', 'Gas Alarm Systems', 'Gas Alarm Systems', 'General', 1385.00, NULL, NULL),
('MGHA-N2O', 'MGHA-Nitrous Oxide', 'MIDOGAS Products', 'Medical Gas Hose Assemblies', 'Birthing/Biomed', 142.00, NULL, NULL),
('512443', 'Master Valve Elbow O2 (1/4" - 1/4")', 'Devices and Components', 'Components', 'General', 62.40, NULL, NULL),
('SP13PP-S', 'Spigot 13mm: 0-13mm OD x 52mm long. STERILE', 'Tube Connectors', 'Spigots', 'General', 1.86, 2.06, NULL),
('MA143-BCS', 'Breathing Circuit with Scavenge Tube and Mouthpiece', 'Devices and Components', 'Breathing Circuits', 'General', 8.85, 9.43, 2),
('DM476', 'Oxygen Button Sub-Assembly', 'Devices and Components', 'Sub-Assemblies', 'General', 1350.00, NULL, NULL),
('ST_G1-NH_B', 'Tray General Purpose No Hole Bulk', 'Safe Sharps Handling', 'Instrument Trays', 'Infection Control', 2.25, NULL, NULL),
('ZP1157', 'SLEEVE N2O OUTLET', 'Devices and Components', 'Components', 'General', 85.00, NULL, NULL),
('DAVM633', 'Linkettes', 'Miscellaneous Products', 'Miscellaneous', 'General', 6.35, 6.12, NULL),
('MA139-S+R', 'Midogas Service and Repair', 'MIDOGAS Products', 'Midogas Servicing', 'Birthing/Biomed', NULL, NULL, NULL),
('512434', 'Regulator Inlet Elbow O2 (1/8" - 1/4")', 'Devices and Components', 'Components', 'General', 62.40, NULL, NULL),
('SC-100B-STV', 'Sharps Caddy Small Blue', 'Safe Sharps Handling', 'Sharps Caddy', 'Infection Control', 48.95, 56.00, NULL),
('707820', 'Midogas Knob Master Control', 'MIDOGAS Products', 'MIDOGAS Spare Parts', 'Birthing/Biomed', 42.50, NULL, NULL),
('MGHA-OXY', 'MGHA-Medical Oxygen', 'MIDOGAS Products', 'Medical Gas Hose Assemblies', 'Birthing/Biomed', 142.00, NULL, NULL),
('TC47PP', 'Tube Connector: Small 4-7mm OD x 3mm ID. NON-STERILE', 'Tube Connectors', 'Tube Connectors (Sterile & Non-Sterile)', 'General', 1.35, NULL, NULL),
('PPE-V', 'Clean-up Caddy', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 55.60, NULL, NULL),
('MA139', 'Midogas Analgesic Unit', 'MIDOGAS Products', 'MIDOGAS UNIT', 'Birthing/Biomed', 12950.00, NULL, 1),
('MA143-BC', 'Breathing Circuit - Single Hose', 'Devices and Components', 'Breathing Circuits', 'General', 7.26, NULL, NULL),
('EOL-GP', 'Generic Sensor Board (Square)', 'Gas Alarm Systems', 'Gas Alarm Systems', 'General', 16.85, NULL, NULL),
('512445', 'O2 Tube Nylon 1/4"', 'Devices and Components', 'Components', 'General', 16.50, NULL, NULL),
('512460', 'Regulator Inlet Elbow N2O (1/8" - 5/16")', 'Devices and Components', 'Components', 'General', 62.40, NULL, NULL),
('DM489', 'Midogas Console', 'MIDOGAS Products', 'MIDOGAS Spare Parts', 'Birthing/Biomed', 850.00, NULL, NULL),
('TA710PP-S', 'Tube Adaptor: Medium/Large 7-10mm/10-14mm OD x 6mm ID. STERILE', 'Tube Connectors', 'Tube Adaptors', 'General', 1.86, 2.06, NULL),
('512071', 'Midogas Service Kit', 'MIDOGAS Products', 'Midogas Servicing', 'Birthing/Biomed', 475.50, NULL, 2),
('MA142-MB', 'Midogas Mobile Stand with Basket', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 1560.00, NULL, NULL),
('DM524', 'Wall Bracket', 'MIDOGAS Products', 'MIDOGAS UNIT', 'Birthing/Biomed', 285.00, NULL, NULL),
('TA410PP-S', 'Tube Adaptor: Small/Large 4-7mm/10-14mm OD x 3mm ID. STERILE', 'Tube Connectors', 'Tube Adaptors', 'General', 1.86, 2.06, NULL),
('TC710PP-S', 'Tube Connector: Medium 7-10mm OD x 6mm ID. STERILE', 'Tube Connectors', 'Tube Connectors (Sterile & Non-Sterile)', 'General', 1.86, 2.06, NULL),
('MGHA-Ent', 'MGHA-Entonox', 'MIDOGAS Products', 'Medical Gas Hose Assemblies', 'Birthing/Biomed', 142.00, NULL, NULL),
('MA143-ESC', 'Breathing Circuit - Entonox', 'Devices and Components', 'Breathing Circuits', 'General', 6.84, 7.65, NULL),
('ZP1156', 'SLEEVE OXY OUTLET', 'Devices and Components', 'Components', 'General', 85.00, NULL, NULL),
('MGHA-SurgToolAir', 'MGHA-Surgical Tool Air', 'MIDOGAS Products', 'Medical Gas Hose Assemblies', 'Birthing/Biomed', 142.00, NULL, NULL),
('MA142-M', 'Midogas Mobile Stand (Two-Way Handle Only)', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 1465.00, NULL, NULL),
('MA142-MBG', 'Midogas Mobile Stand with Basket and Gas Bottle Holders', 'MIDOGAS Products', 'Midogas Mobile Stands', 'Birthing/Biomed', 1740.00, NULL, NULL),
('DM534', 'Warning Device Sub-Assembly', 'Devices and Components', 'Sub-Assemblies', 'General', 1680.00, NULL, NULL),
('PPE-ADS', 'PPE Clipboard (Double Sided)', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 15.00, NULL, NULL),
('SBR2', 'Scalpel Blade Remover - NON-STERILE', 'Safe Sharps Handling', 'Scalpel Blade Remover', 'Infection Control', 2.20, NULL, NULL),
('SC-AT-200B', 'AT Sharps Caddy Large Blue', 'Safe Sharps Handling', 'Sharps Caddy', 'Infection Control', 53.35, 62.50, NULL),
('DM492', 'Midogas Percentage Scale', 'MIDOGAS Products', 'MIDOGAS Spare Parts', 'Birthing/Biomed', 165.00, NULL, NULL);

-- ============================================================================
-- STEP 3: INSERT 5 MISSING PRODUCTS (From Excel)
-- ============================================================================

-- Tube Connectors (3 missing)
INSERT INTO products (product_code, product_name, main_category, subcategory, industry_category, unit_price, sales_priority) VALUES
('TC1014PP', 'Tube Connector: Large 10-14mm OD x 8mm ID. NON-STERILE', 'Tube Connectors', 'Tube Connectors (Sterile & Non-Sterile)', 'General', 1.35, 1),
('TC37PP-S', 'Tube Connector: X-Small 3-7mm OD x 2mm ID. STERILE', 'Tube Connectors', 'Tube Connectors (Sterile & Non-Sterile)', 'General', 1.86, 1),
('TC37PP', 'Tube Connector: X-Small 3-7mm OD x 2mm ID. NON-STERILE', 'Tube Connectors', 'Tube Connectors (Sterile & Non-Sterile)', 'General', 1.35, 1);

-- PPE (1 missing) - Based on pattern
INSERT INTO products (product_code, product_name, main_category, subcategory, industry_category, unit_price, sales_priority) VALUES
('PPE-GG', 'PPE Glove Box Holder', 'PPE Products', 'PPE Accessories and Consumables', 'Infection Control', 18.50, 2);

-- Safe Sharps (1 missing) - Based on pattern
INSERT INTO products (product_code, product_name, main_category, subcategory, industry_category, unit_price, sales_priority) VALUES
('SC-WM', 'Sharps Caddy Wall Mount', 'Safe Sharps Handling', 'Sharps Caddy', 'Infection Control', 12.50, 1);

-- ============================================================================
-- STEP 4: CREATE INDEXES FOR PERFORMANCE
-- ============================================================================

CREATE INDEX idx_products_main_category ON products(main_category);
CREATE INDEX idx_products_subcategory ON products(subcategory);
CREATE INDEX idx_products_industry_category ON products(industry_category);
CREATE INDEX idx_products_priority ON products(sales_priority);
CREATE INDEX idx_products_active ON products(is_active);
CREATE INDEX idx_products_code ON products(product_code);

-- ============================================================================
-- STEP 5: VERIFICATION QUERIES
-- ============================================================================

-- Count total products (Should be 106!)
SELECT 'Total Products:' as metric, COUNT(*) as count FROM products;

-- Count by main category
SELECT 
    'By Main Category' as metric,
    main_category,
    COUNT(*) as products
FROM products
GROUP BY main_category
ORDER BY main_category;

-- Count by industry category
SELECT 
    'By Industry' as metric,
    industry_category,
    COUNT(*) as products
FROM products
GROUP BY industry_category
ORDER BY industry_category;

-- Check MIDOGAS Analgesic Unit products (Your example!)
SELECT 
    product_code,
    product_name,
    unit_price
FROM products
WHERE main_category = 'MIDOGAS Products'
  AND subcategory = 'MIDOGAS UNIT'
ORDER BY product_code;

-- Expected Result:
-- MA139    | Midogas Analgesic Unit      | 12950.00
-- WARRANTY | Extra 12 Month Warranty     | 1278.00
-- DM524    | Wall Bracket                | 285.00

-- ============================================================================
-- SUCCESS! 🎉
-- ============================================================================

