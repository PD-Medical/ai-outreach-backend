-- Migration: Campaign Targeting Enhancements
-- Purpose: Add support for form-based and natural language target selection for campaigns

-- ============================================================================
-- CAMPAIGN_SEQUENCES TABLE ENHANCEMENTS
-- ============================================================================

-- Add columns for target selection modes and configuration
ALTER TABLE public.campaign_sequences
ADD COLUMN IF NOT EXISTS filter_config JSONB DEFAULT '{}',
ADD COLUMN IF NOT EXISTS target_mode VARCHAR(20) DEFAULT 'form',
ADD COLUMN IF NOT EXISTS natural_language_query TEXT,
ADD COLUMN IF NOT EXISTS daily_limit INTEGER DEFAULT 50,
ADD COLUMN IF NOT EXISTS batch_size INTEGER DEFAULT 20,
ADD COLUMN IF NOT EXISTS send_time TIME DEFAULT '09:00',
ADD COLUMN IF NOT EXISTS timezone VARCHAR(50) DEFAULT 'Australia/Sydney',
ADD COLUMN IF NOT EXISTS exclude_weekends BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS exclusion_config JSONB DEFAULT '{
  "exclude_unsubscribed": true,
  "exclude_bounced": true,
  "exclude_active_campaigns": false,
  "exclude_contacted_days": null,
  "exclude_campaign_ids": []
}'::jsonb,
ADD COLUMN IF NOT EXISTS action_type VARCHAR(50) DEFAULT 'send_email',
ADD COLUMN IF NOT EXISTS action_config JSONB DEFAULT '{}',
ADD COLUMN IF NOT EXISTS approval_required BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS target_locked_at TIMESTAMPTZ;

-- Make target_sql nullable since form-based selection generates it on the fly
ALTER TABLE public.campaign_sequences
ALTER COLUMN target_sql DROP NOT NULL;

-- Add constraint for target_mode
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'campaign_sequences_target_mode_check'
    ) THEN
        ALTER TABLE public.campaign_sequences
        ADD CONSTRAINT campaign_sequences_target_mode_check
        CHECK (target_mode IN ('form', 'natural_language'));
    END IF;
END $$;

-- Add constraint for action_type
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'campaign_sequences_action_type_check'
    ) THEN
        ALTER TABLE public.campaign_sequences
        ADD CONSTRAINT campaign_sequences_action_type_check
        CHECK (action_type IN ('send_email', 'update_lead_score', 'both'));
    END IF;
END $$;

-- ============================================================================
-- CAMPAIGN_ENROLLMENTS TABLE ENHANCEMENTS
-- ============================================================================

-- Add columns for better tracking of enrollment lifecycle
ALTER TABLE public.campaign_enrollments
ADD COLUMN IF NOT EXISTS enrolled_by VARCHAR(50) DEFAULT 'system',
ADD COLUMN IF NOT EXISTS action_executed_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS action_result JSONB;

-- ============================================================================
-- EMAIL_DRAFTS TABLE ENHANCEMENTS
-- ============================================================================

-- Add columns to show source context in approval UI
ALTER TABLE public.email_drafts
ADD COLUMN IF NOT EXISTS source_type VARCHAR(20) DEFAULT 'manual',
ADD COLUMN IF NOT EXISTS source_name TEXT,
ADD COLUMN IF NOT EXISTS source_details JSONB DEFAULT '{}';

-- Add constraint for source_type
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'email_drafts_source_type_check'
    ) THEN
        ALTER TABLE public.email_drafts
        ADD CONSTRAINT email_drafts_source_type_check
        CHECK (source_type IN ('manual', 'workflow', 'campaign'));
    END IF;
END $$;

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Index for campaign executor to efficiently find due enrollments
CREATE INDEX IF NOT EXISTS idx_campaign_enrollments_due
ON public.campaign_enrollments (next_send_date, status)
WHERE status = 'enrolled';

-- Index for campaign sequences by status
CREATE INDEX IF NOT EXISTS idx_campaign_sequences_status_scheduled
ON public.campaign_sequences (status, scheduled_at)
WHERE status IN ('scheduled', 'running');

