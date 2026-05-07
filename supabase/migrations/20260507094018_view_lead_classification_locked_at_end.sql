-- ============================================================================
-- v_contact_engagement_profile — append lead_classification_locked at end
-- ============================================================================
-- The previous attempt (20260507092652) tried to insert
-- lead_classification_locked between lead_classification and engagement_level
-- in the SELECT list. Postgres's CREATE OR REPLACE VIEW refuses to rename or
-- shift existing columns:
--
--   ERROR: cannot change name of view column "engagement_level" to
--          "lead_classification_locked" (SQLSTATE 42P16)
--
-- Workaround: re-create the view with the new column appended at the END of
-- the SELECT list. Existing column positions are preserved, the new column
-- gets a slot after reply_rate. Frontend reads `lead_classification_locked`
-- by name, not position, so order is irrelevant to the consumer.
--
-- The previous (failed) migration is left in the history for traceability
-- but never executed against the remote DB.
-- ============================================================================

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

  (
    SELECT
      CASE
        WHEN count(DISTINCT inc.id) = 0 THEN 0::numeric
        ELSE
          count(DISTINCT inc.id) FILTER (
            WHERE EXISTS (
              SELECT 1 FROM public.emails out_e
              WHERE out_e.conversation_id = inc.conversation_id
                AND out_e.contact_id     = c.id
                AND out_e.direction      = 'outgoing'
                AND COALESCE(out_e.sent_at, out_e.received_at)
                  > COALESCE(inc.sent_at,   inc.received_at)
            )
          )::numeric / count(DISTINCT inc.id)::numeric
      END
    FROM public.emails inc
    WHERE inc.contact_id = c.id AND inc.direction = 'incoming'
  ) AS reply_rate,

  -- Appended at the END of the SELECT list to satisfy CREATE OR REPLACE VIEW.
  c.lead_classification_locked

FROM public.contacts c
LEFT JOIN public.organizations o  ON o.id  = c.organization_id
LEFT JOIN public.organizations po ON po.id = o.parent_organization_id;
