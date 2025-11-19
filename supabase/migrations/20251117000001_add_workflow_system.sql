-- ============================================================================
-- Migration: Add Workflow System
-- ============================================================================
-- Description: Adds tables for agent-based workflow system, HITL approvals, and email automation
-- Date: 2025-11-17
-- Source: Adapted from ai-outreach-lambda/migrations/001_add_workflow_system.sql
-- ============================================================================

-- ============================================================================
-- 1. WORKFLOWS
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.workflows (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  description TEXT,

  -- Trigger matching configuration
  trigger_condition TEXT NOT NULL,
  priority INTEGER DEFAULT 100,

  -- Field extraction configuration
  extract_fields JSONB NOT NULL DEFAULT '[]',
  /* Example:
  [
    {
      "variable": "return_date",
      "description": "Expected date of return specified by sender",
      "field_type": "date",
      "required": true
    },
    {
      "variable": "alternate_contact",
      "description": "Alternate contact email if mentioned",
      "field_type": "email",
      "required": false
    }
  ]
  */

  -- Actions configuration (references Python tool names)
  actions JSONB NOT NULL DEFAULT '[]',
  /* Example:
  [
    {
      "tool": "update_contact",
      "params": {
        "contact_id": "{contact_id}",
        "status": "ooo",
        "return_date": "{return_date}"
      },
      "condition": null,
      "auto_approve": true,
      "confidence_threshold": null
    },
    {
      "tool": "draft_email",
      "params": {
        "to": "{alternate_contact}",
        "template_id": "uuid-here",
        "context": {
          "original_contact_name": "{contact_name}",
          "return_date": "{return_date}"
        }
      },
      "condition": "{alternate_contact} != null",
      "auto_approve": false,
      "confidence_threshold": 0.85
    }
  ]
  */

  -- Lead scoring rules
  lead_score_rules JSONB NOT NULL DEFAULT '[]',
  /* Example:
  [
    {
      "contact_target": "original",
      "score_delta": -5,
      "reason": "Contact is out of office",
      "condition": null
    },
    {
      "contact_target": "{alternate_contact}",
      "score_delta": 10,
      "reason": "New alternate contact created",
      "condition": "{alternate_contact} != null"
    }
  ]
  */

  -- Category matching rules (configurable per workflow)
  category_rules JSONB DEFAULT '{
    "enabled_pattern": "business-*",
    "disabled_categories": ["business-transactional"]
  }'::jsonb,

  -- Metadata
  is_active BOOLEAN DEFAULT true,
  created_by UUID REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 2. WORKFLOW EXECUTIONS
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.workflow_executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id UUID NOT NULL REFERENCES public.workflows(id) ON DELETE CASCADE,
  email_id UUID NOT NULL REFERENCES public.emails(id) ON DELETE CASCADE,

  -- Execution status
  status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending',
    'extracting',
    'executing',
    'awaiting_approval',
    'completed',
    'failed'
  )),

  -- Extracted data from email
  extracted_data JSONB,
  /* Example:
  {
    "return_date": "2024-12-01",
    "alternate_contact": "jane@example.com",
    "confidence": 0.92
  }
  */

  -- LLM confidence for extraction
  extraction_confidence FLOAT CHECK (extraction_confidence >= 0 AND extraction_confidence <= 1),

  -- Actions tracking
  actions_completed JSONB DEFAULT '[]',
  /* Example:
  [
    {
      "action_index": 0,
      "tool": "update_contact",
      "params_resolved": {"contact_id": "uuid", "status": "ooo"},
      "result": {"success": true, "contact_id": "uuid"},
      "executed_at": "2024-11-14T10:30:00Z",
      "success": true
    }
  ]
  */

  actions_failed JSONB DEFAULT '[]',
  /* Example:
  [
    {
      "action_index": 2,
      "tool": "send_email",
      "params_resolved": {...},
      "error": "SMTP connection failed",
      "failed_at": "2024-11-14T10:31:00Z"
    }
  ]
  */

  -- For HITL resumption
  pending_action_index INTEGER,

  -- Timing
  started_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

