-- 20260502130700_run_log_retention.sql
-- Make this migration idempotent: cron.schedule() rejects duplicate jobnames,
-- so unschedule any pre-existing entry before re-creating it.
SELECT cron.unschedule('email-sync-run-log-retention')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'email-sync-run-log-retention');

SELECT cron.schedule(
  'email-sync-run-log-retention',
  '15 3 * * *',  -- 03:15 UTC daily
  $$
  DELETE FROM email_sync_run_log
  WHERE started_at < now() - interval '30 days';
  $$
);
