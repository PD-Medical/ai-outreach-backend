-- ============================================================================
-- Migration: Add Lambda Enrichment Features
-- ============================================================================
-- Description: Adds additional enrichment features from ai-outreach-lambda
-- Date: 2025-11-17
-- Source: Adapted from ai-outreach-lambda/migrations/002_add_enrichment_fields.sql
--
-- NOTE: Many enrichment fields already exist in backend. This migration adds:
--   1. System configuration table for global settings
--   2. Helper functions for category matching
--   3. Any missing fields
-- ============================================================================

-- ============================================================================
-- SYSTEM CONFIGURATION TABLE - Add Global Settings
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.system_config (
    key VARCHAR PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Insert default workflow category rules
INSERT INTO public.system_config (key, value, description)
VALUES (
    'workflow_category_rules',
    '{
        "enabled_categories": [
            "business-critical",
            "business-new_lead",
            "business-existing_customer",
            "business-new_order",
            "business-support"
        ],
        "disabled_categories": [
            "business-transactional",
            "spam-*",
            "personal-*"
        ],
        "notes": "Default category matching rules for workflows. Can be overridden per workflow."
    }'::jsonb,
    'Global default for workflow category matching rules'
)
ON CONFLICT (key) DO NOTHING;

-- Insert valid category list
INSERT INTO public.system_config (key, value, description)
VALUES (
    'valid_email_categories',
    '{
        "business": [
            "business-critical",
            "business-new_lead",
            "business-existing_customer",
            "business-new_order",
            "business-support",
            "business-transactional"
        ],
        "spam": [
            "spam-marketing",
            "spam-phishing",
            "spam-automated",
            "spam-other"
        ],
        "personal": [
            "personal-friend",
            "personal-social",
            "personal-other"
        ],
        "other": [
            "other-notification",
            "other-unknown"
        ]
    }'::jsonb,
    'Complete list of valid two-level email categories'
)
ON CONFLICT (key) DO NOTHING;

-- Insert valid intents
INSERT INTO public.system_config (key, value, description)
VALUES (
    'valid_email_intents',
    '{
        "intents": [
            "inquiry",
            "order",
            "quote_request",
            "complaint",
            "follow_up",
            "meeting_request",
            "feedback",
            "support_request",
            "other"
        ]
    }'::jsonb,
    'Valid email intent values (for business emails)'
)
ON CONFLICT (key) DO NOTHING;

-- Insert valid sentiments
INSERT INTO public.system_config (key, value, description)
VALUES (
    'valid_email_sentiments',
    '{
        "sentiments": [
            "positive",
            "neutral",
            "negative",
            "urgent"
        ]
    }'::jsonb,
    'Valid email sentiment values (for business emails)'
)
ON CONFLICT (key) DO NOTHING;

-- ============================================================================
-- VERIFY EXISTING ENRICHMENT FIELDS (Most already exist from backend migrations)
-- ============================================================================

-- Emails table - all fields already exist in backend
-- ✅ intent, email_category, sentiment, priority_score, spam_score already exist

-- Contacts table - all fields already exist in backend
-- ✅ role, department, phone, enrichment_status, enrichment_last_attempted_at already exist
-- ✅ lead_score, lead_classification, engagement_level already exist

-- Conversations table - check for action_items type mismatch
DO $$
BEGIN
    -- Check if action_items exists and is TEXT[] (backend version)
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'conversations'
        AND column_name = 'action_items'
        AND data_type = 'ARRAY'
    ) THEN
        RAISE NOTICE 'conversations.action_items already exists as TEXT[] - keeping backend version';
    -- If it doesn't exist, add as JSONB (lambda version)
    ELSIF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'conversations'
        AND column_name = 'action_items'
    ) THEN
        ALTER TABLE public.conversations ADD COLUMN action_items JSONB;
        COMMENT ON COLUMN public.conversations.action_items IS 'Array of action items extracted from conversation';
    END IF;
