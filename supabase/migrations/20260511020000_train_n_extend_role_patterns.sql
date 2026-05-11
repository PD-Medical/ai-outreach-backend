-- ============================================================================
-- Train N — extend role_address_patterns with exec / job-title inboxes
-- ============================================================================
-- Train M validation showed that vice-president@ slipped through as
-- contact_type='person', so the role guards never fired and the AI
-- happily extracted a real person's name (Donald) plus a domain
-- fragment ("Nsw" from smbensw) and stored both. Same shape for any
-- exec / job-title inbox we hadn't pre-listed.
--
-- This migration adds the common omissions. All inserted as category='role'
-- (job-function inboxes) rather than 'shared' (broad inboxes).
--
-- Notes:
--  - Patterns are regex matched against {local}@ (with trailing @) per the
--    existing _classify_contact_type / _is_role_address contract.
--  - 'manager' and 'director' are intentionally NOT added without a
--    qualifier — `gm` and `director@x.com` could be a real person whose
--    first name is "Gm". Stuck to the unambiguous cases.
-- ============================================================================

INSERT INTO public.role_address_patterns (pattern, description, category) VALUES
  -- Executive inboxes
  ('^vice-president@', 'Vice President (hyphenated)',   'role'),
  ('^vicepresident@',  'Vice President (no separator)', 'role'),
  ('^vp@',             'VP initialism',                 'role'),
  ('^ceo@',            'CEO',                           'role'),
  ('^cfo@',            'CFO',                           'role'),
  ('^coo@',            'COO',                           'role'),
  ('^cto@',            'CTO',                           'role'),
  ('^cio@',            'CIO',                           'role'),
  ('^managing-director@', 'Managing Director',          'role'),
  ('^managingdirector@',  'Managing Director (no separator)', 'role'),
  ('^md@',             'Managing Director initialism (or MD job title)', 'role'),

  -- General office / admin
  ('^president@',      'President',                     'role'),
  ('^secretary@',      'Secretary',                     'role'),
  ('^principal@',      'Principal',                     'role'),
  ('^owner@',          'Owner',                         'role'),
  ('^founder@',        'Founder',                       'role'),

  -- Payroll / Finance
  ('^payroll@',        'Payroll team',                  'role'),
  ('^finance@',        'Finance team',                  'role'),
  ('^treasurer@',      'Treasurer',                     'role'),

  -- Other shared inboxes
  ('^customerservice@', 'Customer service (no separator)', 'shared'),
  ('^customer-service@', 'Customer service (hyphenated)', 'shared'),
  ('^feedback@',       'Feedback inbox',                'shared'),
  ('^press@',          'Press / media inbox',           'shared'),
  ('^media@',          'Media inbox',                   'shared')
ON CONFLICT (pattern) DO UPDATE
  SET description = EXCLUDED.description,
      category    = EXCLUDED.category;

-- Smoke: classify a few of the new patterns
DO $smoke$
BEGIN
  IF public._classify_contact_type('vice-president@example.com') <> 'role' THEN
    RAISE EXCEPTION 'Train N smoke: vice-president@ not classified as role';
  END IF;
  IF public._classify_contact_type('ceo@example.com') <> 'role' THEN
    RAISE EXCEPTION 'Train N smoke: ceo@ not classified as role';
  END IF;
  IF public._classify_contact_type('customer-service@example.com') <> 'shared' THEN
    RAISE EXCEPTION 'Train N smoke: customer-service@ not classified as shared';
  END IF;
  -- Person inboxes still classify correctly
  IF public._classify_contact_type('john@example.com') <> 'person' THEN
    RAISE EXCEPTION 'Train N smoke: john@ misclassified (regression)';
  END IF;
END
$smoke$;
