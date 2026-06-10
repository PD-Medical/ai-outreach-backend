-- Roll campaign signals up in the contact timeline.
-- Raw campaign_events remain one row per provider activity for audit/scoring, but
-- the relationship timeline should show one campaign signal per contact/campaign.

CREATE OR REPLACE FUNCTION public.get_contact_timeline(
  p_contact_id uuid,
  p_activity_type text DEFAULT NULL,
  p_cursor timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 50
)
RETURNS TABLE(
  id text,
  source_type text,
  activity_type text,
  title text,
  body text,
  occurred_at timestamptz,
  due_at timestamptz,
  status text,
  priority text,
  direction text,
  author_name text,
  created_by uuid,
  can_edit boolean,
  can_delete boolean,
  edited_at timestamptz,
  has_revisions boolean,
  metadata jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_actor uuid := public._contact_activity_actor();
BEGIN
  IF v_actor IS NULL AND COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'authenticated user required';
  END IF;
  IF p_contact_id IS NULL THEN
    RAISE EXCEPTION 'contact_id is required';
  END IF;

  RETURN QUERY
  WITH activity_rows AS (
    SELECT
      ca.id::text AS id,
      ca.source_type,
      ca.activity_type,
      ca.title,
      ca.body,
      ca.occurred_at,
      ca.due_at,
      ca.status,
      ca.priority,
      ca.direction,
      coalesce(p.full_name, 'Team') AS author_name,
      ca.created_by,
      (
        ca.created_by = auth.uid()
        AND ca.source_type = 'manual'
        AND ca.activity_type IN ('call', 'follow_up', 'note', 'file')
        AND NOT COALESCE(lock_state.has_next_activity, false)
      ) AS can_edit,
      (
        ca.created_by = auth.uid()
        AND ca.source_type = 'manual'
        AND ca.activity_type IN ('call', 'follow_up', 'note', 'file')
        AND NOT COALESCE(lock_state.has_next_activity, false)
      ) AS can_delete,
      rev.edited_at,
      COALESCE(rev.revision_count, 0) > 0 AS has_revisions,
      ca.metadata || jsonb_build_object(
        'activity_id', ca.id,
        'attachment_count', (
          SELECT count(*)
          FROM public.contact_activity_attachments a
          WHERE a.activity_id = ca.id
        ),
        'attachments', (
          SELECT COALESCE(
            jsonb_agg(
              jsonb_build_object(
                'id', a.id,
                'file_name', a.file_name,
                'content_type', a.content_type,
                'file_size', a.file_size,
                'storage_bucket', a.storage_bucket,
                'storage_path', a.storage_path,
                'created_at', a.created_at
              )
              ORDER BY a.created_at ASC
            ),
            '[]'::jsonb
          )
          FROM public.contact_activity_attachments a
          WHERE a.activity_id = ca.id
        )
      ) AS metadata
    FROM public.contact_activities ca
    LEFT JOIN public.profiles p ON p.auth_user_id = ca.created_by
    LEFT JOIN LATERAL (
      SELECT
        max(car.edited_at) AS edited_at,
        count(*)::int AS revision_count
      FROM public.contact_activity_revisions car
      WHERE car.activity_id = ca.id
    ) rev ON true
    LEFT JOIN LATERAL (
      SELECT (
        EXISTS (
          SELECT 1
          FROM public.contact_activities next_activity
          WHERE next_activity.contact_id = ca.contact_id
            AND next_activity.deleted_at IS NULL
            AND (
              next_activity.occurred_at > ca.occurred_at
              OR (
                next_activity.occurred_at = ca.occurred_at
                AND next_activity.created_at > ca.created_at
              )
            )
        )
        OR EXISTS (
          SELECT 1
          FROM public.campaign_contact_summary next_campaign
          WHERE next_campaign.contact_id = ca.contact_id
            AND next_campaign.last_event_at > ca.occurred_at
        )
        OR EXISTS (
          SELECT 1
          FROM public.emails next_email
          WHERE (
              next_email.contact_id = ca.contact_id
              OR EXISTS (
                SELECT 1
                FROM public.conversations next_conv
                WHERE next_conv.id = next_email.conversation_id
                  AND next_conv.primary_contact_id = ca.contact_id
              )
            )
            AND next_email.received_at > ca.occurred_at
        )
      ) AS has_next_activity
    ) lock_state ON true
    WHERE ca.contact_id = p_contact_id
      AND ca.deleted_at IS NULL
      AND (p_activity_type IS NULL OR ca.activity_type = p_activity_type)
      AND (p_cursor IS NULL OR ca.occurred_at < p_cursor)
  ),
  campaign_rows AS (
    SELECT
      concat('campaign-summary:', ccs.campaign_id::text, ':', ccs.contact_id::text) AS id,
      'campaign'::text AS source_type,
      'campaign'::text AS activity_type,
      CASE
        WHEN ccs.clicked THEN 'Clicked'
        WHEN ccs.opened THEN 'Opened'
        WHEN ccs.emails_bounced > 0 THEN 'Bounced'
        WHEN ccs.emails_sent > 0 THEN 'Sent'
        ELSE 'Campaign engagement'
      END AS title,
      coalesce(c.name, c.subject, 'Campaign engagement') AS body,
      COALESCE(
        CASE WHEN ccs.clicked THEN ccs.last_clicked_at END,
        CASE WHEN ccs.opened THEN ccs.last_opened_at END,
        ccs.last_event_at,
        ccs.first_event_at
      ) AS occurred_at,
      NULL::timestamptz AS due_at,
      'completed'::text AS status,
      'medium'::text AS priority,
      NULL::text AS direction,
      'System'::text AS author_name,
      NULL::uuid AS created_by,
      false AS can_edit,
      false AS can_delete,
      NULL::timestamptz AS edited_at,
      false AS has_revisions,
      jsonb_build_object(
        'campaign_id', ccs.campaign_id,
        'total_score', ccs.total_score,
        'subject', c.subject,
        'opened', ccs.opened,
        'clicked', ccs.clicked,
        'emails_opened', ccs.emails_opened,
        'emails_clicked', ccs.emails_clicked,
        'emails_bounced', ccs.emails_bounced,
        'unique_clicks', ccs.unique_clicks,
        'first_opened_at', ccs.first_opened_at,
        'last_opened_at', ccs.last_opened_at,
        'first_clicked_at', ccs.first_clicked_at,
        'last_clicked_at', ccs.last_clicked_at
      ) AS metadata
    FROM public.campaign_contact_summary ccs
    LEFT JOIN public.campaigns c ON c.id = ccs.campaign_id
    WHERE ccs.contact_id = p_contact_id
      AND (p_activity_type IS NULL OR p_activity_type = 'campaign')
      AND (
        p_cursor IS NULL
        OR COALESCE(
          CASE WHEN ccs.clicked THEN ccs.last_clicked_at END,
          CASE WHEN ccs.opened THEN ccs.last_opened_at END,
          ccs.last_event_at,
          ccs.first_event_at
        ) < p_cursor
      )
  ),
  email_rows AS (
    SELECT
      e.id::text AS id,
      'email'::text AS source_type,
      'email'::text AS activity_type,
      coalesce(
        nullif(e.subject, '')::text,
        CASE
          WHEN e.direction IN ('outgoing', 'outbound', 'sent') THEN 'Email sent'
          ELSE 'Email received'
        END
      ) AS title,
      left(coalesce(nullif(e.body_clean, ''), nullif(e.body_plain, ''), ''), 1200) AS body,
      e.received_at AS occurred_at,
      NULL::timestamptz AS due_at,
      'completed'::text AS status,
      'medium'::text AS priority,
      e.direction::text AS direction,
      CASE
        WHEN e.direction IN ('outgoing', 'outbound', 'sent') THEN 'PD Medical'
        ELSE coalesce(nullif(e.from_name, '')::text, nullif(e.from_email, '')::text, 'External contact')
      END AS author_name,
      NULL::uuid AS created_by,
      false AS can_edit,
      false AS can_delete,
      NULL::timestamptz AS edited_at,
      false AS has_revisions,
      jsonb_build_object(
        'email_id', e.id,
        'conversation_id', e.conversation_id,
        'subject', e.subject,
        'from_email', e.from_email,
        'from_name', e.from_name,
        'to_emails', e.to_emails,
        'cc_emails', e.cc_emails,
        'bcc_emails', e.bcc_emails,
        'is_internal', e.is_internal
      ) AS metadata
    FROM public.emails e
    WHERE (
        e.contact_id = p_contact_id
        OR EXISTS (
          SELECT 1
          FROM public.conversations conv
          WHERE conv.id = e.conversation_id
            AND conv.primary_contact_id = p_contact_id
        )
      )
      AND (p_activity_type IS NULL OR p_activity_type = 'email')
      AND (p_cursor IS NULL OR e.received_at < p_cursor)
  )
  SELECT
    r.id,
    r.source_type,
    r.activity_type,
    r.title,
    r.body,
    r.occurred_at,
    r.due_at,
    r.status,
    r.priority,
    r.direction,
    r.author_name,
    r.created_by,
    r.can_edit,
    r.can_delete,
    r.edited_at,
    r.has_revisions,
    r.metadata
  FROM (
    SELECT * FROM activity_rows
    UNION ALL
    SELECT * FROM campaign_rows
    UNION ALL
    SELECT * FROM email_rows
  ) r
  ORDER BY r.occurred_at DESC NULLS LAST, r.id DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
END;
$$;
