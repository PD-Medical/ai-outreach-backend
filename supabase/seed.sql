-- ============================================================================
-- Seed Mailboxes for PD Medical
-- ============================================================================

-- Insert mailboxes with pre-generated UUIDs
-- Note: IMAP passwords are stored in environment variables as IMAP_PASSWORD_{uuid_with_underscores}
INSERT INTO public.mailboxes (id, email, name, imap_host, imap_port, is_active, created_at, updated_at)
VALUES
  (
    'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d',
    'peter@pdmedical.com.au',
    'Peter Deliopoulos',
    'cp-wc01.iad01.ds.network',
    993,
    true,
    now(),
    now()
  ),
  (
    'b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e',
    'sales@pdmedical.com.au',
    'Sales Team',
    'cp-wc01.iad01.ds.network',
    993,
    true,
    now(),
    now()
  ),
  (
    'c3d4e5f6-a7b8-4c9d-0e1f-2a3b4c5d6e7f',
    'contact@pdmedical.com.au',
    'Contact Team',
    'cp-wc01.iad01.ds.network',
    993,
    true,
    now(),
    now()
  ),
  (
    'd4e5f6a7-b8c9-4d0e-1f2a-3b4c5d6e7f8a',
    'accounts@pdmedical.com.au',
    'Accounts Team',
    'cp-wc01.iad01.ds.network',
    993,
    true,
    now(),
    now()
  ),
  (
    'e5f6a7b8-c9d0-4e1f-2a3b-4c5d6e7f8a9b',
    'chris@pdmedical.com.au',
    'Chris',
    'cp-wc01.iad01.ds.network',
    993,
    true,
    now(),
    now()
  )
ON CONFLICT (email) DO NOTHING;

-- Verify the inserts
SELECT 
  id,
  email,
  name,
  imap_host,
  imap_port,
  is_active
FROM mailboxes
ORDER BY email;

