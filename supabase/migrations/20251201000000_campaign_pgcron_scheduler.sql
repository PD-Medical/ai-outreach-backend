-- ============================================================================
-- CAMPAIGN PG_CRON SCHEDULER MIGRATION
-- ============================================================================
-- Replaces EventBridge polling with conditional pg_cron jobs that only invoke
-- Lambda functions when there is actual work to do.
--
-- Cost Optimization:
--   - EventBridge: ~17,280 Lambda invocations/month (regardless of work)
--   - pg_cron: Only invokes when campaigns/enrollments are due
-- ============================================================================

-- Ensure pg_cron and pg_net extensions are enabled
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Grant usage to postgres role (required for pg_cron)
GRANT USAGE ON SCHEMA cron TO postgres;

-- ============================================================================
-- Campaign Scheduler pg_cron Job
-- ============================================================================
-- Checks every 5 minutes if any recurring campaigns are due for execution.
-- Only invokes the Lambda function if there are campaigns to process.
-- ============================================================================

SELECT cron.schedule(
  'campaign-scheduler-conditional',
  '*/5 * * * *',
  $$
  DO $$
  DECLARE
    v_url text;
    v_has_work boolean;
  BEGIN
    -- Check if there are any campaigns due for execution
    SELECT EXISTS (
      SELECT 1 FROM campaign_sequences
      WHERE next_run_at <= NOW()
      AND status IN ('scheduled', 'running')
      AND recurrence_pattern != 'none'
      LIMIT 1
    ) INTO v_has_work;

    -- Only invoke Lambda if there is work to do
    IF v_has_work THEN
      -- Get the Lambda URL from system_config
      SELECT value#>>'{}' INTO v_url
      FROM system_config
      WHERE key = 'campaign_scheduler_url';

      IF v_url IS NOT NULL THEN
        PERFORM net.http_post(
          url := v_url,
          headers := '{"Content-Type": "application/json"}'::jsonb,
          body := jsonb_build_object(
            'triggered_at', now()::text,
            'source', 'pg_cron'
          ),
          timeout_milliseconds := 60000
        );
        RAISE NOTICE 'Campaign scheduler Lambda invoked at %', NOW();
      ELSE
        RAISE WARNING 'campaign_scheduler_url not configured in system_config';
      END IF;
    END IF;
  END $$;
  $$
);

-- ============================================================================
-- Campaign Executor pg_cron Job
-- ============================================================================
-- Checks every 5 minutes if any campaign enrollments are due for processing.
-- Only invokes the Lambda function if there are enrollments to process.
-- ============================================================================

SELECT cron.schedule(
  'campaign-executor-conditional',
  '*/5 * * * *',
  $$
  DO $$
  DECLARE
    v_url text;
    v_has_work boolean;
  BEGIN
    -- Check if there are any enrollments due for execution
    SELECT EXISTS (
      SELECT 1 FROM campaign_enrollments ce
      JOIN campaign_sequences cs ON ce.campaign_sequence_id = cs.id
      WHERE ce.status = 'enrolled'
      AND ce.next_send_date <= NOW()
      AND cs.status = 'running'
      LIMIT 1
    ) INTO v_has_work;

    -- Only invoke Lambda if there is work to do
    IF v_has_work THEN
      -- Get the Lambda URL from system_config
      SELECT value#>>'{}' INTO v_url
      FROM system_config
      WHERE key = 'campaign_executor_url';

      IF v_url IS NOT NULL THEN
        PERFORM net.http_post(
          url := v_url,
          headers := '{"Content-Type": "application/json"}'::jsonb,
          body := jsonb_build_object(
            'triggered_at', now()::text,
            'source', 'pg_cron'
          ),
          timeout_milliseconds := 60000
        );
        RAISE NOTICE 'Campaign executor Lambda invoked at %', NOW();
      ELSE
        RAISE WARNING 'campaign_executor_url not configured in system_config';
      END IF;
    END IF;
  END $$;
  $$
);

-- ============================================================================
-- Helper function to view scheduled cron jobs
-- ============================================================================
COMMENT ON EXTENSION pg_cron IS 'Campaign scheduling uses pg_cron for cost-efficient Lambda invocation';

-- Log the migration
DO $$
BEGIN
  RAISE NOTICE 'Campaign pg_cron scheduler migration complete. Jobs scheduled:';
  RAISE NOTICE '  - campaign-scheduler-conditional (every 5 min, conditional)';
  RAISE NOTICE '  - campaign-executor-conditional (every 5 min, conditional)';
END $$;
