-- Canonical email messages cutover phase 2.
--
-- Run this only after:
-- 1. 20260611161000_canonical_email_messages.sql has been applied.
-- 2. scripts/canonical_email_messages/backfill_canonical_email_messages.py --apply
--    has completed.
-- 3. scripts/canonical_email_messages/validate_canonical_email_messages.py
--    has passed.

DO $$
DECLARE
  v_orphan_copies integer;
  v_workflow_mismatches integer;
  v_draft_source_mismatches integer;
  v_draft_sent_mismatches integer;
BEGIN
  SELECT count(*) INTO v_orphan_copies
  FROM public.email_mailbox_copies
  WHERE email_message_id IS NULL;

  IF v_orphan_copies > 0 THEN
    RAISE EXCEPTION
      'Canonical email phase 2 blocked: % email_mailbox_copies rows have null email_message_id',
      v_orphan_copies;
  END IF;

  SELECT count(*) INTO v_workflow_mismatches
  FROM public.workflow_executions we
  JOIN public.email_mailbox_copies c ON c.id = we.email_id
  WHERE we.email_id IS NOT NULL
    AND we.email_message_id IS DISTINCT FROM c.email_message_id;

  IF v_workflow_mismatches > 0 THEN
    RAISE EXCEPTION
      'Canonical email phase 2 blocked: % workflow_executions rows have missing or mismatched email_message_id',
      v_workflow_mismatches;
  END IF;

  SELECT count(*) INTO v_draft_source_mismatches
  FROM public.email_drafts d
  JOIN public.email_mailbox_copies c ON c.id = d.source_email_id
  WHERE d.source_email_id IS NOT NULL
    AND d.source_email_message_id IS DISTINCT FROM c.email_message_id;

  IF v_draft_source_mismatches > 0 THEN
    RAISE EXCEPTION
      'Canonical email phase 2 blocked: % email_drafts rows have missing or mismatched source_email_message_id',
      v_draft_source_mismatches;
  END IF;

  SELECT count(*) INTO v_draft_sent_mismatches
  FROM public.email_drafts d
  JOIN public.email_mailbox_copies c ON c.id = d.sent_email_id
  WHERE d.sent_email_id IS NOT NULL
    AND d.sent_email_message_id IS DISTINCT FROM c.email_message_id;

  IF v_draft_sent_mismatches > 0 THEN
    RAISE EXCEPTION
      'Canonical email phase 2 blocked: % email_drafts rows have missing or mismatched sent_email_message_id',
      v_draft_sent_mismatches;
  END IF;
END;
$$;

ALTER TABLE public.email_mailbox_copies
  ALTER COLUMN email_message_id SET NOT NULL;

COMMENT ON COLUMN public.email_mailbox_copies.email_message_id IS
  'Required canonical email_messages row for this mailbox/folder/UID copy. Enforced after cutover backfill validation.';
