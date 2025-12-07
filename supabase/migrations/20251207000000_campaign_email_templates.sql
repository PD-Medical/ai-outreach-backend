-- Migration: Campaign Email Templates
-- Purpose: Add template-based email generation for campaigns (economical alternative to per-contact AI)

-- ============================================================================
-- CAMPAIGN_SEQUENCES TABLE ENHANCEMENTS
-- ============================================================================

-- Add columns for email template mode and storage
ALTER TABLE public.campaign_sequences
ADD COLUMN IF NOT EXISTS email_mode VARCHAR(20) DEFAULT 'template',
ADD COLUMN IF NOT EXISTS email_template_subject TEXT,
ADD COLUMN IF NOT EXISTS email_template_body TEXT,
ADD COLUMN IF NOT EXISTS template_status VARCHAR(20) DEFAULT 'none',
ADD COLUMN IF NOT EXISTS template_generated_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS template_approved_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS auto_approve_enabled BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS auto_approve_threshold INTEGER DEFAULT 80;

-- Add constraint for email_mode
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'campaign_sequences_email_mode_check'
    ) THEN
        ALTER TABLE public.campaign_sequences
        ADD CONSTRAINT campaign_sequences_email_mode_check
        CHECK (email_mode IN ('personalized', 'template'));
    END IF;
END $$;

-- Add constraint for template_status
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'campaign_sequences_template_status_check'
    ) THEN
        ALTER TABLE public.campaign_sequences
        ADD CONSTRAINT campaign_sequences_template_status_check
        CHECK (template_status IN ('none', 'generating', 'pending_approval', 'approved', 'rejected'));
    END IF;
END $$;

-- ============================================================================
-- UPDATE VIEW: Campaign enrollments due for processing
-- Add template-related fields for executor to use
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
  -- New template fields
  cs.email_mode,
  cs.email_template_subject,
  cs.email_template_body,
  cs.template_status,
  cs.auto_approve_enabled,
  cs.auto_approve_threshold,
  -- Contact fields (for template substitution)
  c.email AS contact_email,
  c.first_name AS contact_first_name,
  c.last_name AS contact_last_name,
  c.job_title AS contact_job_title,
  c.department AS contact_department,
  c.organization_id,
  -- Organization fields (for template substitution)
  o.name AS organization_name,
  o.industry AS organization_industry,
  o.city AS organization_city,
  o.state AS organization_state,
  o.region AS organization_region,
  o.facility_type AS organization_facility_type,
  o.hospital_category AS organization_hospital_category
FROM campaign_enrollments ce
JOIN campaign_sequences cs ON ce.campaign_sequence_id = cs.id
JOIN contacts c ON ce.contact_id = c.id
LEFT JOIN organizations o ON c.organization_id = o.id
WHERE
  ce.status = 'enrolled'
  AND ce.next_send_date <= NOW()
  AND cs.status = 'running';

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON COLUMN public.campaign_sequences.email_mode IS 'Email generation mode: template (1 AI call, field substitution) or personalized (AI per contact)';
COMMENT ON COLUMN public.campaign_sequences.email_template_subject IS 'Email template subject with merge fields like {first_name}, {company}';
COMMENT ON COLUMN public.campaign_sequences.email_template_body IS 'Email template body with merge fields for personalization';
COMMENT ON COLUMN public.campaign_sequences.template_status IS 'Status of template: none, generating, pending_approval, approved, rejected';
COMMENT ON COLUMN public.campaign_sequences.template_generated_at IS 'Timestamp when AI generated the template';
COMMENT ON COLUMN public.campaign_sequences.template_approved_at IS 'Timestamp when user approved the template';
COMMENT ON COLUMN public.campaign_sequences.auto_approve_enabled IS 'Whether to auto-approve and send emails without HITL review';
COMMENT ON COLUMN public.campaign_sequences.auto_approve_threshold IS 'Confidence threshold (0-100) for auto-approval (mainly for personalized mode)';

COMMENT ON VIEW public.v_campaign_enrollments_due IS 'View of campaign enrollments due for processing, includes template data and contact/org fields for substitution';
