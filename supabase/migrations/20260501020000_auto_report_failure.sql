-- 20260501020000_auto_report_failure.sql
-- Requires pg_net extension (Supabase enables it by default).
-- This migration is idempotent via a guarded unschedule, matching Phase 1 convention.
--
-- IMPORTANT: This cron job uses pg_net to POST to the report-import-failure-to-github
-- edge function. It depends on two Postgres-level config settings that MUST be set
-- once per environment (out-of-band, not in this migration):
--
--   ALTER DATABASE postgres SET app.settings.supabase_url = 'https://<project-ref>.supabase.co';
--   ALTER DATABASE postgres SET app.settings.service_role_key = '<service-role-key>';
--
-- These are read via current_setting() at cron-trigger time. If they're missing,
-- the cron job runs but the http_post fails silently (and is observable via
-- net._http_response).

SELECT cron.unschedule('auto-report-failure-groups')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'auto-report-failure-groups');

SELECT cron.schedule(
  'auto-report-failure-groups',
  '*/15 * * * *',
  $$
  WITH unreported AS (
    SELECT id FROM email_import_failure_groups
    WHERE github_issue_url IS NULL
      AND occurrence_count >= 3
      AND resolved_at IS NULL
    LIMIT 5
  )
  SELECT
    net.http_post(
      url := current_setting('app.settings.supabase_url') || '/functions/v1/report-import-failure-to-github',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key')
      ),
      body := jsonb_build_object('failure_group_id', id)
    )
  FROM unreported;
  $$
);
