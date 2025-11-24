-- Add workflow_matched_at column to prevent duplicate workflow matching triggers
ALTER TABLE emails ADD COLUMN IF NOT EXISTS workflow_matched_at TIMESTAMP WITH TIME ZONE;

-- Update trigger function to check workflow_matched_at flag
CREATE OR REPLACE FUNCTION trigger_workflow_matching()
RETURNS TRIGGER AS $$
DECLARE
  lambda_url TEXT;
BEGIN
  -- Skip if category hasn't changed (for UPDATEs) - prevents duplicate triggers
  IF TG_OP = 'UPDATE' AND OLD.email_category IS NOT DISTINCT FROM NEW.email_category THEN
    RETURN NEW;
  END IF;

  -- Skip if workflow matching has already been triggered for this email
  IF NEW.workflow_matched_at IS NOT NULL THEN
    RAISE NOTICE 'Workflow matching already triggered for email %, skipping', NEW.id;
    RETURN NEW;
  END IF;

  -- Get Lambda URL from system_config table
  SELECT value #>> '{}' INTO lambda_url
  FROM system_config
  WHERE key = 'workflow_matcher_url';

  -- Skip if no URL configured
  IF lambda_url IS NULL OR lambda_url = '' THEN
    RAISE NOTICE 'Workflow matcher URL not configured, skipping for email %', NEW.id;
    RETURN NEW;
  END IF;

  -- Only trigger for business emails
  IF NEW.direction = 'outgoing' THEN
    RAISE NOTICE 'Skipping workflow matcher for outgoing email %', NEW.id;
    RETURN NEW;
  END IF;

  IF NEW.email_category IS NULL OR NOT NEW.email_category LIKE 'business-%' THEN
    RAISE NOTICE 'Skipping workflow matcher for non-business email % (category: %)', NEW.id, NEW.email_category;
    RETURN NEW;
  END IF;

  IF NEW.email_category = 'business-transactional' THEN
    RAISE NOTICE 'Skipping workflow matcher for transactional email %', NEW.id;
    RETURN NEW;
  END IF;

  -- Mark that workflow matching has been triggered (prevents duplicate triggers)
  NEW.workflow_matched_at := NOW();

  -- Trigger Lambda asynchronously using pg_net
  BEGIN
    PERFORM net.http_post(
      url := lambda_url,
      headers := '{"Content-Type": "application/json"}'::jsonb,
      body := json_build_object('email_id', NEW.id)::jsonb,
      timeout_milliseconds := 30000
    );

    RAISE NOTICE 'Triggered workflow matcher for email %', NEW.id;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Failed to trigger workflow matcher for %: %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON COLUMN emails.workflow_matched_at IS 'Timestamp when workflow matching was triggered for this email (prevents duplicate triggers)';