-- ============================================================================
-- 3. APPROVAL QUEUE (Human-in-the-Loop)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.approval_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_execution_id UUID NOT NULL REFERENCES public.workflow_executions(id) ON DELETE CASCADE,

  -- What action needs approval
  action_index INTEGER NOT NULL,
  action_tool VARCHAR(100) NOT NULL,
  action_params_resolved JSONB NOT NULL,

  -- Context for UI display
  workflow_name VARCHAR(255) NOT NULL,
  email_subject VARCHAR(500),
  contact_email VARCHAR(255),
  extraction_confidence FLOAT,
  reason TEXT,

  -- Decision status
  status VARCHAR(50) DEFAULT 'pending' CHECK (status IN (
    'pending',
    'approved',
    'rejected',
    'modified'
  )),

  -- Decision details
  decided_by UUID REFERENCES public.profiles(id),
  decided_at TIMESTAMPTZ,
  modified_params JSONB,
  rejection_reason TEXT,

  -- Metadata
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 4. ACTION ITEMS
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.action_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title VARCHAR(500) NOT NULL,
  description TEXT,

  -- Relationships
  contact_id UUID NOT NULL REFERENCES public.contacts(id) ON DELETE CASCADE,
  email_id UUID REFERENCES public.emails(id) ON DELETE SET NULL,
  workflow_execution_id UUID REFERENCES public.workflow_executions(id) ON DELETE SET NULL,

  -- Action details
  action_type VARCHAR(50) CHECK (action_type IN (
    'follow_up',
    'call',
    'meeting',
    'review',
    'other'
  )),
  priority VARCHAR(20) DEFAULT 'medium' CHECK (priority IN (
    'low',
    'medium',
    'high',
    'urgent'
  )),
  status VARCHAR(20) DEFAULT 'open' CHECK (status IN (
    'open',
    'in_progress',
    'completed',
    'cancelled'
  )),

  -- Scheduling
  due_date TIMESTAMPTZ,
  assigned_to UUID REFERENCES public.profiles(id) ON DELETE SET NULL,

  -- Completion tracking
  completed_at TIMESTAMPTZ,
  completed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,

  -- Metadata
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 5. EMAIL TEMPLATES
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.email_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  description TEXT,

  -- Template content
  subject_template TEXT NOT NULL,
  body_template TEXT NOT NULL,

  -- LLM personalization instructions
  llm_instructions TEXT,
  /* Example:
  "Personalize this email based on the contact's industry and role.
   Maintain a professional but friendly tone.
   Keep the email under 150 words.
   Highlight relevant product features based on their use case."
  */

  -- Variables used in template (for validation)
  required_variables JSONB DEFAULT '[]',
  /* Example: ["contact_name", "return_date", "product_name"] */

  -- Categorization
  category VARCHAR(100),
  tags JSONB DEFAULT '[]',

  -- Metadata
  is_active BOOLEAN DEFAULT true,
  created_by UUID REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

