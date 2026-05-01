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
-- The cron body uses the missing_ok form of current_setting() and a guard so a
-- missing GUC produces a visible WARNING (in cron.job_run_details.return_message)
-- instead of crashing the cron statement.

SELECT cron.unschedule('auto-report-failure-groups')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'auto-report-failure-groups');

SELECT cron.schedule(
  'auto-report-failure-groups',
  '*/15 * * * *',
  $$
  DO $body$
  DECLARE
    v_url TEXT := current_setting('app.settings.supabase_url', true);
    v_key TEXT := current_setting('app.settings.service_role_key', true);
  BEGIN
    IF v_url IS NULL OR v_key IS NULL THEN
      RAISE WARNING 'auto-report-failure-groups: app.settings.supabase_url or service_role_key not set; skipping run';
      RETURN;
    END IF;

    PERFORM
      net.http_post(
        url := v_url || '/functions/v1/report-import-failure-to-github',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_key
        ),
        body := jsonb_build_object('failure_group_id', g.id)
      )
    FROM (
      SELECT id FROM email_import_failure_groups
      WHERE github_issue_url IS NULL
        AND occurrence_count >= 3
        AND resolved_at IS NULL
      LIMIT 5
    ) g;
  END
  $body$;
  $$
);
