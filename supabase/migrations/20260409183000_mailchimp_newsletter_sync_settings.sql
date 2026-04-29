CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

GRANT USAGE ON SCHEMA cron TO postgres;

INSERT INTO public.system_config (key, value, description) VALUES
  ('mailchimp_newsletter_sync_enabled', 'false'::jsonb, 'Toggle scheduled sync of external Mailchimp newsletters.'),
  ('mailchimp_newsletter_sync_schedule_rate', '"30 minutes"'::jsonb, 'Schedule rate for syncing external Mailchimp newsletters.'),
  ('mailchimp_newsletter_sync_lookback_days', '30'::jsonb, 'How many days back to scan for recently sent Mailchimp newsletters when syncing.'),
  ('mailchimp_newsletter_sync_limit', '25'::jsonb, 'Maximum number of sent Mailchimp campaigns to fetch per sync run.')
ON CONFLICT (key) DO NOTHING;
