-- ============================================================================
-- AI Enrichment Fields Migration
-- ============================================================================
-- Adds fields for AI-powered enrichment of emails, contacts, conversations, and organizations
-- ============================================================================

-- ============================================================================
-- EMAILS TABLE - Classification & Analysis Fields
-- ============================================================================

ALTER TABLE public.emails ADD COLUMN IF NOT EXISTS intent VARCHAR;
COMMENT ON COLUMN public.emails.intent IS 'Primary email purpose: inquiry, order, quote_request, complaint, follow_up, meeting_request, feedback, other';

ALTER TABLE public.emails ADD COLUMN IF NOT EXISTS email_category VARCHAR;
COMMENT ON COLUMN public.emails.email_category IS 'Business classification: critical_business, new_lead, existing_customer, spam, marketing, transactional, support';

ALTER TABLE public.emails ADD COLUMN IF NOT EXISTS sentiment VARCHAR;
COMMENT ON COLUMN public.emails.sentiment IS 'Emotional tone: positive, neutral, negative, urgent';

ALTER TABLE public.emails ADD COLUMN IF NOT EXISTS priority_score INTEGER;
ALTER TABLE public.emails ADD CONSTRAINT emails_priority_score_check
  CHECK (priority_score IS NULL OR (priority_score >= 0 AND priority_score <= 100));
COMMENT ON COLUMN public.emails.priority_score IS 'AI-determined business importance (0-100)';

ALTER TABLE public.emails ADD COLUMN IF NOT EXISTS spam_score DECIMAL(3,2);
ALTER TABLE public.emails ADD CONSTRAINT emails_spam_score_check
  CHECK (spam_score IS NULL OR (spam_score >= 0 AND spam_score <= 1));
COMMENT ON COLUMN public.emails.spam_score IS 'Likelihood of spam (0.0-1.0)';

ALTER TABLE public.emails ADD COLUMN IF NOT EXISTS ai_processed_at TIMESTAMPTZ;
COMMENT ON COLUMN public.emails.ai_processed_at IS 'When AI enrichment completed';

ALTER TABLE public.emails ADD COLUMN IF NOT EXISTS ai_model_version VARCHAR;
COMMENT ON COLUMN public.emails.ai_model_version IS 'AI model used for enrichment';

ALTER TABLE public.emails ADD COLUMN IF NOT EXISTS ai_confidence_score DECIMAL(3,2);
ALTER TABLE public.emails ADD CONSTRAINT emails_ai_confidence_check
  CHECK (ai_confidence_score IS NULL OR (ai_confidence_score >= 0 AND ai_confidence_score <= 1));
COMMENT ON COLUMN public.emails.ai_confidence_score IS 'Confidence in AI classifications (0.0-1.0)';

-- Indexes for email enrichment
CREATE INDEX IF NOT EXISTS idx_emails_intent ON public.emails(intent) WHERE intent IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_emails_category ON public.emails(email_category) WHERE email_category IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_emails_priority ON public.emails(priority_score DESC) WHERE priority_score > 70;
CREATE INDEX IF NOT EXISTS idx_emails_ai_pending ON public.emails(ai_processed_at) WHERE ai_processed_at IS NULL;

-- ============================================================================
-- CONTACTS TABLE - Enrichment & Scoring Fields
-- ============================================================================

ALTER TABLE public.contacts ADD COLUMN IF NOT EXISTS enrichment_status VARCHAR DEFAULT 'pending';
COMMENT ON COLUMN public.contacts.enrichment_status IS 'Status: pending, enriched, failed, partial';

ALTER TABLE public.contacts ADD COLUMN IF NOT EXISTS enrichment_last_attempted_at TIMESTAMPTZ;
COMMENT ON COLUMN public.contacts.enrichment_last_attempted_at IS 'Last enrichment attempt timestamp';

ALTER TABLE public.contacts ADD COLUMN IF NOT EXISTS role VARCHAR;
COMMENT ON COLUMN public.contacts.role IS 'Job title/role extracted from email signature';

ALTER TABLE public.contacts ADD COLUMN IF NOT EXISTS department VARCHAR;
COMMENT ON COLUMN public.contacts.department IS 'Department name extracted from signature';

ALTER TABLE public.contacts ADD COLUMN IF NOT EXISTS lead_score INTEGER DEFAULT 0;
ALTER TABLE public.contacts ADD CONSTRAINT contacts_lead_score_check
  CHECK (lead_score >= 0 AND lead_score <= 100);
COMMENT ON COLUMN public.contacts.lead_score IS 'Cumulative engagement score (0-100)';

