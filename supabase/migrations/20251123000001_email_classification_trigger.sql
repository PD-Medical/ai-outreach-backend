-- Workflow Matching Trigger
-- Automatically triggers workflow-matcher after email is classified

-- Create function to trigger workflow-matcher Lambda
CREATE OR REPLACE FUNCTION trigger_workflow_matching()
RETURNS TRIGGER AS $$
DECLARE
  lambda_url TEXT;
  response_status INT;
BEGIN
  -- Skip if category hasn't changed (for UPDATEs) - prevents duplicate triggers
  IF TG_OP = 'UPDATE' AND OLD.email_category IS NOT DISTINCT FROM NEW.email_category THEN
    RETURN NEW;
  END IF;

  -- Get Lambda URL from system_config table
  -- For local dev: http://host.docker.internal:3001/workflow-matcher
  -- For production: AWS Lambda Function URL
  SELECT value #>> '{}' INTO lambda_url
  FROM system_config
  WHERE key = 'workflow_matcher_url';

  -- Skip if no URL configured
  IF lambda_url IS NULL OR lambda_url = '' THEN
    RAISE NOTICE 'Workflow matcher URL not configured, skipping for email %', NEW.id;
    RETURN NEW;
  END IF;

  -- Only trigger for business emails
  -- Skip if:
  -- 1. Email is outgoing (direction = 'outgoing')
  -- 2. Not a business email (email_category doesn't start with 'business-')
  -- 3. Category is transactional (business-transactional)
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

  -- Trigger Lambda asynchronously using pg_net
  -- This requires pg_net extension
  BEGIN
    PERFORM net.http_post(
      url := lambda_url,
      headers := '{"Content-Type": "application/json"}'::jsonb,
      body := json_build_object('email_id', NEW.id)::jsonb,
      timeout_milliseconds := 30000
    );

    RAISE NOTICE 'Triggered workflow matcher for email %', NEW.id;
  EXCEPTION WHEN OTHERS THEN
    -- Log error but don't fail the operation
    RAISE WARNING 'Failed to trigger workflow matcher for %: %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger on emails table - fires on INSERT or UPDATE when email_category is set
-- Deduplication is handled in the trigger function itself
DROP TRIGGER IF EXISTS trigger_match_workflows ON emails;
CREATE TRIGGER trigger_match_workflows
  AFTER INSERT OR UPDATE OF email_category ON emails
  FOR EACH ROW
  WHEN (NEW.email_category IS NOT NULL AND NEW.email_category LIKE 'business-%')
  EXECUTE FUNCTION trigger_workflow_matching();

-- Enable pg_net extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_net;

COMMENT ON FUNCTION trigger_workflow_matching() IS 'Triggers workflow-matcher Lambda for classified business emails';
COMMENT ON TRIGGER trigger_match_workflows ON emails IS 'Automatically matches workflows for business emails after classification';
