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
      SUM(COALESCE(ccs.total_score, 0)) AS campaign_score,
      MAX(ccs.last_event_at) AS last_campaign_event_at
    FROM public.campaign_contact_summary ccs
    GROUP BY ccs.contact_id
  ),
  scored AS (
    SELECT
      c.id,
      c.created_at,
      COALESCE(cs.campaign_score, 0) + COALESCE(c.lead_score, 0) AS total_score,
      COALESCE(c.needs_follow_up, FALSE) AS needs_follow_up,
      COALESCE(c.lead_classification_locked, FALSE) AS lead_classification_locked,
      LOWER(NULLIF(c.lead_classification, '')) AS lead_classification,
      NULLIF(GREATEST(
        COALESCE(cs.last_campaign_event_at, 'epoch'::timestamptz),
        COALESCE(c.last_contact_date, 'epoch'::timestamptz),
        COALESCE(c.updated_at, 'epoch'::timestamptz)
      ), 'epoch'::timestamptz) AS last_active
    FROM external_contacts c
    LEFT JOIN campaign_scores cs ON cs.contact_id = c.id
    WHERE COALESCE(cs.campaign_score, 0) > 0
       OR COALESCE(c.lead_score, 0) > 0
       OR COALESCE(c.needs_follow_up, FALSE) = TRUE
       OR COALESCE(c.lead_classification_locked, FALSE) = TRUE
  ),
  tiered AS (
    SELECT
      *,
      CASE
        WHEN lead_classification_locked AND lead_classification = 'hot' THEN 'HOT'
        WHEN lead_classification_locked AND lead_classification = 'warm' THEN 'WARM'
        WHEN lead_classification_locked AND lead_classification = 'cold' THEN 'COLD'
        WHEN total_score < 0 THEN 'SUPPRESSED'
        WHEN total_score >= 30 THEN 'HOT'
        WHEN total_score >= 15 THEN 'WARM'
        WHEN total_score >= 5 THEN 'ACTIVE'
        ELSE 'COLD'
      END AS tier
    FROM scored
  )
  SELECT jsonb_build_object(
    'totalLeads', COUNT(*),
    'followUpCount', COUNT(*) FILTER (WHERE needs_follow_up),
    'newThisWeek', COUNT(*) FILTER (WHERE created_at >= now() - interval '7 days'),
    'hotOverdue', COUNT(*) FILTER (WHERE tier = 'HOT' AND last_active IS NOT NULL AND last_active < now() - interval '2 hours'),
    'warmOverdue', COUNT(*) FILTER (WHERE tier = 'WARM' AND last_active IS NOT NULL AND last_active < now() - interval '24 hours'),
    'tierCounts', jsonb_build_object(
      'HOT', COUNT(*) FILTER (WHERE tier = 'HOT'),
      'WARM', COUNT(*) FILTER (WHERE tier = 'WARM'),
      'ACTIVE', COUNT(*) FILTER (WHERE tier = 'ACTIVE'),
      'COLD', COUNT(*) FILTER (WHERE tier = 'COLD'),
      'SUPPRESSED', COUNT(*) FILTER (WHERE tier = 'SUPPRESSED')
    )
  )
  FROM tiered;
$$;

GRANT EXECUTE ON FUNCTION public.get_hot_leads_metrics() TO authenticated;
