-- ============================================================================
-- Train D — Contact detail modal redesign: SQL view + feature flag
-- ============================================================================
-- The new ContactDetailModal Overview tab needs a single query that returns:
--   • contact identity + profile fields with field_sources for provenance dots
--   • organization + parent organization for the breadcrumb
--   • engagement_summary + timestamps for the summary card (Train E populates)
--   • aggregated stats: thread count, total emails, sent/received split, last
--     contact date, reply rate
--
-- Doing this as a SQL view keeps the frontend hook (useContactEngagementProfile)
-- a one-line `SELECT * FROM v_contact_engagement_profile WHERE contact_id = $1`
-- and pushes joins/aggregates to Postgres where they're indexed.
--
-- Reply rate: ratio of incoming emails that received any subsequent outgoing
-- email in the same conversation. Capped at 1.0 (an incoming can be replied to
-- multiple times). Returns 0.0 when there are no incoming emails.
--
-- Feature flag ui.contact_detail_v2: kill-switch for the new modal. The frontend
-- reads this via useSystemConfig and falls back to the legacy ContactDetailDialog
-- when false. Defaulting to true on dev — flip to false via system_config UPDATE
-- if a regression appears, no redeploy needed.
-- ============================================================================

BEGIN;

-- 1. View
CREATE OR REPLACE VIEW public.v_contact_engagement_profile
WITH (security_invoker = true) AS
SELECT
  c.id AS contact_id,
  c.email,
  c.first_name,
  c.last_name,
  c.role,
  c.department,
  c.phone,
  c.notes,
  c.field_sources,
  c.lead_classification,
  c.engagement_level,
  c.lead_score,
  c.engagement_summary,
  c.engagement_summary_at,
  c.engagement_action_items,
  c.engagement_conv_count_at_last_summary,
  c.created_at AS contact_created_at,
  c.updated_at AS contact_updated_at,

  -- Organization + parent
  c.organization_id,
  o.name AS organization_name,
  o.industry AS organization_industry,
  o.parent_organization_id,
  po.name AS parent_organization_name,

  -- Stats
  (
    SELECT count(DISTINCT conv.id)
    FROM public.conversations conv
    WHERE conv.primary_contact_id = c.id
  ) AS thread_count,
  (
    SELECT count(*) FROM public.emails e
    WHERE e.contact_id = c.id
  ) AS total_emails,
  (
    SELECT count(*) FROM public.emails e
    WHERE e.contact_id = c.id AND e.direction = 'incoming'
  ) AS emails_received,
  (
    SELECT count(*) FROM public.emails e
    WHERE e.contact_id = c.id AND e.direction = 'outgoing'
  ) AS emails_sent,
  (
    SELECT max(e.received_at) FROM public.emails e
    WHERE e.contact_id = c.id
  ) AS last_contact_at,

  -- Reply rate: of incoming emails the contact sent us, fraction whose
  -- conversation also contains a later outgoing email from us. Caps at 1.0.
  -- Returns 0.0 when total_received = 0.
  (
    SELECT
      CASE
        WHEN count(DISTINCT inc.id) = 0 THEN 0::numeric
        ELSE LEAST(
          1.0::numeric,
          count(DISTINCT inc.id) FILTER (
            WHERE EXISTS (
              SELECT 1 FROM public.emails out_e
              WHERE out_e.conversation_id = inc.conversation_id
                AND out_e.direction = 'outgoing'
                AND out_e.received_at > inc.received_at
            )
          )::numeric / count(DISTINCT inc.id)::numeric
        )
      END
    FROM public.emails inc
    WHERE inc.contact_id = c.id AND inc.direction = 'incoming'
  ) AS reply_rate

FROM public.contacts c
LEFT JOIN public.organizations o  ON o.id  = c.organization_id
LEFT JOIN public.organizations po ON po.id = o.parent_organization_id;

GRANT SELECT ON public.v_contact_engagement_profile TO authenticated, service_role;

COMMENT ON VIEW public.v_contact_engagement_profile IS
  'Train D: single-query feed for ContactDetailModal Overview tab. Joins '
  'contacts + organization (with parent) + per-contact aggregates for stats '
  'card. Engagement summary fields surfaced here are populated lazily by the '
  'Train E generator (placeholder values shown in UI when null).';

-- 2. Feature flag for frontend modal cutover
INSERT INTO public.system_config (key, value, description)
VALUES (
  'ui.contact_detail_v2',
  'true'::jsonb,
  'Train D rollback flag. When true, contact rows open the new 4-tab '
  'ContactDetailModal (Overview/Conversations/Drafts/Notes). When false, '
  'falls back to the legacy ContactDetailDialog. Flip to false to disable '
  'the new modal without redeploy.'
)
ON CONFLICT (key) DO NOTHING;

COMMIT;
