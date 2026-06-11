-- Hardening for page-sized data loading RPCs.
--
-- The initial rollout RPCs shipped to dev. This migration keeps the deployed
-- functions additive by replacing them in place and only dropping the expanded
-- organization contacts function whose return type now includes total_count.

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
  ),
  page_rows AS (
    SELECT
      to_jsonb(f) - 'organization' - 'score' - 'is_internal'
        || jsonb_build_object(
          'organization', f.organization,
          'score', f.score,
          'is_internal', f.is_internal
        ) AS contact
    FROM filtered f
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
    OFFSET GREATEST(p_offset, 0)
  )
  SELECT
    p.contact,
    t.total_count,
    t.total_active_count,
    t.total_organization_count
  FROM page_rows p
  CROSS JOIN totals t
  UNION ALL
  SELECT
    NULL::jsonb,
    t.total_count,
    t.total_active_count,
    t.total_organization_count
  FROM totals t
  WHERE NOT EXISTS (SELECT 1 FROM page_rows);
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
      ON COALESCE(c.organization_id, 'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid) = o.id
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
  ),
  page_rows AS (
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
      v.match_active_contact_count AS active_contact_count
    FROM visible v
    ORDER BY v.match_contact_count DESC, lower(COALESCE(v.name, '')) ASC, v.id
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  )
  SELECT
    p.organization,
    p.contact_count,
    p.active_contact_count,
    t.total_count,
    t.total_contacts,
    t.total_active_contacts
  FROM page_rows p
  CROSS JOIN totals t
  UNION ALL
  SELECT
    NULL::jsonb,
    0::bigint,
    0::bigint,
    t.total_count,
    t.total_contacts,
    t.total_active_contacts
  FROM totals t
  WHERE NOT EXISTS (SELECT 1 FROM page_rows);
$$;

COMMENT ON FUNCTION public.get_contact_organization_groups(text, text[], text, text, boolean, integer, integer) IS
  'Returns one server-filtered page of organization groups with exact matching contact counts.';

GRANT EXECUTE ON FUNCTION public.get_contact_organization_groups(text, text[], text, text, boolean, integer, integer) TO authenticated;

DROP FUNCTION IF EXISTS public.get_contacts_for_organization(uuid, text, text[], boolean, integer, integer);

CREATE OR REPLACE FUNCTION public.get_contacts_for_organization(
  p_organization_id uuid,
  p_search text DEFAULT NULL,
  p_statuses text[] DEFAULT NULL,
  p_show_internal boolean DEFAULT FALSE,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  contact jsonb,
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
  filtered AS (
    SELECT
      c.*,
      COALESCE(o.is_host, FALSE) AS is_internal,
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
    WHERE COALESCE(c.organization_id, 'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid) = p_organization_id
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
  ),
  totals AS (
    SELECT COUNT(*) AS total_count FROM filtered
  ),
  page_rows AS (
    SELECT
      to_jsonb(f) - 'score' - 'is_internal'
        || jsonb_build_object(
          'is_internal', f.is_internal,
          'score', f.score
        ) AS contact
    FROM filtered f
    ORDER BY f.updated_at DESC NULLS LAST, f.created_at DESC NULLS LAST, f.id
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  )
  SELECT p.contact, t.total_count
  FROM page_rows p
  CROSS JOIN totals t
  UNION ALL
  SELECT NULL::jsonb, t.total_count
  FROM totals t
  WHERE NOT EXISTS (SELECT 1 FROM page_rows);
$$;

COMMENT ON FUNCTION public.get_contacts_for_organization(uuid, text, text[], boolean, integer, integer) IS
  'Lazy-loads one page of contacts for one expanded organization group with exact matching count.';

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
      le.body_clean,
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
      AND (p_unread IS NULL OR (p_unread = TRUE AND le.is_seen = FALSE))
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
  ),
  page_rows AS (
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
          'body_plain', NULL,
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
      ) AS conversation
    FROM filtered f
    ORDER BY f.last_email_at DESC NULLS LAST, f.id
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  )
  SELECT p.conversation, t.total_count
  FROM page_rows p
  CROSS JOIN totals t
  UNION ALL
  SELECT NULL::jsonb, t.total_count
  FROM totals t
  WHERE NOT EXISTS (SELECT 1 FROM page_rows);
$$;

COMMENT ON FUNCTION public.get_conversation_summaries(uuid, text, text, text[], text[], boolean, boolean, integer, text, boolean, integer, integer) IS
  'Returns one server-filtered Emails page with latest display email and exact total count.';

GRANT EXECUTE ON FUNCTION public.get_conversation_summaries(uuid, text, text, text[], text[], boolean, boolean, integer, text, boolean, integer, integer) TO authenticated;
