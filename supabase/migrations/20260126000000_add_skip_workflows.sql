-- ============================================================================
-- Add skip_workflows flag to emails table
-- Prevents workflow matching on imported legacy emails
-- ============================================================================

ALTER TABLE public.emails
ADD COLUMN skip_workflows boolean NOT NULL DEFAULT false;

-- Update trigger function to check skip_workflows
CREATE OR REPLACE FUNCTION public.trigger_workflow_matching() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  lambda_url TEXT;
BEGIN
  -- Skip if category hasn't changed (for UPDATE)
  IF TG_OP = 'UPDATE' AND OLD.email_category IS NOT DISTINCT FROM NEW.email_category THEN
    RETURN NEW;
  END IF;

  -- Skip if workflows are explicitly disabled for this email
  IF NEW.skip_workflows = true THEN
    RETURN NEW;
  END IF;

  -- Skip if workflow matching has already been triggered for this email
  IF NEW.workflow_matched_at IS NOT NULL THEN
    RAISE NOTICE 'Workflow matching already triggered for email %, skipping', NEW.id;
    RETURN NEW;
  END IF;

  -- Get Lambda URL from system_config
  SELECT value #>> '{}' INTO lambda_url FROM system_config WHERE key = 'workflow_matcher_url';
  IF lambda_url IS NULL OR lambda_url = '' THEN
    RETURN NEW;
  END IF;

  -- Skip outgoing emails
  IF NEW.direction = 'outgoing' THEN
    RETURN NEW;
  END IF;

  -- Skip non-business or null categories
  IF NEW.email_category IS NULL OR NOT NEW.email_category LIKE 'business-%' THEN
    RETURN NEW;
  END IF;

  -- Skip transactional emails
  IF NEW.email_category = 'business-transactional' THEN
    RETURN NEW;
  END IF;

  -- Mark as matched and invoke workflow matcher
  NEW.workflow_matched_at := NOW();

  BEGIN
    PERFORM net.http_post(
      url := lambda_url,
      headers := '{"Content-Type": "application/json"}'::jsonb,
      body := json_build_object('email_id', NEW.id)::jsonb,
      timeout_milliseconds := 30000
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Failed to trigger workflow matcher for %: %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;
