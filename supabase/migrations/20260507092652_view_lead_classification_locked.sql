-- ============================================================================
-- v_contact_engagement_profile — surface lead_classification_locked
-- ============================================================================
-- The previous migration added contacts.lead_classification_locked so an
-- operator can pin a contact's classification. The frontend reads contact
-- detail through v_contact_engagement_profile, so the new column needs to
-- flow through the view too — otherwise the UI can't know whether a row's
-- classification is currently AI-driven or operator-locked, and can't
-- decide whether to render the "Reset to AI" affordance.
--
-- Pure additive change. CREATE OR REPLACE VIEW preserves existing grants.
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
  c.lead_classification_locked,
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

  -- Reply rate: of incoming emails THIS contact sent us, fraction whose
  -- conversation contains a later outgoing email TO THIS SAME CONTACT.
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
  ) AS reply_rate

FROM public.contacts c
LEFT JOIN public.organizations o  ON o.id  = c.organization_id
LEFT JOIN public.organizations po ON po.id = o.parent_organization_id;
