-- ============================================================================
-- Train M — contacts.contact_type
-- ============================================================================
-- Distinguishes a real human (person) from shared-mailbox addresses we now
-- want to keep as contacts (info@, accounts@, support@) so reply context and
-- thread history don't get dropped.
--
-- Values:
--   person  — default; real human contact (signature, name fields all apply)
--   role    — a job-function shared inbox (accounts@, sales@, enquiries@).
--             First-name carries the role label; last_name stays NULL.
--   shared  — broader shared inbox (info@, contact@, hello@). UI hides
--             person-only fields (last_name, role, department).
--   system  — automated (noreply, mailer-daemon, postmaster). Already rejected
--             at intake by _is_role_address; column reserved for future use
--             in case operator manually creates one.
--
-- Why a column rather than computing on demand: campaigns, hot-leads scoring,
-- and AI drafting all need to filter on this. Single column join is cheap;
-- per-query regex match against role_address_patterns isn't.
--
-- Default 'person' so existing rows are correctly typed for human contacts;
-- the 20260510100200 migration backfills role/shared rows that already exist.
-- ============================================================================

ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS contact_type text NOT NULL DEFAULT 'person';

ALTER TABLE public.contacts
  DROP CONSTRAINT IF EXISTS contacts_contact_type_check;

ALTER TABLE public.contacts
  ADD CONSTRAINT contacts_contact_type_check
  CHECK (contact_type IN ('person', 'role', 'shared', 'system'));

CREATE INDEX IF NOT EXISTS idx_contacts_contact_type
  ON public.contacts(contact_type)
  WHERE contact_type <> 'person';

COMMENT ON COLUMN public.contacts.contact_type IS
  'How to treat this contact in the UI and downstream features. '
  'person (default) | role (job-function shared inbox like accounts@) | '
  'shared (broad shared inbox like info@) | system (noreply, automated). '
  'Set at intake by lambda from role_address_patterns.category.';

-- Smoke test: column + constraint + values are all valid
DO $smoke$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'contacts'
      AND column_name = 'contact_type'
      AND is_nullable = 'NO'
      AND column_default LIKE '%person%'
  ) THEN
    RAISE EXCEPTION 'Train M smoke: contacts.contact_type missing, nullable, or wrong default';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'contacts_contact_type_check'
      AND conrelid = 'public.contacts'::regclass
  ) THEN
    RAISE EXCEPTION 'Train M smoke: contacts_contact_type_check constraint missing';
  END IF;
END
$smoke$;
