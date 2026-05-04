-- ============================================================================
-- Train L — demote personal-mail seed orgs
-- ============================================================================
-- The seed (org_seed.sql) historically inserted Gmail / Hotmail / Yahoo /
-- Outlook / Optusnet / Tpg as customer organisations because they appeared
-- as "domains" in a backup of the legacy CRM. They are not customers — they
-- are inboxes individuals happen to use. Train I null'd contacts off them;
-- Train L removes the empty rows entirely so the orgs UI stops listing them.
--
-- The seed file (supabase/seed/org_seed.sql) and the build script
-- (scripts/build_org_seed.py) have also been updated in this train so that
-- a `db reset` does not reintroduce these rows.
--
-- Defensive ordering:
--   1. Re-point any contacts STILL on a personal-mail org to the Unknown
--      sentinel (Train I cleanup should have null'd these already, but
--      another import path may have written more — belt and braces).
--   2. Delete the personal-mail rows from organization_domains (also by
--      domain match, not just org_id, in case alias rows linger after their
--      parent org row is gone).
--   3. Delete the org rows themselves, scoped tightly: domain match AND
--      source='seeded'. Domain is a stronger discriminator than name and
--      avoids nuking a hypothetical real customer named "Gmail Pty Ltd".
--
-- Per spec Open Q3: hard delete, no JSON dump. Dev/prod org rows for these
-- domains hold no operational metadata worth preserving.
-- ============================================================================

BEGIN;

-- Hardcoded sentinel id — must match
-- 20260504120500_train_l_unknown_sentinel_org.sql and the lambda's
-- functions/shared/personal_mail_domains.py.
WITH
  sentinel AS (
    SELECT 'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid AS id
  ),
  -- Tight match on (domain in personal-mail list, source='seeded') so we
  -- never touch operator-curated rows.
  demote_targets AS (
    SELECT o.id
    FROM public.organizations o
    WHERE o.source = 'seeded'
      AND lower(o.domain) = ANY(ARRAY[
        'gmail.com','googlemail.com',
        'hotmail.com','outlook.com','live.com','msn.com','hotmail.com.au',
        'yahoo.com','yahoo.com.au','ymail.com',
        'icloud.com','me.com','mac.com',
        'aol.com','protonmail.com','proton.me',
        'bigpond.com','bigpond.net.au','bigpond.com.au',
        'optusnet.com.au','iinet.net.au','internode.on.net',
        'tpg.com.au','dodo.com.au','exetel.com.au'
      ])
  ),
  -- Step 1: re-point straggler contacts to the sentinel.
  repointed AS (
    UPDATE public.contacts
       SET organization_id = (SELECT id FROM sentinel),
           updated_at = now()
     WHERE organization_id IN (SELECT id FROM demote_targets)
    RETURNING id
  )
SELECT count(*) AS straggler_contacts_repointed FROM repointed;

-- Step 2: delete organization_domains rows for personal-mail domains, OR
-- rows pointing at the demoted parent orgs (covers any aliases created
-- post-seed by import paths).
DELETE FROM public.organization_domains
WHERE lower(domain) = ANY(ARRAY[
        'gmail.com','googlemail.com',
        'hotmail.com','outlook.com','live.com','msn.com','hotmail.com.au',
        'yahoo.com','yahoo.com.au','ymail.com',
        'icloud.com','me.com','mac.com',
        'aol.com','protonmail.com','proton.me',
        'bigpond.com','bigpond.net.au','bigpond.com.au',
        'optusnet.com.au','iinet.net.au','internode.on.net',
        'tpg.com.au','dodo.com.au','exetel.com.au'
      ])
   OR organization_id IN (
        SELECT o.id FROM public.organizations o
        WHERE o.source = 'seeded'
          AND lower(o.domain) = ANY(ARRAY[
            'gmail.com','googlemail.com',
            'hotmail.com','outlook.com','live.com','msn.com','hotmail.com.au',
            'yahoo.com','yahoo.com.au','ymail.com',
            'icloud.com','me.com','mac.com',
            'aol.com','protonmail.com','proton.me',
            'bigpond.com','bigpond.net.au','bigpond.com.au',
            'optusnet.com.au','iinet.net.au','internode.on.net',
            'tpg.com.au','dodo.com.au','exetel.com.au'
          ])
      );

-- Step 3: delete the org rows themselves. Tight match on (domain, source).
DELETE FROM public.organizations
WHERE source = 'seeded'
  AND lower(domain) = ANY(ARRAY[
    'gmail.com','googlemail.com',
    'hotmail.com','outlook.com','live.com','msn.com','hotmail.com.au',
    'yahoo.com','yahoo.com.au','ymail.com',
    'icloud.com','me.com','mac.com',
    'aol.com','protonmail.com','proton.me',
    'bigpond.com','bigpond.net.au','bigpond.com.au',
    'optusnet.com.au','iinet.net.au','internode.on.net',
    'tpg.com.au','dodo.com.au','exetel.com.au'
  ]);

-- Smoke test: no seeded orgs on personal-mail domains; sentinel still alive;
-- no contacts left pointing at deleted orgs (FK doesn't allow it, but verify
-- our re-point step ran).
DO $smoke$
DECLARE
  v_remaining_orgs int;
  v_sentinel_count int;
  v_orphan_contacts int;
BEGIN
  SELECT count(*) INTO v_remaining_orgs
  FROM public.organizations
  WHERE source = 'seeded'
    AND lower(domain) = ANY(ARRAY[
      'gmail.com','hotmail.com','outlook.com','yahoo.com','yahoo.com.au',
      'optusnet.com.au','tpg.com.au','bigpond.com'
    ]);
  IF v_remaining_orgs > 0 THEN
    RAISE EXCEPTION 'Train L M2 smoke test failed: % personal-mail seeded orgs still present', v_remaining_orgs;
  END IF;

  SELECT count(*) INTO v_sentinel_count
  FROM public.organizations
  WHERE id = 'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid;
  IF v_sentinel_count <> 1 THEN
    RAISE EXCEPTION 'Train L M2 smoke test failed: Unknown sentinel missing after demotion';
  END IF;

  -- Belt-and-braces: confirm no contact references a now-deleted org.
  -- (Should be impossible — Step 1 re-pointed them — but guard anyway.)
  SELECT count(*) INTO v_orphan_contacts
  FROM public.contacts c
  WHERE c.organization_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.organizations o WHERE o.id = c.organization_id);
  IF v_orphan_contacts > 0 THEN
    RAISE EXCEPTION 'Train L M2 smoke test failed: % contacts now reference non-existent orgs', v_orphan_contacts;
  END IF;
END;
$smoke$;

COMMIT;
