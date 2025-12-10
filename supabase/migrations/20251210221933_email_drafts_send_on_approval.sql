-- ============================================================================
-- EMAIL DRAFTS SEND ON APPROVAL TRIGGER
-- ============================================================================
-- When email_drafts.approval_status changes to 'approved' or 'auto_approved',
-- this trigger invokes the send-approved-drafts edge function via pg_net.
-- ============================================================================

-- Ensure pg_net extension is available
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Replace the trigger function to also invoke send-approved-drafts edge function
CREATE OR REPLACE FUNCTION public.handle_email_drafts_approval() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_edge_function_url text;
BEGIN
  -- Only react when approval_status actually changes to an approved state
  IF TG_OP = 'UPDATE'
     AND NEW.approval_status IS DISTINCT FROM OLD.approval_status
     AND NEW.approval_status IN ('approved', 'auto_approved') THEN

    -- Set approved_at if not already set
    IF NEW.approved_at IS NULL THEN
      NEW.approved_at := now();
    END IF;

    -- Get edge function URL from system_config
    SELECT value#>>'{}'
    INTO v_edge_function_url
    FROM system_config
    WHERE key = 'send_approved_drafts_url';

    -- Invoke edge function to send the email immediately
    IF v_edge_function_url IS NOT NULL THEN
      PERFORM net.http_post(
        url := v_edge_function_url,
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := jsonb_build_object(
          'draft_id', NEW.id,
          'triggered_at', now()::text
        ),
        timeout_milliseconds := 30000
      );
    ELSE
      RAISE WARNING 'send_approved_drafts_url not configured in system_config';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Add URL to system_config (update with actual Supabase project URL)
INSERT INTO system_config (key, value, description)
VALUES (
  'send_approved_drafts_url',
  '"https://yuiqdslwixpcudtqnrox.supabase.co/functions/v1/send-approved-drafts"'::jsonb,
  'URL for send-approved-drafts edge function that sends approved emails via Resend'
)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- Log the migration
DO $$
BEGIN
  RAISE NOTICE 'Email drafts send-on-approval trigger migration complete.';
  RAISE NOTICE '  - handle_email_drafts_approval() now invokes send-approved-drafts edge function';
  RAISE NOTICE '  - URL configured in system_config.send_approved_drafts_url';
END $$;