END $$;

-- Organizations table - all fields already exist in backend
-- ✅ typical_job_roles (as TEXT[]), contact_count, enriched_from_signatures_at already exist

-- ============================================================================
-- ADDITIONAL INDEXES (if not already created)
-- ============================================================================

-- Add index for conversations needing summary updates (if not exists)
CREATE INDEX IF NOT EXISTS idx_conversations_needs_summary
ON public.conversations(email_count, email_count_at_last_summary)
WHERE email_count > email_count_at_last_summary;

-- Add index for system config lookups
CREATE INDEX IF NOT EXISTS idx_system_config_key ON public.system_config(key);

-- ============================================================================
-- AI ENRICHMENT LOGS - Verify and Update Schema
-- ============================================================================

-- Check if ai_enrichment_logs exists and add any missing columns
DO $$
BEGIN
    -- Ensure average_confidence column exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'ai_enrichment_logs'
        AND column_name = 'average_confidence'
    ) THEN
        ALTER TABLE public.ai_enrichment_logs
        ADD COLUMN IF NOT EXISTS average_confidence DECIMAL(3,2);
    END IF;
END $$;

-- ============================================================================
-- HELPER FUNCTIONS - Enhanced Category and Intent Validation
-- ============================================================================

-- Function to validate email category
CREATE OR REPLACE FUNCTION public.is_valid_email_category(p_category VARCHAR)
RETURNS BOOLEAN AS $$
DECLARE
    valid_categories JSONB;
    category_group TEXT;
    categories JSONB;
BEGIN
    -- Get valid categories from system_config
    SELECT value INTO valid_categories
    FROM public.system_config
    WHERE key = 'valid_email_categories';

    IF valid_categories IS NULL THEN
        RETURN TRUE; -- If no validation config, allow all
    END IF;

    -- Check each category group
    FOR category_group IN SELECT jsonb_object_keys(valid_categories)
    LOOP
        categories := valid_categories->category_group;
        IF categories ? p_category THEN
            RETURN TRUE;
        END IF;
    END LOOP;

    RETURN FALSE;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION public.is_valid_email_category IS 'Validate email category against system_config list';

-- Function to validate email intent
CREATE OR REPLACE FUNCTION public.is_valid_email_intent(p_intent VARCHAR)
RETURNS BOOLEAN AS $$
DECLARE
    valid_intents JSONB;
BEGIN
    SELECT value->'intents' INTO valid_intents
    FROM public.system_config
    WHERE key = 'valid_email_intents';

    IF valid_intents IS NULL THEN
        RETURN TRUE;
    END IF;

    RETURN valid_intents ? p_intent;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION public.is_valid_email_intent IS 'Validate email intent against system_config list';

-- Function to validate email sentiment
CREATE OR REPLACE FUNCTION public.is_valid_email_sentiment(p_sentiment VARCHAR)
RETURNS BOOLEAN AS $$
DECLARE
    valid_sentiments JSONB;
BEGIN
    SELECT value->'sentiments' INTO valid_sentiments
    FROM public.system_config
    WHERE key = 'valid_email_sentiments';

    IF valid_sentiments IS NULL THEN
        RETURN TRUE;
    END IF;

    RETURN valid_sentiments ? p_sentiment;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION public.is_valid_email_sentiment IS 'Validate email sentiment against system_config list';

-- Function to get category group (business, spam, personal, other)
CREATE OR REPLACE FUNCTION public.get_category_group(p_category VARCHAR)
RETURNS VARCHAR AS $$
DECLARE
    valid_categories JSONB;
    category_group TEXT;
    categories JSONB;