-- ============================================================================
-- RPC FUNCTION: Get filter options for campaign form builder
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_campaign_filter_options()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'lead_classifications', COALESCE(
      (SELECT jsonb_agg(DISTINCT lead_classification ORDER BY lead_classification)
       FROM contacts
       WHERE lead_classification IS NOT NULL AND lead_classification != ''),
      '[]'::jsonb
    ),
    'engagement_levels', COALESCE(
      (SELECT jsonb_agg(DISTINCT engagement_level ORDER BY engagement_level)
       FROM contacts
       WHERE engagement_level IS NOT NULL AND engagement_level != ''),
      '[]'::jsonb
    ),
    'contact_statuses', COALESCE(
      (SELECT jsonb_agg(DISTINCT status ORDER BY status)
       FROM contacts
       WHERE status IS NOT NULL AND status != ''),
      '[]'::jsonb
    ),
    'regions', COALESCE(
      (SELECT jsonb_agg(DISTINCT region ORDER BY region)
       FROM organizations
       WHERE region IS NOT NULL AND region != ''),
      '[]'::jsonb
    ),
    'states', COALESCE(
      (SELECT jsonb_agg(DISTINCT state ORDER BY state)
       FROM organizations
       WHERE state IS NOT NULL AND state != ''),
      '[]'::jsonb
    ),
    'hospital_categories', COALESCE(
      (SELECT jsonb_agg(DISTINCT hospital_category ORDER BY hospital_category)
       FROM organizations
       WHERE hospital_category IS NOT NULL AND hospital_category != ''),
      '[]'::jsonb
    ),
    'facility_types', COALESCE(
      (SELECT jsonb_agg(DISTINCT facility_type ORDER BY facility_type)
       FROM organizations
       WHERE facility_type IS NOT NULL AND facility_type != ''),
      '[]'::jsonb
    ),
    'industries', COALESCE(
      (SELECT jsonb_agg(DISTINCT industry ORDER BY industry)
       FROM organizations
       WHERE industry IS NOT NULL AND industry != ''),
      '[]'::jsonb
    ),
    'departments', COALESCE(
      (SELECT jsonb_agg(DISTINCT department ORDER BY department)
       FROM contacts
       WHERE department IS NOT NULL AND department != ''),
      '[]'::jsonb
    ),
    'tags', COALESCE(
      (SELECT jsonb_agg(DISTINCT tag ORDER BY tag)
       FROM contacts, jsonb_array_elements_text(tags) AS tag
       WHERE tags IS NOT NULL AND tags != '[]'::jsonb),
      '[]'::jsonb
    ),
    'mailboxes', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object('id', id, 'email', email, 'name', name) ORDER BY name)
       FROM mailboxes
       WHERE is_active = true),
      '[]'::jsonb
    )
  ) INTO result;

  RETURN result;
END;
$$;

-- ============================================================================
-- RPC FUNCTION: Execute campaign target preview SQL safely
-- ============================================================================

