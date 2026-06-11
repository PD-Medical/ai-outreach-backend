-- Peppy data loading next-phase RPCs.
--
-- These functions keep operational pages on page-sized list reads while
-- preserving exact core totals for the existing pagination UI.

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
        'from_mailbox_id', f.from_mailbox_id,
        'contact_id', f.contact_id,
        'generation_confidence', f.generation_confidence,
        'scheduled_send_time', f.scheduled_send_time,
        'context_data', NULL,
        'created_at', f.created_at,
        'version', f.version,
        'previous_draft_id', f.previous_draft_id,
        'source_type', f.source_type,
        'source_name', f.source_name,
        'source_details', NULL,
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
    'from_mailbox_id', d.from_mailbox_id,
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

CREATE OR REPLACE FUNCTION public.get_action_items_page(
  p_status text DEFAULT 'open',
  p_priority text DEFAULT NULL,
  p_action_type text DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_sort_by text DEFAULT 'due_date',
  p_sort_order text DEFAULT 'asc',
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(action_item jsonb, total_count bigint)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH tokens AS (
    SELECT '%' || token || '%' AS pat
    FROM regexp_split_to_table(trim(COALESCE(p_search, '')), '\s+') AS token
    WHERE length(token) > 0
  ),
  filtered AS (
    SELECT
      ai.*,
      c.email AS contact_email,
      c.first_name AS contact_first_name,
      c.last_name AS contact_last_name,
      o.name AS organization_name,
      e.subject AS email_subject,
      COALESCE(jsonb_array_length(COALESCE(ai.comments, '[]'::jsonb)), 0) AS comment_count
    FROM public.action_items ai
    LEFT JOIN public.contacts c ON c.id = ai.contact_id
    LEFT JOIN public.organizations o ON o.id = c.organization_id
    LEFT JOIN public.emails e ON e.id = ai.email_id
    WHERE (COALESCE(p_status, 'all') = 'all' OR ai.status = p_status)
      AND (COALESCE(p_priority, 'all') = 'all' OR ai.priority = p_priority)
      AND (COALESCE(p_action_type, 'all') = 'all' OR ai.action_type = p_action_type)
      AND NOT EXISTS (
        SELECT 1 FROM tokens t
        WHERE NOT (
          (COALESCE(ai.title, '') || ' ' || COALESCE(ai.description, '')) ILIKE t.pat
          OR (COALESCE(c.first_name, '') || ' ' || COALESCE(c.last_name, '') || ' ' || COALESCE(c.email, '')) ILIKE t.pat
          OR COALESCE(o.name, '') ILIKE t.pat
        )
      )
  ),
  totals AS (
    SELECT COUNT(*) AS total_count FROM filtered
  ),
  page_rows AS (
    SELECT jsonb_build_object(
      'id', f.id,
      'title', f.title,
      'description', CASE WHEN f.description IS NULL THEN NULL ELSE left(f.description, 240) END,
      'contact_id', f.contact_id,
      'email_id', f.email_id,
      'workflow_execution_id', f.workflow_execution_id,
      'action_type', f.action_type,
      'priority', f.priority,
      'status', f.status,
      'due_date', f.due_date,
      'assigned_to', f.assigned_to,
      'completed_at', f.completed_at,
      'completed_by', f.completed_by,
      'created_at', f.created_at,
      'updated_at', f.updated_at,
      'comments', '[]'::jsonb,
      'comment_count', f.comment_count,
      'contact', CASE WHEN f.contact_id IS NULL THEN NULL ELSE jsonb_build_object(
        'id', f.contact_id,
        'email', f.contact_email,
        'first_name', f.contact_first_name,
        'last_name', f.contact_last_name,
        'organization', jsonb_build_object('name', f.organization_name)
      ) END,
      'email', CASE WHEN f.email_id IS NULL THEN NULL ELSE jsonb_build_object(
        'id', f.email_id,
        'subject', f.email_subject
      ) END
    ) AS action_item
    FROM filtered f
    ORDER BY
      CASE WHEN p_sort_by = 'due_date' AND p_sort_order = 'asc' THEN f.due_date END ASC NULLS LAST,
      CASE WHEN p_sort_by = 'due_date' AND p_sort_order = 'desc' THEN f.due_date END DESC NULLS LAST,
      CASE WHEN p_sort_by = 'created_at' AND p_sort_order = 'asc' THEN f.created_at END ASC NULLS LAST,
      CASE WHEN p_sort_by = 'created_at' AND p_sort_order = 'desc' THEN f.created_at END DESC NULLS LAST,
      CASE WHEN p_sort_by = 'priority' AND p_sort_order = 'asc' THEN
        CASE f.priority WHEN 'urgent' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 WHEN 'low' THEN 4 ELSE 5 END
      END ASC NULLS LAST,
      CASE WHEN p_sort_by = 'priority' AND p_sort_order = 'desc' THEN
        CASE f.priority WHEN 'urgent' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 WHEN 'low' THEN 4 ELSE 5 END
      END DESC NULLS LAST,
      f.created_at DESC NULLS LAST,
      f.id
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  )
  SELECT p.action_item, t.total_count
  FROM page_rows p
  CROSS JOIN totals t
  UNION ALL
  SELECT NULL::jsonb, t.total_count
  FROM totals t
  WHERE NOT EXISTS (SELECT 1 FROM page_rows);
$$;

GRANT EXECUTE ON FUNCTION public.get_action_items_page(text, text, text, text, text, text, integer, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_action_item_detail(p_action_item_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT to_jsonb(ai)
    || jsonb_build_object(
      'contact', CASE WHEN c.id IS NULL THEN NULL ELSE jsonb_build_object(
        'id', c.id,
        'email', c.email,
        'first_name', c.first_name,
        'last_name', c.last_name,
        'organization', jsonb_build_object('name', o.name)
      ) END,
      'email', CASE WHEN e.id IS NULL THEN NULL ELSE jsonb_build_object(
        'id', e.id,
        'subject', e.subject
      ) END
    )
  FROM public.action_items ai
  LEFT JOIN public.contacts c ON c.id = ai.contact_id
  LEFT JOIN public.organizations o ON o.id = c.organization_id
  LEFT JOIN public.emails e ON e.id = ai.email_id
  WHERE ai.id = p_action_item_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_action_item_detail(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_action_item_stats()
RETURNS TABLE(total bigint, open bigint, in_progress bigint, completed bigint, overdue bigint, high_priority bigint)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE status = 'open') AS open,
    COUNT(*) FILTER (WHERE status = 'in_progress') AS in_progress,
    COUNT(*) FILTER (WHERE status = 'completed') AS completed,
    COUNT(*) FILTER (
      WHERE due_date IS NOT NULL
        AND status NOT IN ('completed', 'cancelled')
        AND due_date < now()
    ) AS overdue,
    COUNT(*) FILTER (
      WHERE priority IN ('high', 'urgent')
        AND status NOT IN ('completed', 'cancelled')
    ) AS high_priority
  FROM public.action_items;
$$;

GRANT EXECUTE ON FUNCTION public.get_action_item_stats() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_campaigns_page(
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(campaign jsonb, total_count bigint)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH filtered AS (
    SELECT cs.*
    FROM public.campaign_sequences cs
  ),
  totals AS (
    SELECT COUNT(*) AS total_count FROM filtered
  ),
  page_rows AS (
    SELECT jsonb_build_object(
      'id', f.id,
      'name', f.name,
      'description', f.description,
      'status', f.status,
      'target_count', f.target_count,
      'from_mailbox_id', f.from_mailbox_id,
      'scheduled_at', f.scheduled_at,
      'started_at', f.started_at,
      'completed_at', f.completed_at,
      'created_at', f.created_at,
      'updated_at', f.updated_at,
      'stats', f.stats,
      'email_mode', to_jsonb(f)->>'email_mode',
      'batch_size', CASE
        WHEN COALESCE(to_jsonb(f)->>'batch_size', '') ~ '^[0-9]+$' THEN (to_jsonb(f)->>'batch_size')::integer
        ELSE 10
      END
    ) AS campaign
    FROM filtered f
    ORDER BY f.created_at DESC NULLS LAST, f.id
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  )
  SELECT p.campaign, t.total_count
  FROM page_rows p
  CROSS JOIN totals t
  UNION ALL
  SELECT NULL::jsonb, t.total_count
  FROM totals t
  WHERE NOT EXISTS (SELECT 1 FROM page_rows);
$$;

GRANT EXECUTE ON FUNCTION public.get_campaigns_page(integer, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_campaigns_summary()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT jsonb_build_object(
    'totalCampaigns', COUNT(*),
    'activeCampaigns', COUNT(*) FILTER (WHERE status = 'running'),
    'totalSent', COALESCE(SUM(CASE WHEN COALESCE(stats->>'sent', '') ~ '^[0-9]+$' THEN (stats->>'sent')::integer ELSE 0 END), 0),
    'totalOpened', COALESCE(SUM(CASE WHEN COALESCE(stats->>'opened', '') ~ '^[0-9]+$' THEN (stats->>'opened')::integer ELSE 0 END), 0),
    'totalReplied', COALESCE(SUM(CASE WHEN COALESCE(stats->>'replied', '') ~ '^[0-9]+$' THEN (stats->>'replied')::integer ELSE 0 END), 0)
  )
  FROM public.campaign_sequences;
$$;

GRANT EXECUTE ON FUNCTION public.get_campaigns_summary() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_campaign_detail(p_campaign_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT to_jsonb(cs)
  FROM public.campaign_sequences cs
  WHERE cs.id = p_campaign_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_campaign_detail(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_products_page(
  p_search text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_priority text DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_product_type text DEFAULT NULL,
  p_limit integer DEFAULT 25,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(product jsonb, total_count bigint)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH tokens AS (
    SELECT '%' || token || '%' AS pat
    FROM regexp_split_to_table(trim(COALESCE(p_search, '')), '\s+') AS token
    WHERE length(token) > 0
  ),
  filtered AS (
    SELECT
      p.*,
      to_jsonb(p) AS pj,
      COALESCE(NULLIF(p.sales_status, ''), CASE WHEN COALESCE(p.is_active, TRUE) THEN 'active' ELSE 'inactive' END) AS normalized_status
    FROM public.products p
    WHERE (
        COALESCE(p_category, 'all') = 'all'
        OR p.industry_category = p_category
        OR p.main_category = p_category
        OR p.subcategory = p_category
        OR to_jsonb(p)->>'category_id' = p_category
      )
      AND (
        COALESCE(p_priority, 'all') = 'all'
        OR (p_priority = 'none' AND p.sales_priority IS NULL)
        OR p.sales_priority::text = p_priority
      )
      AND (
        COALESCE(p_status, 'all') = 'all'
        OR (p_status = 'active' AND COALESCE(p.is_active, TRUE) = TRUE AND COALESCE(NULLIF(p.sales_status, ''), 'active') NOT IN ('inactive', 'disabled'))
        OR (p_status = 'inactive' AND (COALESCE(p.is_active, TRUE) = FALSE OR COALESCE(NULLIF(p.sales_status, ''), 'active') IN ('inactive', 'disabled')))
      )
      AND (
        COALESCE(p_product_type, 'all') = 'all'
        OR to_jsonb(p)->>'product_type' = p_product_type
      )
      AND NOT EXISTS (
        SELECT 1 FROM tokens t
        WHERE NOT (
          (
            COALESCE(p.product_code, '') || ' ' ||
            COALESCE(p.product_name, '') || ' ' ||
            COALESCE(p.main_category, '') || ' ' ||
            COALESCE(p.subcategory, '') || ' ' ||
            COALESCE(p.industry_category, '') || ' ' ||
            COALESCE(to_jsonb(p)->>'category_name', '') || ' ' ||
            COALESCE(to_jsonb(p)->>'parent_name', '') || ' ' ||
            COALESCE(to_jsonb(p)->>'super_parent_name', '') || ' ' ||
            COALESCE(to_jsonb(p)->>'description', '')
          ) ILIKE t.pat
        )
      )
  ),
  totals AS (
    SELECT COUNT(*) AS total_count FROM filtered
  ),
  page_rows AS (
    SELECT
      pj
        - 'market_potential'
        - 'background_history'
        - 'key_contacts_reference'
        - 'forecast_notes'
        - 'sales_instructions'
        - 'sales_timing_notes'
        || jsonb_build_object(
          'market_potential', NULL,
          'background_history', NULL,
          'key_contacts_reference', NULL,
          'forecast_notes', NULL,
          'sales_instructions', NULL,
          'sales_timing_notes', NULL
        ) AS product
    FROM filtered
    ORDER BY product_name ASC NULLS LAST, product_code ASC NULLS LAST, id
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  )
  SELECT p.product, t.total_count
  FROM page_rows p
  CROSS JOIN totals t
  UNION ALL
  SELECT NULL::jsonb, t.total_count
  FROM totals t
  WHERE NOT EXISTS (SELECT 1 FROM page_rows);
$$;

GRANT EXECUTE ON FUNCTION public.get_products_page(text, text, text, text, text, integer, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_product_catalog_summary()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH product_rows AS (
    SELECT
      p.*,
      to_jsonb(p) AS pj,
      COALESCE(NULLIF(p.sales_status, ''), CASE WHEN COALESCE(p.is_active, TRUE) THEN 'active' ELSE 'inactive' END) AS normalized_status
    FROM public.products p
  )
  SELECT jsonb_build_object(
    'totalProducts', COUNT(*),
    'activeProducts', COUNT(*) FILTER (WHERE COALESCE(is_active, TRUE) = TRUE AND normalized_status NOT IN ('inactive', 'disabled')),
    'inactiveProducts', COUNT(*) FILTER (WHERE COALESCE(is_active, TRUE) = FALSE OR normalized_status IN ('inactive', 'disabled')),
    'categoryCount', COUNT(DISTINCT COALESCE(NULLIF(industry_category, ''), NULLIF(main_category, ''), NULLIF(pj->>'category_name', ''))),
    'superParentCount', COUNT(DISTINCT NULLIF(pj->>'super_parent_id', '')),
    'subParentCount', COUNT(DISTINCT NULLIF(pj->>'parent_product_id', '')),
    'priorityCounts', jsonb_build_object(
      '1', COUNT(*) FILTER (WHERE sales_priority = 1),
      '2', COUNT(*) FILTER (WHERE sales_priority = 2),
      '3', COUNT(*) FILTER (WHERE sales_priority = 3),
      'none', COUNT(*) FILTER (WHERE sales_priority IS NULL)
    ),
    'currencyBreakdown', COALESCE((
      SELECT jsonb_object_agg(currency_key, currency_count)
      FROM (
        SELECT COALESCE(currency, 'AUD') AS currency_key, COUNT(*) AS currency_count
        FROM product_rows
        GROUP BY COALESCE(currency, 'AUD')
      ) c
    ), '{}'::jsonb),
    'lastUpdated', MAX(updated_at)
  )
  FROM product_rows;
$$;

GRANT EXECUTE ON FUNCTION public.get_product_catalog_summary() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_product_filter_options()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT jsonb_build_object(
    'categories', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', category_key, 'label', category_label) ORDER BY category_label)
      FROM (
        SELECT DISTINCT
          COALESCE(NULLIF(industry_category, ''), NULLIF(main_category, ''), NULLIF(to_jsonb(p)->>'category_id', ''), 'uncategorized') AS category_key,
          COALESCE(NULLIF(industry_category, ''), NULLIF(main_category, ''), NULLIF(to_jsonb(p)->>'category_name', ''), 'Uncategorized') AS category_label
        FROM public.products p
      ) c
    ), '[]'::jsonb),
    'parentGroups', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', parent_id,
        'label', parent_label,
        'level', parent_level,
        'categoryId', category_id
      ) ORDER BY parent_label)
      FROM (
        SELECT DISTINCT
          NULLIF(to_jsonb(p)->>'parent_product_id', '') AS parent_id,
          COALESCE(NULLIF(to_jsonb(p)->>'parent_name', ''), NULLIF(to_jsonb(p)->>'parent_code', ''), 'Unnamed Group') AS parent_label,
          CASE
            WHEN COALESCE(to_jsonb(p)->>'parent_level', '') ~ '^[0-9]+$' THEN (to_jsonb(p)->>'parent_level')::integer
            ELSE 1
          END AS parent_level,
          NULLIF(to_jsonb(p)->>'category_id', '') AS category_id
        FROM public.products p
        WHERE NULLIF(to_jsonb(p)->>'parent_product_id', '') IS NOT NULL
      ) pg
    ), '[]'::jsonb)
  );
$$;

GRANT EXECUTE ON FUNCTION public.get_product_filter_options() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_product_detail(p_product_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT to_jsonb(p)
  FROM public.products p
  WHERE p.id = p_product_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_product_detail(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_hot_leads_metrics()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH external_contacts AS (
    SELECT c.*
    FROM public.contacts c
    LEFT JOIN public.organizations o ON o.id = c.organization_id
    WHERE COALESCE(o.is_host, FALSE) = FALSE
  ),
  campaign_scores AS (
    SELECT
      ccs.contact_id,
      SUM(COALESCE(ccs.total_score, 0)) AS campaign_score
    FROM public.campaign_contact_summary ccs
    GROUP BY ccs.contact_id
  ),
  scored AS (
    SELECT
      c.id,
      COALESCE(cs.campaign_score, 0) + COALESCE(c.lead_score, 0) AS total_score,
      COALESCE(c.needs_follow_up, FALSE) AS needs_follow_up
    FROM external_contacts c
    LEFT JOIN campaign_scores cs ON cs.contact_id = c.id
    WHERE COALESCE(cs.campaign_score, 0) > 0
       OR COALESCE(c.lead_score, 0) > 0
       OR COALESCE(c.needs_follow_up, FALSE) = TRUE
       OR COALESCE(c.lead_classification_locked, FALSE) = TRUE
  )
  SELECT jsonb_build_object(
    'totalLeads', COUNT(*),
    'followUpCount', COUNT(*) FILTER (WHERE needs_follow_up),
    'tierCounts', jsonb_build_object(
      'HOT', COUNT(*) FILTER (WHERE total_score >= 50),
      'WARM', COUNT(*) FILTER (WHERE total_score >= 20 AND total_score < 50),
      'COOL', COUNT(*) FILTER (WHERE total_score >= 5 AND total_score < 20),
      'COLD', COUNT(*) FILTER (WHERE total_score < 5)
    )
  )
  FROM scored;
$$;

GRANT EXECUTE ON FUNCTION public.get_hot_leads_metrics() TO authenticated;

CREATE INDEX IF NOT EXISTS idx_action_items_status_created
  ON public.action_items (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_products_name_code
  ON public.products (product_name, product_code);