ALTER TABLE public.contacts ADD COLUMN IF NOT EXISTS lead_classification VARCHAR DEFAULT 'cold';
COMMENT ON COLUMN public.contacts.lead_classification IS 'hot (80-100), warm (50-79), cold (0-49)';

ALTER TABLE public.contacts ADD COLUMN IF NOT EXISTS engagement_level VARCHAR DEFAULT 'new';
COMMENT ON COLUMN public.contacts.engagement_level IS 'new, active, engaged, dormant, inactive';

-- Indexes for contact enrichment
CREATE INDEX IF NOT EXISTS idx_contacts_lead_score ON public.contacts(lead_score DESC);
CREATE INDEX IF NOT EXISTS idx_contacts_classification ON public.contacts(lead_classification);
CREATE INDEX IF NOT EXISTS idx_contacts_engagement ON public.contacts(engagement_level);
CREATE INDEX IF NOT EXISTS idx_contacts_enrichment_pending
  ON public.contacts(enrichment_status)
  WHERE enrichment_status = 'pending';

-- ============================================================================
-- CONVERSATIONS TABLE - Summary Fields
-- ============================================================================

ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS summary TEXT;
COMMENT ON COLUMN public.conversations.summary IS 'AI-generated conversation summary (2-3 sentences)';

ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS action_items TEXT[];
COMMENT ON COLUMN public.conversations.action_items IS 'Extracted next steps/tasks from conversation';

ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS last_summarized_at TIMESTAMPTZ;
COMMENT ON COLUMN public.conversations.last_summarized_at IS 'When summary was last updated';

ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS email_count_at_last_summary INTEGER DEFAULT 0;
COMMENT ON COLUMN public.conversations.email_count_at_last_summary IS 'Email count when last summarized';

-- Index for conversations needing summary
CREATE INDEX IF NOT EXISTS idx_conversations_needs_summary
  ON public.conversations(last_summarized_at, email_count)
  WHERE email_count > COALESCE(email_count_at_last_summary, 0);

-- ============================================================================
-- ORGANIZATIONS TABLE - Signature-Based Enrichment
-- ============================================================================

ALTER TABLE public.organizations ADD COLUMN IF NOT EXISTS typical_job_roles TEXT[];
COMMENT ON COLUMN public.organizations.typical_job_roles IS 'Common roles seen in this organization';

ALTER TABLE public.organizations ADD COLUMN IF NOT EXISTS contact_count INTEGER DEFAULT 0;
COMMENT ON COLUMN public.organizations.contact_count IS 'Number of contacts from this organization';

ALTER TABLE public.organizations ADD COLUMN IF NOT EXISTS enriched_from_signatures_at TIMESTAMPTZ;
COMMENT ON COLUMN public.organizations.enriched_from_signatures_at IS 'When organization was last enriched from contact signatures';

-- Index for organizations
CREATE INDEX IF NOT EXISTS idx_organizations_contact_count ON public.organizations(contact_count DESC);

-- ============================================================================
-- AI ENRICHMENT LOGS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.ai_enrichment_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  operation_type VARCHAR NOT NULL,
  -- email_classification, contact_extraction, conversation_summary

  model_used VARCHAR NOT NULL,
  items_processed INTEGER NOT NULL,

  tokens_input INTEGER,
  tokens_output INTEGER,
  estimated_cost_usd DECIMAL(10,6),

  processing_time_ms INTEGER,
  success_count INTEGER,
  error_count INTEGER,
  average_confidence DECIMAL(3,2),

  created_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE public.ai_enrichment_logs IS 'Tracks AI enrichment operations for cost and performance monitoring';

-- Indexes for enrichment logs
CREATE INDEX IF NOT EXISTS idx_ai_logs_date ON public.ai_enrichment_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_logs_operation ON public.ai_enrichment_logs(operation_type);

-- Grant permissions
GRANT ALL ON public.ai_enrichment_logs TO authenticated;
GRANT ALL ON public.ai_enrichment_logs TO service_role;

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to calculate lead classification from score
CREATE OR REPLACE FUNCTION update_lead_classification()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.lead_score >= 80 THEN
    NEW.lead_classification := 'hot';
  ELSIF NEW.lead_score >= 50 THEN
    NEW.lead_classification := 'warm';
  ELSE
    NEW.lead_classification := 'cold';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-update lead classification
DROP TRIGGER IF EXISTS trigger_update_lead_classification ON public.contacts;
CREATE TRIGGER trigger_update_lead_classification
  BEFORE INSERT OR UPDATE OF lead_score ON public.contacts
  FOR EACH ROW
  EXECUTE FUNCTION update_lead_classification();

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
