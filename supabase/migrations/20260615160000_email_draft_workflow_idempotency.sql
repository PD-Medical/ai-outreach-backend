-- Add a stable workflow draft idempotency key so repeated workflow action
-- invocations cannot create multiple active approval drafts.

ALTER TABLE public.email_drafts
  ADD COLUMN IF NOT EXISTS idempotency_key text;

CREATE UNIQUE INDEX IF NOT EXISTS idx_email_drafts_active_idempotency_key
  ON public.email_drafts (idempotency_key)
  WHERE idempotency_key IS NOT NULL
    AND approval_status IN ('pending', 'approved', 'auto_approved', 'sent');

COMMENT ON COLUMN public.email_drafts.idempotency_key IS
  'Stable key for duplicate prevention. Workflow drafts use workflow:{workflow_execution_id}:action:{action_index}.';

CREATE OR REPLACE FUNCTION public.get_pending_approvals_page(
  p_statuses text[] DEFAULT ARRAY['pending']::text[],
  p_history_filter text DEFAULT NULL,
  p_show_internal boolean DEFAULT FALSE,
  p_limit integer DEFAULT 15,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(draft jsonb, total_count bigint)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH status_filter AS (
    SELECT CASE
      WHEN COALESCE(array_length(p_statuses, 1), 0) > 0 THEN p_statuses
      WHEN p_history_filter = 'approved' THEN ARRAY['approved', 'auto_approved']::text[]
      WHEN p_history_filter IN ('rejected', 'sent') THEN ARRAY[p_history_filter]::text[]
      WHEN p_history_filter = 'all' THEN ARRAY['approved', 'auto_approved', 'rejected', 'sent']::text[]
      ELSE ARRAY['pending']::text[]
    END AS statuses
  ),
  filtered AS (
    SELECT
      d.*,
      m.email AS mailbox_email,
      m.name AS mailbox_name,
      c.email AS contact_email,
      c.first_name AS contact_first_name,
      c.last_name AS contact_last_name,
      COALESCE(o.is_host, FALSE) AS contact_is_host,
      p.full_name AS approved_by_name,
      we.status AS workflow_status,
      we.workflow_id,
      we.match_reasoning,
      we.actions_failed,
      w.name AS workflow_name
    FROM public.email_drafts d
    CROSS JOIN status_filter sf
    LEFT JOIN public.mailboxes m ON m.id = d.from_mailbox_id
    LEFT JOIN public.contacts c ON c.id = d.contact_id
    LEFT JOIN public.organizations o ON o.id = c.organization_id
    LEFT JOIN public.profiles p ON p.profile_id = d.approved_by
    LEFT JOIN public.workflow_executions we ON we.id = d.workflow_execution_id
    LEFT JOIN public.workflows w ON w.id = we.workflow_id
    WHERE d.approval_status = ANY(sf.statuses)
      AND (p_show_internal OR COALESCE(o.is_host, FALSE) = FALSE)
  ),
  totals AS (
    SELECT COUNT(*) AS total_count FROM filtered
  ),
  page_rows AS (
    SELECT
      jsonb_build_object(
        'id', f.id,
        'subject', f.subject,
        'body_plain', NULL,
        'body_html', NULL,
        'to_emails', f.to_emails,
        'cc_emails', f.cc_emails,
        'bcc_emails', f.bcc_emails,
        'from_mailbox_id', f.from_mailbox_id,
        'idempotency_key', f.idempotency_key,
        'contact_id', f.contact_id,
        'generation_confidence', f.generation_confidence,
        'scheduled_send_time', f.scheduled_send_time,
        'context_data', NULL,
        'created_at', f.created_at,
        'version', f.version,
        'previous_draft_id', f.previous_draft_id,
        'source_type', f.source_type,
        'source_name', f.source_name,
        'source_details', f.source_details,
        'workflow_execution_id', f.workflow_execution_id,
        'source_email_id', f.source_email_id,
        'conversation_id', f.conversation_id,
        'thread_id', f.thread_id,
        'approval_status', f.approval_status,
        'approved_at', f.approved_at,
        'rejection_reason', f.rejection_reason,
        'sent_at', f.sent_at,
        'approved_by', f.approved_by,
        'mailbox', CASE WHEN f.from_mailbox_id IS NULL THEN NULL ELSE jsonb_build_object(
          'email', f.mailbox_email,
          'name', f.mailbox_name,
          'persona_description', NULL,
          'signature_html', NULL,
          'signature_images', NULL
        ) END,
        'contact', CASE WHEN f.contact_id IS NULL THEN NULL ELSE jsonb_build_object(
          'email', f.contact_email,
          'first_name', f.contact_first_name,
          'last_name', f.contact_last_name,
          'organizations', jsonb_build_object('is_host', f.contact_is_host)
        ) END,
        'approved_by_profile', CASE WHEN f.approved_by_name IS NULL THEN NULL ELSE jsonb_build_object(
          'full_name', f.approved_by_name
        ) END,
        'workflow_execution', CASE WHEN f.workflow_execution_id IS NULL THEN NULL ELSE jsonb_build_object(
          'id', f.workflow_execution_id,
          'status', f.workflow_status,
          'workflow_id', f.workflow_id,
          'match_reasoning', f.match_reasoning,
          'actions_failed', f.actions_failed,
          'workflow', jsonb_build_object('name', f.workflow_name)
        ) END
      ) AS draft
    FROM filtered f
    ORDER BY
      CASE WHEN 'pending' = ANY(COALESCE(p_statuses, ARRAY[]::text[])) THEN f.created_at END DESC NULLS LAST,
      f.approved_at DESC NULLS LAST,
      f.created_at DESC NULLS LAST,
      f.id
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  )
  SELECT p.draft, t.total_count
  FROM page_rows p
  CROSS JOIN totals t
  UNION ALL
  SELECT NULL::jsonb, t.total_count
  FROM totals t
  WHERE NOT EXISTS (SELECT 1 FROM page_rows);
$$;

GRANT EXECUTE ON FUNCTION public.get_pending_approvals_page(text[], text, boolean, integer, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_email_draft_detail(p_draft_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT jsonb_build_object(
    'id', d.id,
    'subject', d.subject,
    'body_plain', d.body_plain,
    'body_html', d.body_html,
    'to_emails', d.to_emails,
    'cc_emails', d.cc_emails,
    'bcc_emails', d.bcc_emails,
    'from_mailbox_id', d.from_mailbox_id,
    'idempotency_key', d.idempotency_key,
    'contact_id', d.contact_id,
    'generation_confidence', d.generation_confidence,
    'scheduled_send_time', d.scheduled_send_time,
    'context_data', d.context_data,
    'created_at', d.created_at,
    'version', d.version,
    'previous_draft_id', d.previous_draft_id,
    'source_type', d.source_type,
    'source_name', d.source_name,
    'source_details', d.source_details,
    'workflow_execution_id', d.workflow_execution_id,
    'source_email_id', d.source_email_id,
    'conversation_id', d.conversation_id,
    'thread_id', d.thread_id,
    'approval_status', d.approval_status,
    'approved_at', d.approved_at,
    'rejection_reason', d.rejection_reason,
    'sent_at', d.sent_at,
    'approved_by', d.approved_by,
    'mailbox', CASE WHEN d.from_mailbox_id IS NULL THEN NULL ELSE jsonb_build_object(
      'email', m.email,
      'name', m.name,
      'persona_description', m.persona_description,
      'signature_html', m.signature_html,
      'signature_images', m.signature_images
    ) END,
    'contact', CASE WHEN d.contact_id IS NULL THEN NULL ELSE jsonb_build_object(
      'email', c.email,
      'first_name', c.first_name,
      'last_name', c.last_name
    ) END,
    'approved_by_profile', CASE WHEN p.full_name IS NULL THEN NULL ELSE jsonb_build_object(
      'full_name', p.full_name
    ) END,
    'workflow_execution', CASE WHEN d.workflow_execution_id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', d.workflow_execution_id,
      'status', we.status,
      'workflow_id', we.workflow_id,
      'match_reasoning', we.match_reasoning,
      'actions_failed', we.actions_failed,
      'workflow', jsonb_build_object('name', w.name)
    ) END
  )
  FROM public.email_drafts d
  LEFT JOIN public.mailboxes m ON m.id = d.from_mailbox_id
  LEFT JOIN public.contacts c ON c.id = d.contact_id
  LEFT JOIN public.profiles p ON p.profile_id = d.approved_by
  LEFT JOIN public.workflow_executions we ON we.id = d.workflow_execution_id
  LEFT JOIN public.workflows w ON w.id = we.workflow_id
  WHERE d.id = p_draft_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_email_draft_detail(uuid) TO authenticated;
