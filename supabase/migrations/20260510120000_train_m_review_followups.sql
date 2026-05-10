-- ============================================================================
-- Train M — review follow-ups
-- ============================================================================
-- Addresses the four Important items raised in PR #100 review:
--
--  1. domain_resolution_attempts had no explicit RLS. Service-role helpers
--     manage writes, but the table itself was relying on default-deny. Make
--     the contract explicit so the table behaves consistently with the rest
--     of the schema and so anyone reading the migration can see the policy.
--
--  2. _classify_contact_type returned 'system' for NULL/empty input while
--     _is_role_address returned true. Net-effect was consistent inside the
--     upsert RPC (both reject), but a future caller using one helper without
--     the other could disagree. Fold _is_role_address into _classify_contact_type
--     so there's a single source of truth and the asymmetry is gone.
--
--  3. The 100100 backfill had a catch-all ELSE branch that silently labelled
--     unknown source values as 'manual'. Audit distinct source values now
--     and warn if anything outside the four expected cases exists; force the
--     migration author to look before silently relabelling. Implementation:
--     RAISE NOTICE on unexpected values rather than fail (this migration runs
--     against an already-migrated database; we just want the visibility).
--
--  4. The 100400 smoke verify-block leaks its temp role_address_pattern row
--     across migration re-runs because cleanup uses an exact-string match
--     that mirrors the test pattern. The verify block in 100400 is already
--     committed; this migration runs an idempotent purge of any rows whose
--     pattern starts with '^m-smoke-' so a redeploy of 100400 can't accumulate
--     test data.
-- ============================================================================

BEGIN;

-- 1. RLS on domain_resolution_attempts
ALTER TABLE public.domain_resolution_attempts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS domain_resolution_attempts_select_policy
  ON public.domain_resolution_attempts;
CREATE POLICY domain_resolution_attempts_select_policy
  ON public.domain_resolution_attempts
  FOR SELECT
  USING (auth.role() = 'service_role');

DROP POLICY IF EXISTS domain_resolution_attempts_modify_policy
  ON public.domain_resolution_attempts;
CREATE POLICY domain_resolution_attempts_modify_policy
  ON public.domain_resolution_attempts
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

GRANT SELECT, INSERT, UPDATE, DELETE ON public.domain_resolution_attempts
  TO service_role;

COMMENT ON TABLE public.domain_resolution_attempts IS
  'Miss cache for the homepage org-name resolver. Service-role-only RLS '
  '(read, insert, update, delete). Lambda enrichment writes via the helper '
  'RPCs which run SECURITY DEFINER and bypass RLS.';

-- 2. Fold _is_role_address into _classify_contact_type — single source of truth.
--    Old function kept for compatibility but now delegates.
CREATE OR REPLACE FUNCTION public._is_role_address(p_email text)
RETURNS boolean
LANGUAGE sql STABLE
AS $$
  SELECT public._classify_contact_type(p_email) = 'system';
$$;

COMMENT ON FUNCTION public._is_role_address(text) IS
  'Train M: thin wrapper over _classify_contact_type so the two helpers '
  'never disagree on edge cases (NULL/empty input, multi-category matches). '
  'Returns true iff classification is system-tier.';

-- 3. Audit unexpected source values. RAISE NOTICE so re-runs surface in logs
--    without breaking the migration.
DO $audit$
DECLARE
  r          record;
  v_unknown  int := 0;
BEGIN
  FOR r IN
    SELECT DISTINCT COALESCE(source, '(null)') AS src
    FROM public.organizations
    WHERE source IS NULL
       OR source NOT IN ('seeded', 'manual', 'auto', 'enriched')
  LOOP
    v_unknown := v_unknown + 1;
    RAISE NOTICE 'Train M audit: unexpected organizations.source value found: %',
      r.src;
  END LOOP;

  IF v_unknown > 0 THEN
    RAISE NOTICE 'Train M audit: % organizations row(s) carry an unexpected '
      'source value. The 20260510100100 backfill mapped these to '
      'name_source=''manual'' as a catch-all. Review and re-stamp manually if '
      'the catch-all isn''t the right provenance.', v_unknown;
  END IF;
END
$audit$;

-- 4. Idempotent purge of any leftover '^m-smoke-' role_address_patterns rows
--    so a redeploy of 100400 can't accumulate test data. The verify block
--    in 100400 inserts and deletes its own row, but if a previous run was
--    interrupted between insert and delete (rare but possible — e.g. a
--    SIGTERM mid-DO block) the row would persist.
DELETE FROM public.role_address_patterns
WHERE pattern LIKE '^m-smoke-%';

COMMIT;

-- Smoke
DO $smoke$
BEGIN
  -- RLS enabled on the new table
  IF NOT EXISTS (
    SELECT 1 FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename = 'domain_resolution_attempts'
      AND rowsecurity = true
  ) THEN
    RAISE EXCEPTION 'Train M followup smoke: RLS not enabled on domain_resolution_attempts';
  END IF;

  -- _is_role_address still rejects noreply
  IF NOT public._is_role_address('noreply@example.com') THEN
    RAISE EXCEPTION 'Train M followup smoke: _is_role_address regression — noreply not rejected';
  END IF;

  -- _is_role_address still passes accounts (role-tier, not system)
  IF public._is_role_address('accounts@example.com') THEN
    RAISE EXCEPTION 'Train M followup smoke: _is_role_address regression — accounts now rejected';
  END IF;

  -- _is_role_address handles NULL consistently with _classify_contact_type
  IF NOT public._is_role_address(NULL) THEN
    RAISE EXCEPTION 'Train M followup smoke: _is_role_address(NULL) returned false (expected true)';
  END IF;
  IF public._classify_contact_type(NULL) <> 'system' THEN
    RAISE EXCEPTION 'Train M followup smoke: _classify_contact_type(NULL) inconsistent with _is_role_address';
  END IF;
END
$smoke$;
