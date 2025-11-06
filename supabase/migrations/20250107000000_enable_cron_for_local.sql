-- ============================================================================
-- Enable Cron Job for Local Development
-- ============================================================================
-- This migration updates the cron job to work in local development by
-- hardcoding the local URLs instead of using database settings.
-- ============================================================================

-- First, unschedule the existing job if it exists
SELECT cron.unschedule('sync-emails-every-minute') WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'sync-emails-every-minute'
);

-- Schedule the cron job with hardcoded local development URLs
-- This will work immediately in local development without additional configuration
SELECT cron.schedule(
  'sync-emails-every-minute',           -- Job name
  '* * * * *',                          -- Every minute (cron syntax)
  $$
  SELECT net.http_post(
    url := 'http://host.docker.internal:54321/functions/v1/sync-emails',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU'
    ),
    body := jsonb_build_object(
      'triggered_at', now(),
      'source', 'pg_cron',
      'job_name', 'sync-emails-every-minute'
    ),
    timeout_milliseconds := 55000  -- 55 second timeout
  ) AS request_id;
  $$
);

-- ============================================================================
-- NOTES
-- ============================================================================
-- This migration is for LOCAL DEVELOPMENT ONLY.
-- 
-- For production deployment:
-- 1. The cron job should use current_setting() to get URLs from database config
-- 2. Set the production URLs using:
--    ALTER DATABASE postgres SET app.settings.supabase_url = 'https://[project].supabase.co';
--    ALTER DATABASE postgres SET app.settings.service_role_key = '[your-key]';
-- 3. Update the cron job to use current_setting() instead of hardcoded values
-- ============================================================================

-- Verify the job was scheduled
DO $$
DECLARE
  job_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO job_count FROM cron.job WHERE jobname = 'sync-emails-every-minute';
  
  IF job_count > 0 THEN
    RAISE NOTICE 'Cron job "sync-emails-every-minute" is scheduled and active';
  ELSE
    RAISE WARNING 'Cron job was not scheduled successfully';
  END IF;
END $$;

