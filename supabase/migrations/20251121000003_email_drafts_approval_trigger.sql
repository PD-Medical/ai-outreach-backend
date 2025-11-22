-- ============================================================================
-- Migration: Email Drafts Approval Trigger
-- ============================================================================
-- Purpose:
--   - Add a trigger on email_drafts so that when approval_status changes to
--     'approved' or 'auto_approved', the approved_at timestamp is populated.
--   - Sending logic is handled by the send-approved-drafts Edge Function,
--     which reads from email_drafts directly.
-- ============================================================================

-- 1) Function: handle approval metadata on email_drafts
CREATE OR REPLACE FUNCTION public.handle_email_drafts_approval()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Only react when approval_status actually changes to an approved state
  IF TG_OP = 'UPDATE'
     AND NEW.approval_status IS DISTINCT FROM OLD.approval_status
     AND NEW.approval_status IN ('approved', 'auto_approved') THEN

    -- Set approved_at if not already set
    IF NEW.approved_at IS NULL THEN
      NEW.approved_at := now();
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- 2) Trigger: run before update on email_drafts
DROP TRIGGER IF EXISTS email_drafts_approval_trigger ON public.email_drafts;
CREATE TRIGGER email_drafts_approval_trigger
BEFORE UPDATE ON public.email_drafts
FOR EACH ROW
EXECUTE FUNCTION public.handle_email_drafts_approval();

COMMENT ON FUNCTION public.handle_email_drafts_approval() IS
'When email_drafts.approval_status changes to approved/auto_approved, populate approved_at.';
