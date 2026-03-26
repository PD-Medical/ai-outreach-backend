-- ============================================================================
-- ADD MISSING FK: email_drafts.contact_id -> contacts.id
-- This FK exists on dev but was missing from prod consolidated schema
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'email_drafts_contact_id_fkey'
      AND table_name = 'email_drafts'
  ) THEN
    ALTER TABLE public.email_drafts
      ADD CONSTRAINT email_drafts_contact_id_fkey
      FOREIGN KEY (contact_id) REFERENCES public.contacts(id);
  END IF;
END $$;
