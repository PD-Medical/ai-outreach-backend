-- ============================================================================
-- Email Sync System - pg_cron Setup
-- ============================================================================
-- This migration configures pg_cron but does NOT schedule the job automatically.
-- The cron job should be enabled AFTER completing legacy data import.
-- 
-- Prerequisites:
-- 1. pg_cron and pg_net extensions must be enabled (done in previous migration)
-- 2. sync-emails Edge Function must be deployed
-- 3. Database settings must be configured (see below)
--
-- Configuration required (set via Supabase dashboard or SQL):
--   ALTER DATABASE postgres SET app.settings.supabase_url = 'https://[project-ref].supabase.co';
--   ALTER DATABASE postgres SET app.settings.service_role_key = '[your-service-role-key]';
--
-- TO ENABLE THE CRON JOB:
-- Option 1: Call the toggle-cron-job Edge Function (POST with {"enabled": true})
-- Option 2: Run the SQL command in the "MANUAL CRON SETUP" section below
-- ============================================================================

-- Unschedule existing job if it exists (for cleanup)
SELECT cron.unschedule('sync-emails-every-minute') WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'sync-emails-every-minute'
);

-- NOTE: Cron job is NOT scheduled by default. Enable it after legacy import.
-- See "MANUAL CRON SETUP" section below for the SQL command to enable it.

-- ============================================================================
-- MONITORING QUERIES
-- ============================================================================
-- Use these queries to monitor the cron job:

-- View scheduled jobs
-- SELECT * FROM cron.job;

-- View recent job runs (last 10)
-- SELECT * FROM cron.job_run_details 
-- WHERE jobname = 'sync-emails-every-minute'
-- ORDER BY start_time DESC 
-- LIMIT 10;

-- View failed job runs
-- SELECT * FROM cron.job_run_details 
-- WHERE jobname = 'sync-emails-every-minute' 
--   AND status = 'failed'
-- ORDER BY start_time DESC;

-- ============================================================================
-- MANUAL CRON SETUP (Run this AFTER legacy import is complete)
-- ============================================================================
-- To enable automatic email synchronization, schedule the cron job:

/*
SELECT cron.schedule(
  'sync-emails-every-minute',           -- Job name
  '* * * * *',                          -- Every minute (cron syntax)
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.supabase_url', true) || '/functions/v1/sync-emails',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
    ),
    body := jsonb_build_object(
      'triggered_at', now(),
      'source', 'pg_cron',
      'job_name', 'sync-emails-every-minute'
    ),
    timeout_milliseconds := 55000  -- 55 second timeout (under Edge Function limit)
  ) AS request_id;
  $$
);
*/

-- To disable the cron job:
-- SELECT cron.unschedule('sync-emails-every-minute');

-- ============================================================================
-- CONFIGURATION INSTRUCTIONS
-- ============================================================================
-- After applying this migration, set the required configuration:
--
-- 1. Get your Supabase project URL and service role key from the dashboard
--
-- 2. Set the database configuration (replace values):
--    ALTER DATABASE postgres SET app.settings.supabase_url = 'https://[project-ref].supabase.co';
--    ALTER DATABASE postgres SET app.settings.service_role_key = '[your-service-role-key]';
--
-- 3. Verify the configuration:
--    SELECT current_setting('app.settings.supabase_url', true);
--    SELECT current_setting('app.settings.service_role_key', true);
--
-- 4. Complete legacy import for all mailboxes
--
-- 5. Enable the cron job using one of these methods:
--    a) Call toggle-cron-job Edge Function: POST {"enabled": true}
--    b) Run the SQL in "MANUAL CRON SETUP" section above
--
-- 6. Monitor the job:
--    SELECT * FROM cron.job_run_details 
--    WHERE jobname = 'sync-emails-every-minute'
--    ORDER BY start_time DESC LIMIT 10;
-- ============================================================================

-- Add helpful comment
COMMENT ON EXTENSION pg_cron IS 'PostgreSQL job scheduler - used for automated email synchronization';

