-- 20260502130600_stuck_job_watchdog.sql
-- Requires pg_cron extension (already enabled per project conventions; verify in dashboard).
-- Make this migration idempotent: cron.schedule() rejects duplicate jobnames,
-- so unschedule any pre-existing entry before re-creating it.
SELECT cron.unschedule('email-import-jobs-watchdog')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'email-import-jobs-watchdog');

SELECT cron.schedule(
  'email-import-jobs-watchdog',
  '*/5 * * * *',
  $$
  WITH reset AS (
    UPDATE email_import_jobs
    SET status = 'failed',
        last_error = 'Job stopped responding (no progress for 30 minutes)',
        completed_at = now()
    WHERE status = 'running'
      AND updated_at < now() - interval '30 minutes'
    RETURNING id
  )
  INSERT INTO email_sync_run_log (process, started_at, completed_at, outcome, emails_processed)
  SELECT 'watchdog', now(), now(),
         CASE WHEN COUNT(*) = 0 THEN 'Nothing stuck'
              ELSE 'Reset ' || COUNT(*) || ' stuck job(s)' END,
         COUNT(*)
  FROM reset;
  $$
);
