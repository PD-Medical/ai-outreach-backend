-- ============================================================================
-- Migration: Fix Auth Tracking for System-Generated Tables
-- ============================================================================
-- Description: Remove auth_user_tracking triggers from system-generated tables
-- Date: 2025-11-17
-- Issue: Lambda IMAP sync failing because emails/conversations are auto-created
-- ============================================================================

-- ============================================================================
-- STEP 1: Remove triggers from purely system-generated tables
-- ============================================================================

-- Emails are created by Lambda IMAP sync (service_role), not by users
DROP TRIGGER IF EXISTS trigger_emails_auth_tracking ON emails;

-- Conversations are auto-created from email threads by Lambda, not by users
DROP TRIGGER IF EXISTS trigger_conversations_auth_tracking ON conversations;

-- ============================================================================
-- STEP 2: Keep triggers on user-created or mixed tables
-- ============================================================================
-- These triggers remain active:
-- - trigger_contacts_auth_tracking (mixed: user OR Lambda creates)
-- - trigger_campaigns_auth_tracking (user creates)
-- - trigger_organizations_auth_tracking (mixed: user OR Lambda creates)
-- - trigger_contact_product_interests_auth_tracking (user creates)
-- ============================================================================

-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
DECLARE
  trigger_count INTEGER;
BEGIN
  -- Verify emails trigger was removed
  SELECT COUNT(*) INTO trigger_count
  FROM information_schema.triggers
  WHERE trigger_name = 'trigger_emails_auth_tracking'
    AND event_object_table = 'emails';

  IF trigger_count > 0 THEN
    RAISE EXCEPTION 'Failed: trigger_emails_auth_tracking still exists on emails';
  END IF;

  -- Verify conversations trigger was removed
  SELECT COUNT(*) INTO trigger_count
  FROM information_schema.triggers
  WHERE trigger_name = 'trigger_conversations_auth_tracking'
    AND event_object_table = 'conversations';

  IF trigger_count > 0 THEN
    RAISE EXCEPTION 'Failed: trigger_conversations_auth_tracking still exists on conversations';
  END IF;

  RAISE NOTICE '✅ Migration completed successfully!';
  RAISE NOTICE '✅ Removed auth tracking from emails (Lambda IMAP sync)';
  RAISE NOTICE '✅ Removed auth tracking from conversations (auto-created)';
  RAISE NOTICE '✅ Lambda function should now work without errors';
END $$;
