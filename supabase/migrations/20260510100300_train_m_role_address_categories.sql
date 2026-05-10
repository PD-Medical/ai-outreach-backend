-- ============================================================================
-- Train M — role_address_patterns categories + new role/shared patterns
-- ============================================================================
-- The current table treats every pattern as a hard reject — info@, accounts@,
-- noreply@ all cause the upsert RPC to skip contact creation. That's overkill
-- for the role/shared cases: real conversations happen via accounts@ inboxes
-- and we lose thread context by rejecting them.
--
-- Train M splits patterns into three categories:
--   system  — automated senders, hard-reject (noreply, mailer-daemon,
--             postmaster, abuse, bounces). Pre-existing behaviour.
--   role    — job-function shared inbox (accounts, sales, support, enquiries).
--             Stored as a contact with contact_type='role', name in first_name.
--   shared  — broad shared inbox (info, contact, hello, admin). Stored as
--             contact_type='shared'.
--
-- Existing patterns are all system-tier; back-fill them as such, then add the
-- new role/shared patterns.
--
-- The RPC change that uses this category lives in the next migration.
-- ============================================================================

BEGIN;

-- 1. Add category column
ALTER TABLE public.role_address_patterns
  ADD COLUMN IF NOT EXISTS category text;

-- Backfill: every existing pattern is a system-tier hard reject.
UPDATE public.role_address_patterns
SET category = 'system'
WHERE category IS NULL;

ALTER TABLE public.role_address_patterns
  ALTER COLUMN category SET NOT NULL;

ALTER TABLE public.role_address_patterns
  ALTER COLUMN category SET DEFAULT 'system';

ALTER TABLE public.role_address_patterns
  DROP CONSTRAINT IF EXISTS role_address_patterns_category_check;

ALTER TABLE public.role_address_patterns
  ADD CONSTRAINT role_address_patterns_category_check
  CHECK (category IN ('system', 'role', 'shared'));

CREATE INDEX IF NOT EXISTS idx_role_address_patterns_category
  ON public.role_address_patterns(category)
  WHERE is_active;

COMMENT ON COLUMN public.role_address_patterns.category IS
  'system: hard-reject at intake (no contact created). '
  'role: job-function inbox, store as contact with contact_type=role. '
  'shared: broad shared inbox, store as contact with contact_type=shared.';

-- 2. Insert role/shared patterns
INSERT INTO public.role_address_patterns (pattern, description, category) VALUES
  -- role: job-function specific
  ('^accounts@',         'Accounts / accounts payable / accounts receivable team', 'role'),
  ('^accountspayable@',  'Accounts payable team',                                   'role'),
  ('^accounts-payable@', 'Accounts payable team (hyphenated)',                      'role'),
  ('^accountsreceivable@','Accounts receivable team',                               'role'),
  ('^ap@',               'Accounts payable (initialism)',                           'role'),
  ('^ar@',               'Accounts receivable (initialism)',                        'role'),
  ('^billing@',          'Billing team',                                            'role'),
  ('^invoice@',          'Invoice handling',                                        'role'),
  ('^invoices@',         'Invoice handling (plural)',                               'role'),
  ('^sales@',            'Sales team',                                              'role'),
  ('^support@',          'Customer support team',                                   'role'),
  ('^helpdesk@',         'Help-desk team',                                          'role'),
  ('^help-desk@',        'Help-desk team (hyphenated)',                             'role'),
  ('^enquiries@',        'General enquiries',                                       'role'),
  ('^enquiry@',          'General enquiry',                                         'role'),
  ('^inquiries@',        'General inquiries (US spelling)',                         'role'),
  ('^purchasing@',       'Purchasing team',                                         'role'),
  ('^procurement@',      'Procurement team',                                        'role'),
  ('^orders@',           'Orders team',                                             'role'),
  ('^hr@',               'HR team',                                                 'role'),
  ('^careers@',          'Careers/recruiting',                                      'role'),
  ('^jobs@',             'Jobs/recruiting',                                         'role'),
  ('^marketing@',        'Marketing team',                                          'role'),
  ('^reception@',        'Reception desk',                                          'role'),
  ('^reservations@',     'Reservations / bookings',                                 'role'),
  ('^bookings@',         'Bookings team',                                           'role'),
  ('^office@',           'General office inbox',                                    'role'),

  -- shared: broad/general
  ('^info@',             'General info inbox',                                      'shared'),
  ('^contact@',          'General contact inbox',                                   'shared'),
  ('^hello@',            'Friendly general inbox',                                  'shared'),
  ('^team@',             'Team inbox',                                              'shared'),
  ('^admin@',            'Admin team',                                              'shared'),
  ('^office_admin@',     'Office admin team',                                       'shared'),
  ('^mail@',             'General mail inbox',                                      'shared'),
  ('^enquire@',          'General enquire (less common spelling)',                  'shared')
ON CONFLICT (pattern) DO UPDATE
  SET description = EXCLUDED.description,
      category    = EXCLUDED.category;

COMMIT;

-- Smoke test: verify category column populated, new patterns inserted
DO $smoke$
DECLARE
  v_no_cat   int;
  v_role_n   int;
  v_shared_n int;
  v_system_n int;
BEGIN
  SELECT count(*) INTO v_no_cat FROM public.role_address_patterns WHERE category IS NULL;
  IF v_no_cat > 0 THEN
    RAISE EXCEPTION 'Train M smoke: % role_address_patterns rows have NULL category', v_no_cat;
  END IF;

  SELECT count(*) INTO v_role_n   FROM public.role_address_patterns WHERE category = 'role';
  SELECT count(*) INTO v_shared_n FROM public.role_address_patterns WHERE category = 'shared';
  SELECT count(*) INTO v_system_n FROM public.role_address_patterns WHERE category = 'system';

  IF v_role_n   < 10 THEN RAISE EXCEPTION 'Train M smoke: only % role patterns (expected ≥10)', v_role_n; END IF;
  IF v_shared_n < 5  THEN RAISE EXCEPTION 'Train M smoke: only % shared patterns (expected ≥5)', v_shared_n; END IF;
  IF v_system_n < 10 THEN RAISE EXCEPTION 'Train M smoke: only % system patterns (expected ≥10)', v_system_n; END IF;
END
$smoke$;
