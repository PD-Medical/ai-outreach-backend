-- Atomic Mailchimp engagement event recording.
-- Keeps campaign_events and campaign_contact_summary consistent for repeated
-- API polling and duplicate external IDs.

CREATE OR REPLACE FUNCTION public.record_mailchimp_campaign_event(
  p_campaign_id uuid,
  p_contact_id uuid,
  p_email text,
  p_event_type public.event_type,
  p_event_timestamp timestamptz,
  p_score integer,
  p_external_id text,
  p_source jsonb,
  p_is_unique_click_score boolean DEFAULT false
)
RETURNS TABLE(status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_id uuid;
BEGIN
  IF p_external_id IS NULL OR btrim(p_external_id) = '' THEN
    RAISE EXCEPTION 'Mailchimp campaign event external_id is required';
  END IF;

  INSERT INTO public.campaign_events (
    campaign_id,
    contact_id,
    email,
    event_type,
    event_timestamp,
    score,
    external_id,
    source
  )
  VALUES (
    p_campaign_id,
    p_contact_id,
    p_email,
    p_event_type,
    p_event_timestamp,
    p_score,
    p_external_id,
    COALESCE(p_source, '{}'::jsonb)
  )
  ON CONFLICT (external_id) WHERE external_id IS NOT NULL DO NOTHING
  RETURNING id INTO v_event_id;

  IF v_event_id IS NULL THEN
    RETURN QUERY SELECT 'skipped_existing'::text;
    RETURN;
  END IF;

  INSERT INTO public.campaign_contact_summary (
    campaign_id,
    contact_id,
    email,
    total_score,
    opened,
    clicked,
    converted,
    first_event_at,
    last_event_at,
    emails_sent,
    emails_delivered,
    emails_opened,
    emails_clicked,
    emails_bounced,
    emails_replied,
    unique_clicks,
    first_opened_at,
    first_clicked_at,
    first_replied_at,
    last_opened_at,
    last_clicked_at,
    workflow_emails_sent,
    workflow_emails_opened,
    workflow_emails_clicked
  )
  VALUES (
    p_campaign_id,
    p_contact_id,
    p_email,
    p_score,
    p_event_type = 'opened'::public.event_type,
    p_event_type = 'clicked'::public.event_type,
    false,
    p_event_timestamp,
    p_event_timestamp,
    CASE WHEN p_event_type = 'sent'::public.event_type THEN 1 ELSE 0 END,
    0,
    CASE WHEN p_event_type = 'opened'::public.event_type THEN 1 ELSE 0 END,
    CASE WHEN p_event_type = 'clicked'::public.event_type THEN 1 ELSE 0 END,
    CASE WHEN p_event_type = 'bounced'::public.event_type THEN 1 ELSE 0 END,
    0,
    CASE WHEN p_event_type = 'clicked'::public.event_type AND p_is_unique_click_score THEN 1 ELSE 0 END,
    CASE WHEN p_event_type = 'opened'::public.event_type THEN p_event_timestamp ELSE NULL END,
    CASE WHEN p_event_type = 'clicked'::public.event_type THEN p_event_timestamp ELSE NULL END,
    NULL,
    CASE WHEN p_event_type = 'opened'::public.event_type THEN p_event_timestamp ELSE NULL END,
    CASE WHEN p_event_type = 'clicked'::public.event_type THEN p_event_timestamp ELSE NULL END,
    0,
    0,
    0
  )
  ON CONFLICT (campaign_id, contact_id) DO UPDATE SET
    email = EXCLUDED.email,
    total_score = public.campaign_contact_summary.total_score + p_score,
    opened = public.campaign_contact_summary.opened OR (p_event_type = 'opened'::public.event_type),
    clicked = public.campaign_contact_summary.clicked OR (p_event_type = 'clicked'::public.event_type),
    first_event_at = COALESCE(public.campaign_contact_summary.first_event_at, p_event_timestamp),
    last_event_at = GREATEST(COALESCE(public.campaign_contact_summary.last_event_at, p_event_timestamp), p_event_timestamp),
    emails_sent = public.campaign_contact_summary.emails_sent + CASE WHEN p_event_type = 'sent'::public.event_type THEN 1 ELSE 0 END,
    emails_opened = public.campaign_contact_summary.emails_opened + CASE WHEN p_event_type = 'opened'::public.event_type THEN 1 ELSE 0 END,
    emails_clicked = public.campaign_contact_summary.emails_clicked + CASE WHEN p_event_type = 'clicked'::public.event_type THEN 1 ELSE 0 END,
    emails_bounced = public.campaign_contact_summary.emails_bounced + CASE WHEN p_event_type = 'bounced'::public.event_type THEN 1 ELSE 0 END,
    unique_clicks = public.campaign_contact_summary.unique_clicks + CASE WHEN p_event_type = 'clicked'::public.event_type AND p_is_unique_click_score THEN 1 ELSE 0 END,
    first_opened_at = CASE
      WHEN p_event_type = 'opened'::public.event_type THEN COALESCE(public.campaign_contact_summary.first_opened_at, p_event_timestamp)
      ELSE public.campaign_contact_summary.first_opened_at
    END,
    last_opened_at = CASE
      WHEN p_event_type = 'opened'::public.event_type THEN GREATEST(COALESCE(public.campaign_contact_summary.last_opened_at, p_event_timestamp), p_event_timestamp)
      ELSE public.campaign_contact_summary.last_opened_at
    END,
    first_clicked_at = CASE
      WHEN p_event_type = 'clicked'::public.event_type THEN COALESCE(public.campaign_contact_summary.first_clicked_at, p_event_timestamp)
      ELSE public.campaign_contact_summary.first_clicked_at
    END,
    last_clicked_at = CASE
      WHEN p_event_type = 'clicked'::public.event_type THEN GREATEST(COALESCE(public.campaign_contact_summary.last_clicked_at, p_event_timestamp), p_event_timestamp)
      ELSE public.campaign_contact_summary.last_clicked_at
    END;

  RETURN QUERY SELECT 'inserted'::text;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_mailchimp_campaign_event(
  uuid,
  uuid,
  text,
  public.event_type,
  timestamptz,
  integer,
  text,
  jsonb,
  boolean
) TO authenticated, service_role;
