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

-- Acquire SHARE ROW EXCLUSIVE on organizations BEFORE the work begins.
-- Why: contacts.organization_id has ON DELETE CASCADE. Without an explicit
-- lock, a concurrent INSERT INTO contacts (organization_id = <demoted-org-id>)
-- could race in between Step 1 (re-point) and Step 3 (delete). The DELETE
-- would then CASCADE-delete the brand-new contact silently — exactly the
-- class of "fix introduces silent data loss" the K.2 train was designed
-- to prevent. SHARE ROW EXCLUSIVE blocks INSERT/UPDATE/DELETE on
-- organizations and the FK-checking inserts on contacts referencing it,
-- without blocking SELECT. Read traffic continues; write traffic queues
-- behind us briefly.
LOCK TABLE public.organizations IN SHARE ROW EXCLUSIVE MODE;

-- Run the three steps inside one DO block so we can capture step-by-step
-- counts via RAISE NOTICE. This gives operators (and prod-deploy log
-- review) visibility into exactly how many rows were touched, instead of
-- a silent migration that succeeds with no audit trail.
DO $demote$
DECLARE
  c_sentinel constant uuid := 'ffffffff-ffff-4fff-8fff-ffffffffffff';
  c_personal_mail_domains constant text[] := ARRAY[
    'gmail.com','googlemail.com',
    'hotmail.com','outlook.com','live.com','msn.com','hotmail.com.au',
    'yahoo.com','yahoo.com.au','ymail.com',
    'icloud.com','me.com','mac.com',
    'aol.com','protonmail.com','proton.me',
    'bigpond.com','bigpond.net.au','bigpond.com.au',
    'optusnet.com.au','iinet.net.au','internode.on.net',
    'tpg.com.au','dodo.com.au','exetel.com.au'
  ];
  v_targeted int;
  v_repointed int;
  v_aliases_deleted int;
  v_orgs_deleted int;
BEGIN
  -- Snapshot the count of contacts on demote_targets BEFORE step 1 so we
  -- can prove the re-point ran (smoke test below). Also captures the
  -- audit-trail figure for prod review.
  SELECT count(*)
    INTO v_targeted
  FROM public.contacts c
  WHERE c.organization_id IN (
    SELECT o.id
    FROM public.organizations o
    WHERE o.source = 'seeded'
      AND lower(o.domain) = ANY(c_personal_mail_domains)
  );

  -- Step 1: re-point straggler contacts to the Unknown sentinel.
  WITH demote_targets AS (
    SELECT o.id
    FROM public.organizations o
    WHERE o.source = 'seeded'
      AND lower(o.domain) = ANY(c_personal_mail_domains)
  ),
  repointed AS (
    UPDATE public.contacts
       SET organization_id = c_sentinel,
           updated_at = now()
     WHERE organization_id IN (SELECT id FROM demote_targets)
    RETURNING id
  )
  SELECT count(*) INTO v_repointed FROM repointed;

  -- Step 2: delete organization_domains rows. Either by domain match (covers
  -- aliases added post-seed) or by org_id (covers seeded aliases).
  WITH alias_deletes AS (
    DELETE FROM public.organization_domains
    WHERE lower(domain) = ANY(c_personal_mail_domains)
       OR organization_id IN (
            SELECT o.id FROM public.organizations o
            WHERE o.source = 'seeded'
              AND lower(o.domain) = ANY(c_personal_mail_domains)
          )
    RETURNING organization_id
  )
  SELECT count(*) INTO v_aliases_deleted FROM alias_deletes;

  -- Step 3: delete the org rows themselves. Tight match on (domain, source).
  WITH org_deletes AS (
    DELETE FROM public.organizations
    WHERE source = 'seeded'
      AND lower(domain) = ANY(c_personal_mail_domains)
    RETURNING id
  )
  SELECT count(*) INTO v_orgs_deleted FROM org_deletes;

  -- Audit trail: surface the counts. RAISE NOTICE shows up in supabase
  -- migration output and in the supabase CLI's stdout, so operators can
  -- review the destructive scope after running.
  RAISE NOTICE 'Train L M2: targeted=% straggler contacts; repointed=%; aliases_deleted=%; orgs_deleted=%',
    v_targeted, v_repointed, v_aliases_deleted, v_orgs_deleted;

  -- Smoke check inside the same DO block: every targeted contact should
  -- have been repointed (CASCADE can't have eaten any because we held
  -- SHARE ROW EXCLUSIVE; if v_targeted != v_repointed, something is off).
  IF v_targeted <> v_repointed THEN
    RAISE EXCEPTION
      'Train L M2 invariant failure: targeted=% but repointed=% (CASCADE silently consumed rows?)',
      v_targeted, v_repointed;
  END IF;
END;
$demote$;

-- Smoke test: no seeded orgs on personal-mail domains; sentinel still alive;
-- no contacts left pointing at deleted orgs.
DO $smoke$
DECLARE
  v_remaining_orgs int;
  v_sentinel_count int;
  v_orphan_contacts int;
  c_personal_mail_domains constant text[] := ARRAY[
    'gmail.com','googlemail.com',
    'hotmail.com','outlook.com','live.com','msn.com','hotmail.com.au',
    'yahoo.com','yahoo.com.au','ymail.com',
    'icloud.com','me.com','mac.com',
    'aol.com','protonmail.com','proton.me',
    'bigpond.com','bigpond.net.au','bigpond.com.au',
    'optusnet.com.au','iinet.net.au','internode.on.net',
    'tpg.com.au','dodo.com.au','exetel.com.au'
  ];
BEGIN
  SELECT count(*) INTO v_remaining_orgs
  FROM public.organizations
  WHERE source = 'seeded'
    AND lower(domain) = ANY(c_personal_mail_domains);
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
