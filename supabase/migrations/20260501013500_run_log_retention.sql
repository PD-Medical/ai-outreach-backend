-- 20260501013500_run_log_retention.sql
SELECT cron.schedule(
  'email-sync-run-log-retention',
  '15 3 * * *',  -- 03:15 UTC daily
  $$
  DELETE FROM email_sync_run_log
  WHERE started_at < now() - interval '30 days';
  $$
);
