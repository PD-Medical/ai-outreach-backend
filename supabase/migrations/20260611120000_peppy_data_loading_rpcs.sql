-- Peppy data loading RPCs.
--
-- These functions move Contacts and Email list shaping into Postgres so the
-- frontend can render page-sized results instead of fetching database-sized
-- datasets and slicing/filtering in the browser.

CREATE OR REPLACE FUNCTION public.get_contact_filter_options(
  p_show_internal boolean DEFAULT FALSE
)
RETURNS TABLE(
  states text[],
  categories text[],
  statuses text[]
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH scoped_orgs AS (
    SELECT o.*
    FROM public.organizations o
    WHERE p_show_internal OR COALESCE(o.is_host, FALSE) = FALSE
  ),
  scoped_contacts AS (
    SELECT c.*
    FROM public.contacts c
    LEFT JOIN public.organizations o ON o.id = c.organization_id
    WHERE p_show_internal OR COALESCE(o.is_host, FALSE) = FALSE
  )
  SELECT
    COALESCE(
      ARRAY(
        SELECT DISTINCT trim(o.state)
        FROM scoped_orgs o
        WHERE NULLIF(trim(COALESCE(o.state, '')), '') IS NOT NULL
        ORDER BY trim(o.state)
      ),
      ARRAY[]::text[]
    ) AS states,
    COALESCE(
      ARRAY(
        SELECT DISTINCT trim(o.hospital_category)
        FROM scoped_orgs o
        WHERE NULLIF(trim(COALESCE(o.hospital_category, '')), '') IS NOT NULL
        ORDER BY trim(o.hospital_category)
      ),
      ARRAY[]::text[]
    ) AS categories,
    COALESCE(
      ARRAY(
        SELECT DISTINCT trim(c.status)
        FROM scoped_contacts c
        WHERE NULLIF(trim(COALESCE(c.status, '')), '') IS NOT NULL
        ORDER BY trim(c.status)
      ),
      ARRAY[]::text[]
    ) AS statuses;
$$;

COMMENT ON FUNCTION public.get_contact_filter_options(boolean) IS
  'Returns exact Contacts filter options without loading every contact or organization.';

GRANT EXECUTE ON FUNCTION public.get_contact_filter_options(boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_contacts_page(
  p_search text DEFAULT NULL,
  p_statuses text[] DEFAULT NULL,
  p_state text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_show_internal boolean DEFAULT FALSE,
  p_sort_key text DEFAULT 'created_at',
  p_sort_dir text DEFAULT 'desc',
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  contact jsonb,
  total_count bigint,
  total_active_count bigint,
  total_organization_count bigint
)
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
      c.*,
      COALESCE(o.is_host, FALSE) AS is_internal,
      jsonb_build_object(
        'id', o.id,
        'name', o.name,
        'state', o.state,
        'hospital_category', o.hospital_category,
        'is_host', COALESCE(o.is_host, FALSE)
      ) AS organization,
      CASE
        WHEN s.contact_id IS NULL THEN NULL
        ELSE jsonb_build_object(
          'contact_id', s.contact_id,
          'total_score', s.total_score,
          'opened', s.opened,
          'clicked', s.clicked,
          'converted', s.converted,
          'first_event_at', s.first_event_at,
          'last_event_at', s.last_event_at,
          'campaign_id', s.campaign_id
        )
      END AS score
    FROM public.contacts c
    LEFT JOIN public.organizations o ON o.id = c.organization_id
    LEFT JOIN LATERAL (
      SELECT ccs.*
      FROM public.campaign_contact_summary ccs
      WHERE ccs.contact_id = c.id
      ORDER BY ccs.total_score DESC NULLS LAST, ccs.last_event_at DESC NULLS LAST
      LIMIT 1
    ) s ON TRUE
    WHERE (p_show_internal OR COALESCE(o.is_host, FALSE) = FALSE)
      AND (
        COALESCE(array_length(p_statuses, 1), 0) = 0
        OR c.status = ANY(p_statuses)
      )
      AND (COALESCE(p_state, 'all') = 'all' OR o.state = p_state)
      AND (COALESCE(p_category, 'all') = 'all' OR o.hospital_category = p_category)
      AND NOT EXISTS (
        SELECT 1 FROM tokens t
        WHERE NOT (
          (
            COALESCE(c.first_name, '')   || ' ' ||
            COALESCE(c.last_name, '')    || ' ' ||
            COALESCE(c.email, '')        || ' ' ||
            COALESCE(c.job_title, '')    || ' ' ||
            COALESCE(c.phone_search, '') || ' ' ||
            COALESCE(c.notes, '')
          ) ILIKE t.pat
          OR
          (
            COALESCE(o.name, '')    || ' ' ||
            COALESCE(o.domain, '')  || ' ' ||
            COALESCE(o.phone, '')   || ' ' ||
            COALESCE(o.city, '')    || ' ' ||
            COALESCE(o.state, '')   || ' ' ||
            COALESCE(o.suburb, '')  || ' ' ||
            COALESCE(o.region, '')
          ) ILIKE t.pat
        )
      )
  ),
  totals AS (
    SELECT
      COUNT(*) AS total_count,
      COUNT(*) FILTER (WHERE status = 'active') AS total_active_count,
      COUNT(DISTINCT COALESCE(organization_id, 'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid)) AS total_organization_count
    FROM filtered
  )
  SELECT
    to_jsonb(f) - 'organization' - 'score' - 'is_internal'
      || jsonb_build_object(
        'organization', f.organization,
        'score', f.score,
        'is_internal', f.is_internal
      ) AS contact,
    t.total_count,
    t.total_active_count,
    t.total_organization_count
  FROM filtered f
  CROSS JOIN totals t
  ORDER BY
    CASE WHEN p_sort_key = 'name' AND p_sort_dir = 'asc' THEN lower(COALESCE(f.first_name, '') || ' ' || COALESCE(f.last_name, '') || ' ' || COALESCE(f.email, '')) END ASC NULLS LAST,
    CASE WHEN p_sort_key = 'name' AND p_sort_dir = 'desc' THEN lower(COALESCE(f.first_name, '') || ' ' || COALESCE(f.last_name, '') || ' ' || COALESCE(f.email, '')) END DESC NULLS LAST,
    CASE WHEN p_sort_key = 'organization_name' AND p_sort_dir = 'asc' THEN lower(f.organization->>'name') END ASC NULLS LAST,
    CASE WHEN p_sort_key = 'organization_name' AND p_sort_dir = 'desc' THEN lower(f.organization->>'name') END DESC NULLS LAST,
    CASE WHEN p_sort_key = 'job_title' AND p_sort_dir = 'asc' THEN lower(f.job_title) END ASC NULLS LAST,
    CASE WHEN p_sort_key = 'job_title' AND p_sort_dir = 'desc' THEN lower(f.job_title) END DESC NULLS LAST,
    CASE WHEN p_sort_key = 'status' AND p_sort_dir = 'asc' THEN lower(f.status) END ASC NULLS LAST,
    CASE WHEN p_sort_key = 'status' AND p_sort_dir = 'desc' THEN lower(f.status) END DESC NULLS LAST,
    CASE WHEN p_sort_key = 'created_at' AND p_sort_dir = 'asc' THEN f.created_at END ASC NULLS LAST,
    CASE WHEN p_sort_key = 'created_at' AND p_sort_dir = 'desc' THEN f.created_at END DESC NULLS LAST,
    f.updated_at DESC NULLS LAST,
    f.id
  LIMIT LEAST(GREATEST(p_limit, 1), 100)
  OFFSET GREATEST(p_offset, 0);
$$;

COMMENT ON FUNCTION public.get_contacts_page(text, text[], text, text, boolean, text, text, integer, integer) IS
  'Returns one server-filtered flat Contacts page with exact core counts and visible score summary.';

GRANT EXECUTE ON FUNCTION public.get_contacts_page(text, text[], text, text, boolean, text, text, integer, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_contact_organization_groups(
  p_search text DEFAULT NULL,
  p_statuses text[] DEFAULT NULL,
  p_state text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_show_internal boolean DEFAULT FALSE,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  organization jsonb,
  contact_count bigint,
  active_contact_count bigint,
  total_count bigint,
  total_contacts bigint,
  total_active_contacts bigint
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH tokens AS (
    SELECT '%' || token || '%' AS pat
    FROM regexp_split_to_table(trim(COALESCE(p_search, '')), '\s+') AS token
    WHERE length(token) > 0
  ),
  scoped_orgs AS (
    SELECT o.*, ot.id AS type_id, ot.name AS type_name, ot.description AS type_description
    FROM public.organizations o
    LEFT JOIN public.organization_types ot ON ot.id = o.organization_type_id
    WHERE (p_show_internal OR COALESCE(o.is_host, FALSE) = FALSE)
      AND (COALESCE(p_state, 'all') = 'all' OR o.state = p_state)
      AND (COALESCE(p_category, 'all') = 'all' OR o.hospital_category = p_category)
  ),
  grouped_counts AS (
    SELECT
      o.id,
      COUNT(c.id) AS match_contact_count,
      COUNT(c.id) FILTER (WHERE c.status = 'active') AS match_active_contact_count
    FROM scoped_orgs o
    LEFT JOIN public.contacts c
      ON c.organization_id = o.id
      AND (
        COALESCE(array_length(p_statuses, 1), 0) = 0
        OR c.status = ANY(p_statuses)
      )
      AND NOT EXISTS (
        SELECT 1 FROM tokens t
        WHERE NOT (
          (
            COALESCE(c.first_name, '')   || ' ' ||
            COALESCE(c.last_name, '')    || ' ' ||
            COALESCE(c.email, '')        || ' ' ||
            COALESCE(c.job_title, '')    || ' ' ||
            COALESCE(c.phone_search, '') || ' ' ||
            COALESCE(c.notes, '')
          ) ILIKE t.pat
          OR
          (
            COALESCE(o.name, '')    || ' ' ||
            COALESCE(o.domain, '')  || ' ' ||
            COALESCE(o.phone, '')   || ' ' ||
            COALESCE(o.city, '')    || ' ' ||
            COALESCE(o.state, '')   || ' ' ||
            COALESCE(o.suburb, '')  || ' ' ||
            COALESCE(o.region, '')
          ) ILIKE t.pat
        )
      )
    GROUP BY o.id
  ),
  grouped AS (
    SELECT
      o.*,
      COALESCE(gc.match_contact_count, 0) AS match_contact_count,
      COALESCE(gc.match_active_contact_count, 0) AS match_active_contact_count
    FROM scoped_orgs o
    LEFT JOIN grouped_counts gc ON gc.id = o.id
  ),
  visible AS (
    SELECT g.*
    FROM grouped g
    WHERE (
      COALESCE(p_search, '') = ''
      AND COALESCE(array_length(p_statuses, 1), 0) = 0
    )
    OR g.match_contact_count > 0
  ),
  totals AS (
    SELECT
      COUNT(*) AS total_count,
      COALESCE(SUM(match_contact_count), 0) AS total_contacts,
      COALESCE(SUM(match_active_contact_count), 0) AS total_active_contacts
    FROM visible
  )
  SELECT
    to_jsonb(v) - 'type_id' - 'type_name' - 'type_description' - 'match_contact_count' - 'match_active_contact_count'
      || jsonb_build_object(
        'organization_types',
        CASE
          WHEN v.type_id IS NULL THEN NULL
          ELSE jsonb_build_object('id', v.type_id, 'name', v.type_name, 'description', v.type_description)
        END,
        'contacts', '[]'::jsonb,
        'contact_count', v.match_contact_count,
        'active_contact_count', v.match_active_contact_count
      ) AS organization,
    v.match_contact_count AS contact_count,
    v.match_active_contact_count AS active_contact_count,
    t.total_count,
    t.total_contacts,
    t.total_active_contacts
  FROM visible v
  CROSS JOIN totals t
  ORDER BY v.match_contact_count DESC, lower(COALESCE(v.name, '')) ASC, v.id
  LIMIT LEAST(GREATEST(p_limit, 1), 100)
  OFFSET GREATEST(p_offset, 0);
$$;

COMMENT ON FUNCTION public.get_contact_organization_groups(text, text[], text, text, boolean, integer, integer) IS
  'Returns one server-filtered page of organization groups with exact matching contact counts.';

GRANT EXECUTE ON FUNCTION public.get_contact_organization_groups(text, text[], text, text, boolean, integer, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_contacts_for_organization(
  p_organization_id uuid,
  p_search text DEFAULT NULL,
  p_statuses text[] DEFAULT NULL,
  p_show_internal boolean DEFAULT FALSE,
  p_limit integer DEFAULT 200,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(contact jsonb)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH tokens AS (
    SELECT '%' || token || '%' AS pat
    FROM regexp_split_to_table(trim(COALESCE(p_search, '')), '\s+') AS token
    WHERE length(token) > 0
  )
  SELECT
    to_jsonb(c)
      || jsonb_build_object(
        'is_internal', COALESCE(o.is_host, FALSE),
        'score',
        CASE
          WHEN s.contact_id IS NULL THEN NULL
          ELSE jsonb_build_object(
            'contact_id', s.contact_id,
            'total_score', s.total_score,
            'opened', s.opened,
            'clicked', s.clicked,
            'converted', s.converted,
            'first_event_at', s.first_event_at,
            'last_event_at', s.last_event_at,
            'campaign_id', s.campaign_id
          )
        END
      ) AS contact
  FROM public.contacts c
  LEFT JOIN public.organizations o ON o.id = c.organization_id
  LEFT JOIN LATERAL (
    SELECT ccs.*
    FROM public.campaign_contact_summary ccs
    WHERE ccs.contact_id = c.id
    ORDER BY ccs.total_score DESC NULLS LAST, ccs.last_event_at DESC NULLS LAST
    LIMIT 1
  ) s ON TRUE
  WHERE c.organization_id = p_organization_id
    AND (p_show_internal OR COALESCE(o.is_host, FALSE) = FALSE)
    AND (
      COALESCE(array_length(p_statuses, 1), 0) = 0
      OR c.status = ANY(p_statuses)
    )
    AND NOT EXISTS (
      SELECT 1 FROM tokens t
      WHERE NOT (
        (
          COALESCE(c.first_name, '')   || ' ' ||
          COALESCE(c.last_name, '')    || ' ' ||
          COALESCE(c.email, '')        || ' ' ||
          COALESCE(c.job_title, '')    || ' ' ||
          COALESCE(c.phone_search, '') || ' ' ||
          COALESCE(c.notes, '')
        ) ILIKE t.pat
        OR
        (
          COALESCE(o.name, '')    || ' ' ||
          COALESCE(o.domain, '')  || ' ' ||
          COALESCE(o.phone, '')   || ' ' ||
          COALESCE(o.city, '')    || ' ' ||
          COALESCE(o.state, '')   || ' ' ||
          COALESCE(o.suburb, '')  || ' ' ||
          COALESCE(o.region, '')
        ) ILIKE t.pat
      )
    )
  ORDER BY c.updated_at DESC NULLS LAST, c.created_at DESC NULLS LAST, c.id
  LIMIT LEAST(GREATEST(p_limit, 1), 500)
  OFFSET GREATEST(p_offset, 0);
$$;

COMMENT ON FUNCTION public.get_contacts_for_organization(uuid, text, text[], boolean, integer, integer) IS
  'Lazy-loads bounded contacts for one expanded organization group.';

GRANT EXECUTE ON FUNCTION public.get_contacts_for_organization(uuid, text, text[], boolean, integer, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_conversation_summaries(
  p_mailbox_id uuid DEFAULT NULL,
  p_category_type text DEFAULT 'all',
  p_category_subtype text DEFAULT NULL,
  p_intents text[] DEFAULT NULL,
  p_sentiments text[] DEFAULT NULL,
  p_requires_response boolean DEFAULT NULL,
  p_unread boolean DEFAULT NULL,
  p_priority_min integer DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_show_internal boolean DEFAULT FALSE,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  conversation jsonb,
  total_count bigint
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH tokens AS (
    SELECT '%' || token || '%' AS pat
    FROM regexp_split_to_table(trim(COALESCE(p_search, '')), '\s+') AS token
    WHERE length(token) > 0
  ),
  latest_ranked AS (
    SELECT
      e.*,
      ROW_NUMBER() OVER (
        PARTITION BY e.conversation_id
        ORDER BY
          CASE WHEN COALESCE(e.message_kind::text, 'human') <> 'auto_reply' THEN 0 ELSE 1 END,
          e.received_at DESC,
          e.created_at DESC,
          e.id DESC
      ) AS rn
    FROM public.emails e
    WHERE COALESCE(e.is_deleted, FALSE) = FALSE
  ),
  latest AS (
    SELECT *
    FROM latest_ranked
    WHERE rn = 1
  ),
  filtered AS (
    SELECT
      c.*,
      mb.id AS mailbox_id_out,
      mb.email AS mailbox_email,
      mb.name AS mailbox_name,
      o.id AS organization_id_out,
      o.name AS organization_name,
      pc.id AS contact_id_out,
      pc.email AS contact_email,
      pc.first_name AS contact_first_name,
      pc.last_name AS contact_last_name,
      le.id AS latest_email_id,
      le.from_email,
      le.from_name,
      le.subject AS latest_subject,
      le.body_plain,
      le.email_category,
      le.intent,
      le.sentiment,
      le.priority_score,
      le.received_at,
      le.direction,
      le.is_seen,
      le.message_kind,
      le.mailchimp_newsletter_id,
      le.mailchimp_match_method,
      le.mailchimp_match_confidence,
      le.is_internal,
      mn.id AS newsletter_id,
      mn.subject AS newsletter_subject,
      mn.sent_at AS newsletter_sent_at,
      mn.from_name AS newsletter_from_name
    FROM public.conversations c
    JOIN latest le ON le.conversation_id = c.id
    LEFT JOIN public.mailboxes mb ON mb.id = c.mailbox_id
    LEFT JOIN public.organizations o ON o.id = c.organization_id
    LEFT JOIN public.contacts pc ON pc.id = c.primary_contact_id
    LEFT JOIN public.mailchimp_newsletters mn ON mn.id = le.mailchimp_newsletter_id
    WHERE c.status = 'active'
      AND c.email_count > 0
      AND (p_mailbox_id IS NULL OR c.mailbox_id = p_mailbox_id)
      AND (p_requires_response IS NULL OR c.requires_response = p_requires_response)
      AND (p_unread IS NULL OR le.is_seen = NOT p_unread)
      AND (p_priority_min IS NULL OR COALESCE(le.priority_score, 0) >= p_priority_min)
      AND (p_show_internal OR COALESCE(le.is_internal, FALSE) = FALSE)
      AND (
        COALESCE(p_category_type, 'all') = 'all'
        OR COALESCE(le.email_category, '') LIKE p_category_type || '-%'
      )
      AND (
        p_category_subtype IS NULL
        OR COALESCE(le.email_category, '') LIKE '%-' || p_category_subtype
      )
      AND (
        COALESCE(array_length(p_intents, 1), 0) = 0
        OR le.intent = ANY(p_intents)
      )
      AND (
        COALESCE(array_length(p_sentiments, 1), 0) = 0
        OR le.sentiment = ANY(p_sentiments)
      )
      AND NOT EXISTS (
        SELECT 1 FROM tokens t
        WHERE NOT (
          (
            COALESCE(c.subject, '')      || ' ' ||
            COALESCE(c.summary, '')      || ' ' ||
            COALESCE(le.subject, '')     || ' ' ||
            COALESCE(le.from_email, '')  || ' ' ||
            COALESCE(le.from_name, '')   || ' ' ||
            COALESCE(le.body_clean, '')  || ' ' ||
            COALESCE(le.body_plain, '')
          ) ILIKE t.pat
          OR
          (
            COALESCE(pc.first_name, '') || ' ' ||
            COALESCE(pc.last_name, '')  || ' ' ||
            COALESCE(pc.email, '')
          ) ILIKE t.pat
          OR
          (
            COALESCE(o.name, '') || ' ' ||
            COALESCE(o.city, '') || ' ' ||
            COALESCE(o.state, '')
          ) ILIKE t.pat
        )
      )
  ),
  totals AS (
    SELECT COUNT(*) AS total_count FROM filtered
  )
  SELECT
    jsonb_build_object(
      'id', f.id,
      'thread_id', f.thread_id,
      'subject', f.subject,
      'email_count', f.email_count,
      'first_email_at', f.first_email_at,
      'last_email_at', f.last_email_at,
      'last_email_direction', f.last_email_direction,
      'status', f.status,
      'requires_response', f.requires_response,
      'summary', f.summary,
      'action_items', f.action_items,
      'mailbox', CASE
        WHEN f.mailbox_id_out IS NULL THEN NULL
        ELSE jsonb_build_object('id', f.mailbox_id_out, 'email', f.mailbox_email, 'name', f.mailbox_name)
      END,
      'organization', CASE
        WHEN f.organization_id_out IS NULL THEN NULL
        ELSE jsonb_build_object('id', f.organization_id_out, 'name', f.organization_name)
      END,
      'primary_contact', CASE
        WHEN f.contact_id_out IS NULL THEN NULL
        ELSE jsonb_build_object('id', f.contact_id_out, 'email', f.contact_email, 'first_name', f.contact_first_name, 'last_name', f.contact_last_name)
      END,
      'latest_email', jsonb_build_object(
        'id', f.latest_email_id,
        'from_email', f.from_email,
        'from_name', f.from_name,
        'subject', f.latest_subject,
        'body_plain', f.body_plain,
        'email_category', f.email_category,
        'intent', f.intent,
        'sentiment', f.sentiment,
        'priority_score', f.priority_score,
        'received_at', f.received_at,
        'direction', f.direction,
        'is_seen', f.is_seen,
        'message_kind', f.message_kind,
        'mailchimp_newsletter_id', f.mailchimp_newsletter_id,
        'mailchimp_match_method', f.mailchimp_match_method,
        'mailchimp_match_confidence', f.mailchimp_match_confidence,
        'is_internal', f.is_internal,
        'mailchimp_newsletter', CASE
          WHEN f.newsletter_id IS NULL THEN NULL
          ELSE jsonb_build_object('id', f.newsletter_id, 'subject', f.newsletter_subject, 'sent_at', f.newsletter_sent_at, 'from_name', f.newsletter_from_name)
        END
      )
    ) AS conversation,
    t.total_count
  FROM filtered f
  CROSS JOIN totals t
  ORDER BY f.last_email_at DESC NULLS LAST, f.id
  LIMIT LEAST(GREATEST(p_limit, 1), 100)
  OFFSET GREATEST(p_offset, 0);
$$;

COMMENT ON FUNCTION public.get_conversation_summaries(uuid, text, text, text[], text[], boolean, boolean, integer, text, boolean, integer, integer) IS
  'Returns one server-filtered Emails page with latest display email and exact total count.';

GRANT EXECUTE ON FUNCTION public.get_conversation_summaries(uuid, text, text, text[], text[], boolean, boolean, integer, text, boolean, integer, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_hot_products_summary(
  p_start_date timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 10
)
RETURNS TABLE(
  product jsonb,
  counts jsonb
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH event_counts AS (
    SELECT
      (ce.source->>'product_id')::uuid AS product_id,
      COUNT(*) FILTER (WHERE ce.event_type = 'purchase') AS orders,
      COUNT(*) FILTER (WHERE ce.event_type = 'demo_request') AS quotes,
      COUNT(*) FILTER (WHERE ce.event_type IN ('form_submit', 'website_visit')) AS interest
    FROM public.campaign_events ce
    WHERE ce.source ? 'product_id'
      AND (p_start_date IS NULL OR ce.event_timestamp >= p_start_date)
      AND (ce.source->>'product_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    GROUP BY (ce.source->>'product_id')::uuid
  )
  SELECT
    to_jsonb(p) AS product,
    jsonb_build_object(
      'orders', COALESCE(ec.orders, 0),
      'quotes', COALESCE(ec.quotes, 0),
      'interest', COALESCE(ec.interest, 0)
    ) AS counts
  FROM public.products p
  LEFT JOIN event_counts ec ON ec.product_id = p.id
  ORDER BY
    COALESCE(p.sales_priority, 999) ASC,
    (COALESCE(p.unit_price, 0) * COALESCE(p.moq, 0)) DESC,
    p.id
  LIMIT LEAST(GREATEST(p_limit, 1), 50);
$$;

COMMENT ON FUNCTION public.get_hot_products_summary(timestamptz, integer) IS
  'Returns hot product rows and campaign event counts in one aggregate query, avoiding per-product event lookups.';

GRANT EXECUTE ON FUNCTION public.get_hot_products_summary(timestamptz, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_workflow_stats_batch(
  p_workflow_ids uuid[],
  p_days integer DEFAULT 7
)
RETURNS TABLE(
  workflow_id uuid,
  total bigint,
  completed bigint,
  failed bigint,
  pending bigint
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH selected_workflows AS (
    SELECT unnest(COALESCE(p_workflow_ids, ARRAY[]::uuid[])) AS id
  ),
  filtered_executions AS (
    SELECT we.*
    FROM public.workflow_executions we
    JOIN selected_workflows sw ON sw.id = we.workflow_id
    WHERE p_days <= 0
      OR we.started_at >= now() - make_interval(days => p_days)
  )
  SELECT
    sw.id AS workflow_id,
    COUNT(fe.*) AS total,
    COUNT(fe.*) FILTER (WHERE fe.status = 'completed') AS completed,
    COUNT(fe.*) FILTER (WHERE fe.status = 'failed') AS failed,
    COUNT(fe.*) FILTER (WHERE fe.status = 'awaiting_approval') AS pending
  FROM selected_workflows sw
  LEFT JOIN filtered_executions fe ON fe.workflow_id = sw.id
  GROUP BY sw.id;
$$;

COMMENT ON FUNCTION public.get_workflow_stats_batch(uuid[], integer) IS
  'Returns workflow execution counts for many workflows in one query.';

GRANT EXECUTE ON FUNCTION public.get_workflow_stats_batch(uuid[], integer) TO authenticated;
