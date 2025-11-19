-- Migration: Add email drafts table for Email Agent with LangGraph HITL
-- This table stores email drafts created by the Email Agent for approval workflow

-- Email drafts table
CREATE TABLE public.email_drafts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Source context
  source_email_id UUID REFERENCES emails(id),
  thread_id VARCHAR,
  conversation_id UUID REFERENCES conversations(id),
  contact_id UUID REFERENCES contacts(id),

  -- Recipients
  to_emails TEXT[] NOT NULL,
  cc_emails TEXT[],
  bcc_emails TEXT[],
  from_mailbox_id UUID NOT NULL REFERENCES mailboxes(id),

  -- Content
  subject VARCHAR NOT NULL,
  body_html TEXT,
  body_plain TEXT NOT NULL,

  -- Generation context
  template_id UUID REFERENCES email_templates(id),
  product_ids UUID[],
  context_data JSONB DEFAULT '{}'::jsonb,

  -- AI metadata
  llm_model VARCHAR,
  generation_confidence DECIMAL(3,2) CHECK (generation_confidence IS NULL OR (generation_confidence >= 0 AND generation_confidence <= 1)),

  -- Approval workflow
  approval_status VARCHAR(20) DEFAULT 'pending'
    CHECK (approval_status IN ('pending', 'approved', 'rejected', 'auto_approved', 'sent')),
  approved_by UUID REFERENCES profiles(profile_id),
  approved_at TIMESTAMPTZ,
  rejection_reason TEXT,

  -- LangGraph thread reference for resume
  langgraph_thread_id VARCHAR,

  -- Workflow/Campaign reference
  workflow_execution_id UUID REFERENCES workflow_executions(id),
  campaign_enrollment_id UUID REFERENCES campaign_enrollments(id),

  -- After sending
  sent_email_id UUID REFERENCES emails(id),
  sent_at TIMESTAMPTZ,

  -- Version tracking for re-drafts (when user rejects with feedback)
  version INTEGER DEFAULT 1,
  previous_draft_id UUID REFERENCES email_drafts(id),

  -- Metadata
  created_by UUID REFERENCES profiles(profile_id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add draft_id and langgraph_thread_id to approval_queue
ALTER TABLE approval_queue ADD COLUMN IF NOT EXISTS draft_id UUID REFERENCES email_drafts(id);
ALTER TABLE approval_queue ADD COLUMN IF NOT EXISTS langgraph_thread_id VARCHAR;

-- Indexes for email_drafts
CREATE INDEX idx_email_drafts_approval_status ON email_drafts(approval_status, created_at DESC);
CREATE INDEX idx_email_drafts_pending ON email_drafts(approval_status) WHERE approval_status = 'pending';
CREATE INDEX idx_email_drafts_workflow ON email_drafts(workflow_execution_id) WHERE workflow_execution_id IS NOT NULL;
CREATE INDEX idx_email_drafts_campaign ON email_drafts(campaign_enrollment_id) WHERE campaign_enrollment_id IS NOT NULL;
CREATE INDEX idx_email_drafts_langgraph ON email_drafts(langgraph_thread_id) WHERE langgraph_thread_id IS NOT NULL;
CREATE INDEX idx_email_drafts_thread ON email_drafts(thread_id) WHERE thread_id IS NOT NULL;
CREATE INDEX idx_email_drafts_contact ON email_drafts(contact_id) WHERE contact_id IS NOT NULL;

-- Index for approval_queue draft lookup
CREATE INDEX idx_approval_queue_draft ON approval_queue(draft_id) WHERE draft_id IS NOT NULL;
CREATE INDEX idx_approval_queue_langgraph ON approval_queue(langgraph_thread_id) WHERE langgraph_thread_id IS NOT NULL;

-- Trigger to update updated_at
CREATE OR REPLACE FUNCTION update_email_drafts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_email_drafts_updated_at
  BEFORE UPDATE ON email_drafts
  FOR EACH ROW
  EXECUTE FUNCTION update_email_drafts_updated_at();

-- RLS Policies for email_drafts
ALTER TABLE email_drafts ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to view drafts
CREATE POLICY "Users can view email drafts" ON email_drafts
  FOR SELECT
  USING (true);

-- Allow authenticated users to insert drafts
CREATE POLICY "Users can create email drafts" ON email_drafts
  FOR INSERT
  WITH CHECK (true);

-- Allow authenticated users to update drafts
CREATE POLICY "Users can update email drafts" ON email_drafts
  FOR UPDATE
  USING (true);

-- Comments
COMMENT ON TABLE email_drafts IS 'Email drafts created by Email Agent for HITL approval workflow';
COMMENT ON COLUMN email_drafts.langgraph_thread_id IS 'LangGraph thread ID for resuming agent execution';
COMMENT ON COLUMN email_drafts.version IS 'Draft version number, increments when re-drafted after rejection';
COMMENT ON COLUMN email_drafts.previous_draft_id IS 'Link to previous version when re-drafting';
COMMENT ON COLUMN email_drafts.context_data IS 'JSON storing the context used for generation (thread summary, product info, etc)';

-- NOTE: LangGraph checkpointer tables are created automatically by AsyncPostgresSaver.setup()
-- No need to manually create them in this migration
