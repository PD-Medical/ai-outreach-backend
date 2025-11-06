-- ============================================================================
-- Cron Helper Functions
-- ============================================================================
-- Helper functions for the toggle-cron-job Edge Function
-- These allow Edge Functions to interact with cron.job table
-- ============================================================================

-- Function to check if cron job exists
CREATE OR REPLACE FUNCTION public.check_cron_job_exists(job_name text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  job_exists boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = job_name
  ) INTO job_exists;
  
  RETURN job_exists;
END;
$$;

-- Function to execute dynamic SQL (for scheduling/unscheduling cron jobs)
CREATE OR REPLACE FUNCTION public.exec_sql(sql text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  EXECUTE sql;
END;
$$;

-- Function to get database settings
CREATE OR REPLACE FUNCTION public.get_db_settings()
RETURNS TABLE(
  supabase_url text,
  service_role_key text
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    current_setting('app.settings.supabase_url', true),
    current_setting('app.settings.service_role_key', true);
END;
$$;

-- Function to get cron job status
CREATE OR REPLACE FUNCTION public.get_cron_job_status(job_name text)
RETURNS TABLE(
  jobid bigint,
  schedule text,
  command text,
  nodename text,
  nodeport integer,
  database text,
  username text,
  active boolean,
  jobname text
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    j.jobid,
    j.schedule,
    j.command,
    j.nodename,
    j.nodeport,
    j.database,
    j.username,
    j.active,
    j.jobname
  FROM cron.job j
  WHERE j.jobname = get_cron_job_status.job_name;
END;
$$;

-- Function to get recent cron job runs
CREATE OR REPLACE FUNCTION public.get_cron_job_runs(job_name text, limit_count integer DEFAULT 10)
RETURNS TABLE(
  runid bigint,
  job_pid integer,
  status text,
  return_message text,
  start_time timestamp with time zone,
  end_time timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    r.runid,
    r.job_pid,
    r.status,
    r.return_message,
    r.start_time,
    r.end_time
  FROM cron.job_run_details r
  WHERE r.jobname = get_cron_job_runs.job_name
  ORDER BY r.start_time DESC
  LIMIT limit_count;
END;
$$;

-- Grant execute permissions to authenticated and service role
GRANT EXECUTE ON FUNCTION public.check_cron_job_exists TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.exec_sql TO service_role; -- Only service role can execute SQL
GRANT EXECUTE ON FUNCTION public.get_db_settings TO service_role;
GRANT EXECUTE ON FUNCTION public.get_cron_job_status TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_cron_job_runs TO authenticated, service_role;

-- Add comments
COMMENT ON FUNCTION public.check_cron_job_exists IS 'Check if a cron job exists by name';
COMMENT ON FUNCTION public.exec_sql IS 'Execute dynamic SQL (service role only) - used for scheduling/unscheduling cron jobs';
COMMENT ON FUNCTION public.get_db_settings IS 'Get database configuration settings for cron job';
COMMENT ON FUNCTION public.get_cron_job_status IS 'Get details about a specific cron job';
COMMENT ON FUNCTION public.get_cron_job_runs IS 'Get recent execution history for a cron job';


