-- ================================================================================
-- UNIFIED CAMPAIGN + WORKFLOW ENGAGEMENT TRACKING
-- ================================================================================
-- Purpose: 
--   Connect campaigns and workflows into one unified engagement system
--   Enable tracking of workflow-generated emails alongside campaign emails
--   Support analytics across both campaign and workflow channels
--
-- Changes:
--   - Links campaign_events to workflow_executions and drafts
--   - Adds contact tracking to workflow_executions
--   - Enhances campaign_contact_summary with detailed metrics
--   - Maintains backward compatibility with existing boolean flags
-- ================================================================================

-- ============================================================
-- STEP 1: Add workflow tracking to campaign_events
-- ============================================================

ALTER TABLE campaign_events
ADD COLUMN IF NOT EXISTS campaign_enrollment_id UUID REFERENCES campaign_enrollments(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS workflow_execution_id UUID REFERENCES workflow_executions(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS draft_id UUID REFERENCES email_drafts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_campaign_events_enrollment 
ON campaign_events(campaign_enrollment_id) 
WHERE campaign_enrollment_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_campaign_events_workflow 
ON campaign_events(workflow_execution_id) 
WHERE workflow_execution_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_campaign_events_draft 
ON campaign_events(draft_id) 
WHERE draft_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_campaign_events_workflow_type 
ON campaign_events(workflow_execution_id, event_type) 
WHERE workflow_execution_id IS NOT NULL;

COMMENT ON COLUMN campaign_events.campaign_enrollment_id IS 
'Links event to specific campaign enrollment. NULL for non-campaign emails.';

COMMENT ON COLUMN campaign_events.workflow_execution_id IS 
'Links event to workflow execution. NULL for direct campaign emails. Non-NULL indicates workflow-generated email.';

COMMENT ON COLUMN campaign_events.draft_id IS 
'Links event to AI-generated draft. NULL for template-based emails.';

-- ============================================================
-- STEP 2: Add contact and campaign links to workflow_executions
-- ============================================================

ALTER TABLE workflow_executions
ADD COLUMN IF NOT EXISTS contact_id UUID REFERENCES contacts(id) ON DELETE CASCADE,
ADD COLUMN IF NOT EXISTS campaign_enrollment_id UUID REFERENCES campaign_enrollments(id) ON DELETE SET NULL;

-- Backfill contact_id from emails table
UPDATE workflow_executions we
SET contact_id = e.contact_id
FROM emails e
WHERE we.email_id = e.id
  AND we.contact_id IS NULL;

-- Make contact_id required (check first)
DO $$ 
BEGIN
  IF EXISTS (
    SELECT 1 FROM workflow_executions WHERE contact_id IS NULL LIMIT 1
  ) THEN
    RAISE WARNING 'Some workflow_executions have NULL contact_id. Skipping NOT NULL constraint.';
  ELSE
    ALTER TABLE workflow_executions ALTER COLUMN contact_id SET NOT NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_workflow_executions_contact 
ON workflow_executions(contact_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_workflow_executions_enrollment 
ON workflow_executions(campaign_enrollment_id) 
WHERE campaign_enrollment_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_workflow_executions_workflow_contact 
ON workflow_executions(workflow_id, contact_id);

COMMENT ON COLUMN workflow_executions.contact_id IS 
'Contact this workflow execution is for. Required.';

COMMENT ON COLUMN workflow_executions.campaign_enrollment_id IS 
'Campaign enrollment that triggered this workflow. NULL if workflow was triggered by non-campaign event.';

-- ============================================================
-- STEP 3: Enhance campaign_contact_summary
-- ============================================================

-- Add detailed counters (keeping existing booleans for compatibility)
ALTER TABLE campaign_contact_summary
ADD COLUMN IF NOT EXISTS emails_sent INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS emails_delivered INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS emails_opened INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS emails_clicked INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS emails_bounced INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS emails_replied INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS unique_clicks INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS first_opened_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS first_clicked_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS first_replied_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS last_opened_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS last_clicked_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS workflow_emails_sent INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS workflow_emails_opened INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS workflow_emails_clicked INTEGER NOT NULL DEFAULT 0;

-- Backfill statistics from existing campaign_events
UPDATE campaign_contact_summary ccs
SET 
  emails_sent = COALESCE((
    SELECT COUNT(*) 
    FROM campaign_events ce 
    WHERE ce.campaign_id = ccs.campaign_id 
      AND ce.contact_id = ccs.contact_id 
      AND ce.event_type = 'sent'
  ), 0),
  
  emails_delivered = COALESCE((
    SELECT COUNT(*) 
    FROM campaign_events ce 
    WHERE ce.campaign_id = ccs.campaign_id 
      AND ce.contact_id = ccs.contact_id 
      AND ce.event_type = 'delivered'
  ), 0),
  
  emails_opened = COALESCE((
    SELECT COUNT(*) 
    FROM campaign_events ce 
    WHERE ce.campaign_id = ccs.campaign_id 
      AND ce.contact_id = ccs.contact_id 
      AND ce.event_type = 'opened'
  ), 0),
  
  emails_clicked = COALESCE((
    SELECT COUNT(*) 
    FROM campaign_events ce 
    WHERE ce.campaign_id = ccs.campaign_id 
      AND ce.contact_id = ccs.contact_id 
      AND ce.event_type = 'clicked'
  ), 0),
  
  emails_bounced = COALESCE((
    SELECT COUNT(*) 
    FROM campaign_events ce 
    WHERE ce.campaign_id = ccs.campaign_id 
      AND ce.contact_id = ccs.contact_id 
      AND ce.event_type = 'bounced'
  ), 0),
  
  workflow_emails_sent = COALESCE((
    SELECT COUNT(*) 
    FROM campaign_events ce 
    WHERE ce.campaign_id = ccs.campaign_id 
      AND ce.contact_id = ccs.contact_id 
      AND ce.event_type = 'sent'
      AND ce.workflow_execution_id IS NOT NULL
  ), 0),
  
  workflow_emails_opened = COALESCE((
    SELECT COUNT(*) 
    FROM campaign_events ce 
    WHERE ce.campaign_id = ccs.campaign_id 
      AND ce.contact_id = ccs.contact_id 
      AND ce.event_type = 'opened'
      AND ce.workflow_execution_id IS NOT NULL
  ), 0),
  
  workflow_emails_clicked = COALESCE((
    SELECT COUNT(*) 
    FROM campaign_events ce 
    WHERE ce.campaign_id = ccs.campaign_id 
      AND ce.contact_id = ccs.contact_id 
      AND ce.event_type = 'clicked'
      AND ce.workflow_execution_id IS NOT NULL
  ), 0),
  
  first_opened_at = (
    SELECT MIN(event_timestamp) 
    FROM campaign_events ce 
    WHERE ce.campaign_id = ccs.campaign_id 
      AND ce.contact_id = ccs.contact_id 
      AND ce.event_type = 'opened'
  ),
  
  first_clicked_at = (
    SELECT MIN(event_timestamp) 
    FROM campaign_events ce 
    WHERE ce.campaign_id = ccs.campaign_id 
      AND ce.contact_id = ccs.contact_id 
      AND ce.event_type = 'clicked'
  ),
  
  last_opened_at = (
    SELECT MAX(event_timestamp) 
    FROM campaign_events ce 
    WHERE ce.campaign_id = ccs.campaign_id 
      AND ce.contact_id = ccs.contact_id 
      AND ce.event_type = 'opened'
  ),
  
  last_clicked_at = (
    SELECT MAX(event_timestamp) 
    FROM campaign_events ce 
    WHERE ce.campaign_id = ccs.campaign_id 
      AND ce.contact_id = ccs.contact_id 
      AND ce.event_type = 'clicked'
  ),
  
  -- Sync existing boolean flags with new counters
  opened = (
    SELECT COUNT(*) > 0
    FROM campaign_events ce 
    WHERE ce.campaign_id = ccs.campaign_id 
      AND ce.contact_id = ccs.contact_id 
      AND ce.event_type = 'opened'
  ),
  
  clicked = (
    SELECT COUNT(*) > 0
    FROM campaign_events ce 
    WHERE ce.campaign_id = ccs.campaign_id 
      AND ce.contact_id = ccs.contact_id 
      AND ce.event_type = 'clicked'
  );

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_campaign_contact_summary_workflow_sent 
ON campaign_contact_summary(campaign_id) 
WHERE workflow_emails_sent > 0;

CREATE INDEX IF NOT EXISTS idx_campaign_contact_summary_engagement_times 
ON campaign_contact_summary(campaign_id, first_opened_at) 
WHERE first_opened_at IS NOT NULL;

-- Add documentation
COMMENT ON COLUMN campaign_contact_summary.emails_sent IS 
'Total emails sent (campaign + workflow combined). emails_sent >= workflow_emails_sent always.';

COMMENT ON COLUMN campaign_contact_summary.emails_opened IS 
'Total emails opened. Syncs with opened boolean: opened = (emails_opened > 0).';

COMMENT ON COLUMN campaign_contact_summary.emails_clicked IS 
'Total emails clicked. Syncs with clicked boolean: clicked = (emails_clicked > 0).';

COMMENT ON COLUMN campaign_contact_summary.workflow_emails_sent IS 
'Workflow-generated emails sent (subset of emails_sent).';

COMMENT ON COLUMN campaign_contact_summary.workflow_emails_opened IS 
'Workflow-generated emails opened (subset of emails_opened).';

COMMENT ON COLUMN campaign_contact_summary.workflow_emails_clicked IS 
'Workflow-generated emails clicked (subset of emails_clicked).';

COMMENT ON COLUMN campaign_contact_summary.opened IS 
'Boolean flag indicating if contact opened any email. Kept for backward compatibility. Use emails_opened > 0 in new code.';

COMMENT ON COLUMN campaign_contact_summary.clicked IS 
'Boolean flag indicating if contact clicked any link. Kept for backward compatibility. Use emails_clicked > 0 in new code.';

-- ============================================================
-- STEP 4: Create helpful views
-- ============================================================

-- Campaign performance with workflow breakdown
CREATE OR REPLACE VIEW campaign_performance_summary AS
SELECT 
    c.id as campaign_id,
    c.name as campaign_name,
    c.external_id,
    COUNT(DISTINCT ccs.contact_id) as contacts_enrolled,
    SUM(ccs.emails_sent) as total_emails_sent,
    SUM(ccs.emails_sent - ccs.workflow_emails_sent) as campaign_emails_sent,
    SUM(ccs.workflow_emails_sent) as workflow_emails_sent,
    SUM(ccs.emails_opened) as total_opens,
    SUM(ccs.emails_clicked) as total_clicks,
    COUNT(DISTINCT CASE WHEN ccs.opened THEN ccs.contact_id END) as contacts_opened,
    COUNT(DISTINCT CASE WHEN ccs.clicked THEN ccs.contact_id END) as contacts_clicked,
    COUNT(DISTINCT CASE WHEN ccs.converted THEN ccs.contact_id END) as contacts_converted,
    ROUND(100.0 * SUM(ccs.emails_opened) / NULLIF(SUM(ccs.emails_sent), 0), 2) as open_rate,
    ROUND(100.0 * SUM(ccs.emails_clicked) / NULLIF(SUM(ccs.emails_sent), 0), 2) as click_rate,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN ccs.converted THEN ccs.contact_id END) / 
          NULLIF(COUNT(DISTINCT ccs.contact_id), 0), 2) as conversion_rate,
    c.created_at,
    c.sent_at
FROM campaigns c
LEFT JOIN campaign_contact_summary ccs ON ccs.campaign_id = c.id
GROUP BY c.id, c.name, c.external_id, c.created_at, c.sent_at;

COMMENT ON VIEW campaign_performance_summary IS 
'Aggregated campaign performance including workflow contribution breakdown.';

-- Workflow effectiveness
CREATE OR REPLACE VIEW workflow_effectiveness_summary AS
SELECT 
    w.id as workflow_id,
    w.name as workflow_name,
    w.trigger_condition,
    w.is_active,
    COUNT(DISTINCT we.id) as total_executions,
    COUNT(DISTINCT we.id) FILTER (WHERE we.status = 'completed') as completed_executions,
    COUNT(DISTINCT we.id) FILTER (WHERE we.status = 'failed') as failed_executions,
    COUNT(DISTINCT ce.id) FILTER (WHERE ce.event_type = 'sent') as emails_sent,
    COUNT(DISTINCT ce.id) FILTER (WHERE ce.event_type = 'opened') as emails_opened,
    COUNT(DISTINCT ce.id) FILTER (WHERE ce.event_type = 'clicked') as emails_clicked,
    COUNT(DISTINCT we.contact_id) as unique_contacts,
    ROUND(100.0 * COUNT(DISTINCT ce.id) FILTER (WHERE ce.event_type = 'opened') / 
          NULLIF(COUNT(DISTINCT ce.id) FILTER (WHERE ce.event_type = 'sent'), 0), 2) as open_rate,
    ROUND(100.0 * COUNT(DISTINCT ce.id) FILTER (WHERE ce.event_type = 'clicked') / 
          NULLIF(COUNT(DISTINCT ce.id) FILTER (WHERE ce.event_type = 'sent'), 0), 2) as click_rate,
    MAX(we.started_at) as last_execution_at
FROM workflows w
LEFT JOIN workflow_executions we ON we.workflow_id = w.id
LEFT JOIN campaign_events ce ON ce.workflow_execution_id = we.id
GROUP BY w.id, w.name, w.trigger_condition, w.is_active;

COMMENT ON VIEW workflow_effectiveness_summary IS 
'Aggregated workflow performance metrics and engagement statistics.';

-- ============================================================
-- STEP 5: Create helper function
-- ============================================================

CREATE OR REPLACE FUNCTION get_campaign_stats(p_campaign_id UUID)
RETURNS TABLE (
    metric TEXT,
    campaign_emails INTEGER,
    workflow_emails INTEGER,
    total INTEGER,
    workflow_percentage NUMERIC
) 
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        'Emails Sent'::TEXT,
        (SUM(emails_sent - workflow_emails_sent))::INTEGER,
        (SUM(workflow_emails_sent))::INTEGER,
        (SUM(emails_sent))::INTEGER,
        ROUND(100.0 * SUM(workflow_emails_sent) / NULLIF(SUM(emails_sent), 0), 2)
    FROM campaign_contact_summary
    WHERE campaign_id = p_campaign_id
    
    UNION ALL
    
    SELECT 
        'Emails Opened'::TEXT,
        (SUM(emails_opened - workflow_emails_opened))::INTEGER,
        (SUM(workflow_emails_opened))::INTEGER,
        (SUM(emails_opened))::INTEGER,
        ROUND(100.0 * SUM(workflow_emails_opened) / NULLIF(SUM(emails_opened), 0), 2)
    FROM campaign_contact_summary
    WHERE campaign_id = p_campaign_id
    
    UNION ALL
    
    SELECT 
        'Emails Clicked'::TEXT,
        (SUM(emails_clicked - workflow_emails_clicked))::INTEGER,
        (SUM(workflow_emails_clicked))::INTEGER,
        (SUM(emails_clicked))::INTEGER,
        ROUND(100.0 * SUM(workflow_emails_clicked) / NULLIF(SUM(emails_clicked), 0), 2)
    FROM campaign_contact_summary
    WHERE campaign_id = p_campaign_id;
END;
$$;

COMMENT ON FUNCTION get_campaign_stats(UUID) IS 
'Get campaign statistics with breakdown of campaign vs workflow contribution.
Usage: SELECT * FROM get_campaign_stats(''campaign_id_here'');';

-- ============================================================
-- STEP 6: Update table documentation
-- ============================================================

COMMENT ON TABLE campaign_events IS 
'Unified engagement tracking for all emails (campaign and workflow-generated).
Links to campaigns, enrollments, workflow executions, and drafts via foreign keys.';

COMMENT ON TABLE campaign_contact_summary IS 
'Aggregated engagement statistics per campaign per contact.
Includes breakdown of campaign emails vs workflow-generated emails.
Boolean flags (opened, clicked) maintained for compatibility; use counters in new code.';

COMMENT ON TABLE workflow_executions IS 
'Records of workflow executions linked to contacts and optionally to campaign enrollments.';

-- ============================================================
-- VERIFICATION
-- ============================================================

DO $$
DECLARE
    events_count INTEGER;
    executions_count INTEGER;
    summary_count INTEGER;
    mismatch_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO events_count FROM campaign_events;
    SELECT COUNT(*) INTO executions_count 
    FROM workflow_executions WHERE contact_id IS NOT NULL;
    SELECT COUNT(*) INTO summary_count FROM campaign_contact_summary;
    
    -- Check for boolean/counter mismatches
    SELECT COUNT(*) INTO mismatch_count
    FROM campaign_contact_summary
    WHERE (opened != (emails_opened > 0))
       OR (clicked != (emails_clicked > 0));
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'UNIFIED TRACKING SYSTEM - VERIFICATION';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Campaign events: %', events_count;
    RAISE NOTICE 'Workflow executions (with contact): %', executions_count;
    RAISE NOTICE 'Campaign summaries: %', summary_count;
    RAISE NOTICE 'Boolean/Counter mismatches: %', mismatch_count;
    RAISE NOTICE '';
    
    IF mismatch_count = 0 THEN
        RAISE NOTICE '✅ All boolean flags synced with counters';
    ELSE
        RAISE WARNING '⚠️  Found % records with boolean/counter mismatch', mismatch_count;
    END IF;
    
    RAISE NOTICE '✅ Schema updated successfully';
    RAISE NOTICE '✅ New columns: campaign_enrollment_id, workflow_execution_id, draft_id';
    RAISE NOTICE '✅ Views created: campaign_performance_summary, workflow_effectiveness_summary';
    RAISE NOTICE '✅ Helper function: get_campaign_stats(campaign_id)';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '  1. Update webhook to populate new columns from Resend tags';
    RAISE NOTICE '  2. Update send functions to include tags when sending emails';
    RAISE NOTICE '  3. Use counter columns (emails_opened) instead of booleans in new code';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
END $$;