BEGIN
    SELECT value INTO valid_categories
    FROM public.system_config
    WHERE key = 'valid_email_categories';

    IF valid_categories IS NULL THEN
        RETURN 'other';
    END IF;

    FOR category_group IN SELECT jsonb_object_keys(valid_categories)
    LOOP
        categories := valid_categories->category_group;
        IF categories ? p_category THEN
            RETURN category_group;
        END IF;
    END LOOP;

    RETURN 'other';
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION public.get_category_group IS 'Get category group (business/spam/personal/other) for a given category';

-- ============================================================================
-- TRIGGERS - Auto-update system_config.updated_at
-- ============================================================================

CREATE TRIGGER update_system_config_updated_at
    BEFORE UPDATE ON public.system_config
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================================
-- VIEWS - System Configuration Dashboard
-- ============================================================================

-- View for easy access to enrichment configuration
CREATE OR REPLACE VIEW public.v_enrichment_config AS
SELECT
    'valid_categories' as config_type,
    jsonb_array_length(value->'business') +
    jsonb_array_length(value->'spam') +
    jsonb_array_length(value->'personal') +
    jsonb_array_length(value->'other') as total_count,
    value as config_value
FROM public.system_config
WHERE key = 'valid_email_categories'
UNION ALL
SELECT
    'valid_intents' as config_type,
    jsonb_array_length(value->'intents') as total_count,
    value as config_value
FROM public.system_config
WHERE key = 'valid_email_intents'
UNION ALL
SELECT
    'valid_sentiments' as config_type,
    jsonb_array_length(value->'sentiments') as total_count,
    value as config_value
FROM public.system_config
WHERE key = 'valid_email_sentiments'
UNION ALL
SELECT
    'workflow_category_rules' as config_type,
    jsonb_array_length(value->'enabled_categories') +
    jsonb_array_length(value->'disabled_categories') as total_count,
    value as config_value
FROM public.system_config
WHERE key = 'workflow_category_rules';

-- View for enrichment statistics
CREATE OR REPLACE VIEW public.v_enrichment_stats AS
SELECT
    'emails' as table_name,
    COUNT(*) as total_records,
    COUNT(email_category) as enriched_category,
    COUNT(intent) as enriched_intent,
    COUNT(sentiment) as enriched_sentiment,
    COUNT(priority_score) as enriched_priority,
    ROUND(AVG(ai_confidence_score)::numeric, 2) as avg_confidence,
    COUNT(ai_processed_at) as ai_processed_count
FROM public.emails
UNION ALL
SELECT
    'contacts' as table_name,
    COUNT(*) as total_records,
    COUNT(role) as enriched_role,
    COUNT(department) as enriched_department,
    COUNT(lead_score) as enriched_lead_score,
    NULL as enriched_priority,
    NULL as avg_confidence,
    COUNT(enrichment_last_attempted_at) as ai_processed_count
FROM public.contacts
UNION ALL
SELECT
    'conversations' as table_name,
    COUNT(*) as total_records,
    COUNT(summary) as enriched_summary,
    COUNT(action_items) as enriched_action_items,
    NULL as enriched_lead_score,
    NULL as enriched_priority,
    NULL as avg_confidence,
    COUNT(last_summarized_at) as ai_processed_count
FROM public.conversations;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE public.system_config IS 'Global system configuration for enrichment rules and validation';

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT ALL ON public.system_config TO authenticated;
GRANT ALL ON public.system_config TO service_role;

-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
BEGIN
    -- Verify system_config table exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'system_config') THEN
        RAISE EXCEPTION 'Migration failed: system_config table not created';
    END IF;

    -- Verify configuration entries exist
    IF NOT EXISTS (SELECT 1 FROM public.system_config WHERE key = 'valid_email_categories') THEN
        RAISE EXCEPTION 'Migration failed: valid_email_categories config not inserted';
    END IF;

    RAISE NOTICE 'Migration 20251117000002 completed successfully!';
    RAISE NOTICE 'Added system_config table with enrichment validation rules';
    RAISE NOTICE 'Added helper functions for category/intent/sentiment validation';
END $$;

-- Migration complete!