CREATE OR REPLACE FUNCTION public.exec_campaign_preview_sql(query TEXT, preview_limit INTEGER DEFAULT 100)
RETURNS TABLE(
  total_count BIGINT,
  preview_results JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  count_result BIGINT;
  preview_json JSONB;
  clean_query TEXT;
BEGIN
  -- Security: Only allow SELECT statements
  clean_query := TRIM(query);
  IF NOT (LOWER(clean_query) LIKE 'select%') THEN
    RAISE EXCEPTION 'Only SELECT statements are allowed';
  END IF;

  -- Security: Block dangerous keywords
  IF LOWER(clean_query) ~ '\b(drop|delete|update|insert|alter|create|truncate|grant|revoke)\b' THEN
    RAISE EXCEPTION 'Dangerous SQL keyword detected';
  END IF;

  -- Get total count
  EXECUTE 'SELECT COUNT(*) FROM (' || clean_query || ') AS subquery' INTO count_result;

  -- Get preview with limit
  EXECUTE 'SELECT COALESCE(jsonb_agg(row_to_json(t)), ''[]''::jsonb) FROM ('
    || clean_query
    || ' LIMIT ' || preview_limit
    || ') AS t' INTO preview_json;

  RETURN QUERY SELECT count_result, preview_json;
END;
$$;

-- ============================================================================
-- VIEW: Campaign enrollments due for processing
-- ============================================================================

DROP VIEW IF EXISTS public.v_campaign_enrollments_due;
CREATE VIEW public.v_campaign_enrollments_due AS
SELECT
  ce.id AS enrollment_id,
  ce.campaign_sequence_id,
  ce.contact_id,
  ce.current_step,
  ce.next_send_date,
  ce.status AS enrollment_status,
  cs.name AS campaign_name,
  cs.action_type,
  cs.action_config,
  cs.from_mailbox_id,
  cs.approval_required,
  cs.batch_size,
  cs.daily_limit,
  c.email AS contact_email,
  c.first_name AS contact_first_name,
  c.last_name AS contact_last_name,
  c.organization_id,
  o.name AS organization_name
FROM campaign_enrollments ce
JOIN campaign_sequences cs ON ce.campaign_sequence_id = cs.id
JOIN contacts c ON ce.contact_id = c.id
LEFT JOIN organizations o ON c.organization_id = o.id
WHERE
  ce.status = 'enrolled'
  AND ce.next_send_date <= NOW()
  AND cs.status = 'running';

-- ============================================================================
-- BACKFILL: Update existing email_drafts with source tracking
-- ============================================================================

-- Set source_type for existing workflow-generated drafts
UPDATE public.email_drafts
SET
  source_type = 'workflow',
  source_name = w.name,
  source_details = jsonb_build_object('workflow_id', w.id, 'workflow_name', w.name)
FROM workflow_executions we
JOIN workflows w ON we.workflow_id = w.id
WHERE email_drafts.workflow_execution_id = we.id
AND (email_drafts.source_type IS NULL OR email_drafts.source_type = 'manual')
AND email_drafts.workflow_execution_id IS NOT NULL;

-- Set source_type for existing campaign-generated drafts
UPDATE public.email_drafts
SET
  source_type = 'campaign',
  source_name = cs.name,
  source_details = jsonb_build_object(
    'campaign_id', cs.id,
    'campaign_name', cs.name,
    'enrollment_id', email_drafts.campaign_enrollment_id
  )
FROM campaign_enrollments ce
JOIN campaign_sequences cs ON ce.campaign_sequence_id = cs.id
WHERE email_drafts.campaign_enrollment_id = ce.id
AND (email_drafts.source_type IS NULL OR email_drafts.source_type = 'manual')
AND email_drafts.campaign_enrollment_id IS NOT NULL;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON COLUMN public.campaign_sequences.filter_config IS 'JSON configuration for form-based target selection filters';
COMMENT ON COLUMN public.campaign_sequences.target_mode IS 'Target selection mode: form (form builder) or natural_language (AI-powered)';
COMMENT ON COLUMN public.campaign_sequences.natural_language_query IS 'Original natural language query used for targeting (for reference/audit)';
COMMENT ON COLUMN public.campaign_sequences.exclusion_config IS 'Configuration for excluding contacts from targeting';
COMMENT ON COLUMN public.campaign_sequences.action_type IS 'Type of action to perform: send_email, update_lead_score, or both';
COMMENT ON COLUMN public.campaign_sequences.action_config IS 'Configuration specific to the action type (email purpose, score delta, etc.)';
COMMENT ON COLUMN public.campaign_sequences.approval_required IS 'Whether emails require human approval before sending';
COMMENT ON COLUMN public.campaign_sequences.target_locked_at IS 'Timestamp when targets were locked in for the campaign';

COMMENT ON COLUMN public.email_drafts.source_type IS 'Source of the draft: manual, workflow, or campaign';
COMMENT ON COLUMN public.email_drafts.source_name IS 'Human-readable name of the source (workflow name, campaign name)';
COMMENT ON COLUMN public.email_drafts.source_details IS 'Additional details about the source for UI display';

COMMENT ON FUNCTION public.get_campaign_filter_options() IS 'Returns distinct values for campaign target filter dropdowns';
COMMENT ON FUNCTION public.exec_campaign_preview_sql(TEXT, INTEGER) IS 'Safely executes campaign targeting SQL and returns preview results';
COMMENT ON VIEW public.v_campaign_enrollments_due IS 'View of campaign enrollments that are due for processing';
