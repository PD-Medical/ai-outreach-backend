-- Mailchimp engagement polling sync
-- Bridges external Mailchimp campaign report activity into the native campaign
-- event/summary tables used by Hot Leads and lead scoring views.

ALTER TABLE public.mailchimp_newsletters
  ADD COLUMN IF NOT EXISTS campaign_id uuid REFERENCES public.campaigns(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_campaigns_mailchimp_external_id
  ON public.campaigns(provider, external_id)
  WHERE provider = 'mailchimp' AND external_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_mailchimp_newsletters_campaign_id
  ON public.mailchimp_newsletters(campaign_id)
  WHERE campaign_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.mailchimp_engagement_sync_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source text NOT NULL DEFAULT 'manual',
  status text NOT NULL CHECK (status IN ('running', 'completed', 'failed')),
  requested_by uuid,
  campaign_id text,
  dry_run boolean NOT NULL DEFAULT false,
  stats jsonb NOT NULL DEFAULT '{}'::jsonb,
  error text,
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_mailchimp_engagement_sync_runs_started
  ON public.mailchimp_engagement_sync_runs(started_at DESC);

CREATE INDEX IF NOT EXISTS idx_mailchimp_engagement_sync_runs_campaign
  ON public.mailchimp_engagement_sync_runs(campaign_id, started_at DESC)
  WHERE campaign_id IS NOT NULL;

ALTER TABLE public.mailchimp_engagement_sync_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mailchimp_engagement_sync_runs_select_policy
ON public.mailchimp_engagement_sync_runs;

CREATE POLICY mailchimp_engagement_sync_runs_select_policy
  ON public.mailchimp_engagement_sync_runs
  FOR SELECT
  USING (public.has_permission('view_contacts'::text));

GRANT SELECT ON public.mailchimp_engagement_sync_runs TO authenticated;

INSERT INTO public.system_config (key, value, description)
VALUES
  ('mailchimp_engagement_sync_enabled', 'true'::jsonb, 'Toggle scheduled polling of Mailchimp campaign engagement reports.'),
  ('mailchimp_engagement_sync_schedule_rate', '"1 hour"'::jsonb, 'Schedule rate for polling Mailchimp campaign engagement reports.'),
  ('mailchimp_engagement_sync_lookback_days', '7'::jsonb, 'How many days back to scan synced Mailchimp campaigns for engagement polling.'),
  ('mailchimp_engagement_sync_campaign_limit', '25'::jsonb, 'Maximum number of Mailchimp campaigns to poll for engagement per run.')
ON CONFLICT (key) DO NOTHING;