-- Workflows
CREATE INDEX IF NOT EXISTS idx_workflows_active ON public.workflows(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_workflows_created_by ON public.workflows(created_by);
CREATE INDEX IF NOT EXISTS idx_workflows_active_priority ON public.workflows(is_active, priority) WHERE is_active = true;

-- Workflow Executions
CREATE INDEX IF NOT EXISTS idx_workflow_executions_status ON public.workflow_executions(status, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_workflow_executions_email ON public.workflow_executions(email_id);
CREATE INDEX IF NOT EXISTS idx_workflow_executions_workflow ON public.workflow_executions(workflow_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_workflow_executions_pending ON public.workflow_executions(status) WHERE status = 'awaiting_approval';

-- Approval Queue
CREATE INDEX IF NOT EXISTS idx_approval_queue_pending ON public.approval_queue(status, created_at DESC) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_approval_queue_workflow_execution ON public.approval_queue(workflow_execution_id);
CREATE INDEX IF NOT EXISTS idx_approval_queue_decided_by ON public.approval_queue(decided_by, decided_at DESC);

-- Action Items
CREATE INDEX IF NOT EXISTS idx_action_items_contact ON public.action_items(contact_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_action_items_status_due ON public.action_items(status, due_date) WHERE status IN ('open', 'in_progress');
CREATE INDEX IF NOT EXISTS idx_action_items_assigned ON public.action_items(assigned_to, status);
CREATE INDEX IF NOT EXISTS idx_action_items_workflow ON public.action_items(workflow_execution_id);

-- Email Templates
CREATE INDEX IF NOT EXISTS idx_email_templates_active ON public.email_templates(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_email_templates_category ON public.email_templates(category);

-- ============================================================================
-- TRIGGERS FOR UPDATED_AT
-- ============================================================================

-- Function to update updated_at timestamp (reuse if exists)
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to tables
CREATE TRIGGER update_workflows_updated_at
    BEFORE UPDATE ON public.workflows
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_action_items_updated_at
    BEFORE UPDATE ON public.action_items
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_email_templates_updated_at
    BEFORE UPDATE ON public.email_templates
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================================
-- HELPER FUNCTIONS FOR WORKFLOW CATEGORY MATCHING
-- ============================================================================

-- Function to check if category matches workflow rules
CREATE OR REPLACE FUNCTION public.category_matches_workflow_rules(
    p_category VARCHAR,
    p_rules JSONB
) RETURNS BOOLEAN AS $$
DECLARE
    enabled_pattern VARCHAR;
    disabled_categories JSONB;
    disabled_cat VARCHAR;
BEGIN
    -- Get rules
    enabled_pattern := p_rules->>'enabled_pattern';
    disabled_categories := p_rules->'disabled_categories';

    -- Check if explicitly disabled
    IF disabled_categories IS NOT NULL THEN
        FOR disabled_cat IN SELECT jsonb_array_elements_text(disabled_categories) LOOP
            -- Check wildcard match (e.g., 'spam-*')
            IF disabled_cat LIKE '%*' THEN
                IF p_category LIKE REPLACE(disabled_cat, '*', '%') THEN
                    RETURN FALSE;
                END IF;
            -- Check exact match
            ELSIF p_category = disabled_cat THEN
                RETURN FALSE;
            END IF;
        END LOOP;
    END IF;

    -- Check if matches enabled pattern
    IF enabled_pattern LIKE '%*' THEN
        RETURN p_category LIKE REPLACE(enabled_pattern, '*', '%');
    ELSE
        RETURN p_category = enabled_pattern;
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION public.category_matches_workflow_rules IS 'Check if email category matches workflow category rules (with wildcard support)';

-- Function to get workflows for email category
CREATE OR REPLACE FUNCTION public.get_workflows_for_category(p_category VARCHAR)
RETURNS TABLE(workflow_id UUID, workflow_name VARCHAR, priority INTEGER) AS $$
BEGIN
    RETURN QUERY
    SELECT w.id, w.name, w.priority
    FROM public.workflows w
    WHERE w.is_active = true
      AND public.category_matches_workflow_rules(p_category, w.category_rules)
    ORDER BY w.priority DESC;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION public.get_workflows_for_category IS 'Get all active workflows that should trigger for given email category';

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE public.workflows IS 'User-configured workflows for automated email processing';
COMMENT ON TABLE public.workflow_executions IS 'Audit trail of workflow executions';
COMMENT ON TABLE public.approval_queue IS 'Human-in-the-loop approval queue for workflow actions';
COMMENT ON TABLE public.action_items IS 'Follow-up actions generated by workflows';
COMMENT ON TABLE public.email_templates IS 'Email templates for drafting automated responses';

COMMENT ON COLUMN public.workflows.category_rules IS 'Category matching rules: enabled_pattern, disabled_categories, custom overrides';

-- ============================================================================
-- SAMPLE DATA (Optional - for testing)
-- ============================================================================

-- Sample email template
INSERT INTO public.email_templates (name, description, subject_template, body_template, llm_instructions, category, required_variables)
VALUES (
  'OOO Alternate Contact',
  'Email to alternate contact when primary is out of office',
  'Following up: {original_subject}',
  'Hi {alternate_name},

I previously reached out to {original_contact_name} regarding {topic}, but they are currently out of office until {return_date}.

{email_body}

Would you be the right person to discuss this, or could you direct me to someone who could help?

Best regards',
  'Keep tone professional but friendly. Acknowledge the OOO situation tactfully. Be concise and clear about what you need.',
  'ooo_response',
  '["alternate_name", "original_contact_name", "return_date", "topic", "email_body"]'
)
ON CONFLICT DO NOTHING;

-- Sample workflow: OOO Detection
INSERT INTO public.workflows (
  name,
  description,
  trigger_condition,
  priority,
  extract_fields,
  actions,
  lead_score_rules,
  category_rules,
  is_active
)
VALUES (
  'Out of Office Detection',
  'Detects OOO auto-replies and schedules follow-up',
  'Automated out-of-office reply with return date and/or alternate contact information',
  100,
  '[
    {
      "variable": "return_date",
      "description": "Expected date of return specified by sender",
      "field_type": "date",
      "required": true
    },
    {
      "variable": "alternate_contact",
      "description": "Alternate contact email address mentioned in OOO message",
      "field_type": "email",
      "required": false
    },
    {
      "variable": "alternate_name",
      "description": "Name of alternate contact if mentioned",
      "field_type": "string",
      "required": false
    }
  ]'::jsonb,
  '[
    {
      "tool": "update_contact",
      "params": {
        "contact_id": "{contact_id}",
        "status": "ooo",
        "return_date": "{return_date}",
        "notes": "Out of office until {return_date}"
      },
      "condition": null,
      "auto_approve": true,
      "confidence_threshold": null
    },
    {
      "tool": "create_action_item",
      "params": {
        "title": "Follow up after OOO return: {contact_name}",
        "contact_id": "{contact_id}",
        "priority": "medium",
        "due_date": "{return_date}",
        "description": "Contact was out of office. Follow up after return date."
      },
      "condition": "{return_date} != null",
      "auto_approve": true,
      "confidence_threshold": null
    },
    {
      "tool": "create_contact",
      "params": {
        "email": "{alternate_contact}",
        "organization_id": "{organization_id}",
        "first_name": "{alternate_name}",
        "source": "ooo_alternate",
        "related_contact_id": "{contact_id}"
      },
      "condition": "{alternate_contact} != null",
      "auto_approve": true,
      "confidence_threshold": 0.8
    },
    {
      "tool": "draft_email",
      "params": {
        "to": "{alternate_contact}",
        "template_id": null,
        "context": {
          "original_contact_name": "{contact_name}",
          "return_date": "{return_date}",
          "alternate_name": "{alternate_name}"
        }
      },
      "condition": "{alternate_contact} != null",
      "auto_approve": false,
      "confidence_threshold": 0.85
    }
  ]'::jsonb,
  '[
    {
      "contact_target": "original",
      "score_delta": -5,
      "reason": "Contact is out of office",
      "condition": null
    },
    {
      "contact_target": "{alternate_contact}",
      "score_delta": 10,
      "reason": "New alternate contact identified",
      "condition": "{alternate_contact} != null"
    }
  ]'::jsonb,
  '{
    "enabled_pattern": "business-*",
    "disabled_categories": ["business-transactional", "spam-*"]
  }'::jsonb,
  true
)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT ALL ON public.workflows TO authenticated;
GRANT ALL ON public.workflows TO service_role;

GRANT ALL ON public.workflow_executions TO authenticated;
GRANT ALL ON public.workflow_executions TO service_role;

GRANT ALL ON public.approval_queue TO authenticated;
GRANT ALL ON public.approval_queue TO service_role;

GRANT ALL ON public.action_items TO authenticated;
GRANT ALL ON public.action_items TO service_role;

GRANT ALL ON public.email_templates TO authenticated;
GRANT ALL ON public.email_templates TO service_role;

-- Migration complete!
