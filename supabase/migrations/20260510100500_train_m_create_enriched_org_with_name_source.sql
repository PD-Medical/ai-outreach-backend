-- ============================================================================
-- Train M — create_enriched_org_for_domain accepts name_source + pending flag
-- ============================================================================
-- The Train L RPC stamped every newly-created org with source='enriched' and
-- left name_source unset (the K.2-era code only knew about source). Now that
-- the resolver can produce names via three different paths (LLM signature →
-- homepage scrape → domain-stem fallback), the RPC needs to accept which
-- source produced the name and whether the row should land in the operator
-- review queue.
--
-- New parameters (both default to keep backward compatibility — old callers
-- still work the same way):
--   p_name_source         — 'enriched_ai' | 'homepage' | 'domain_stem'
--                           (defaults to 'enriched_ai' to match Train L)
--   p_pending_review      — boolean. true when the resolver fell through to
--                           the domain-stem fallback (no real signal).
--
-- The race-safety pivot from Train L (alias-table UNIQUE INDEX, not
-- organizations.domain) is preserved verbatim.
-- ============================================================================

BEGIN;

-- Train L installed a 2-arg overload (text, text). Adding the 4-arg
-- overload below would coexist alongside it because CREATE OR REPLACE
-- only matches an identical signature. Two callable signatures with
-- compatible types make any 2-arg call ambiguous ("could not choose a
-- best candidate function"). Drop the old overload explicitly so there's
-- exactly one create_enriched_org_for_domain function — the new 4-arg
-- one with defaults that handles old 2-arg call sites cleanly.
DROP FUNCTION IF EXISTS public.create_enriched_org_for_domain(text, text);

CREATE OR REPLACE FUNCTION public.create_enriched_org_for_domain(
  p_name              text,
  p_domain            text,
  p_name_source       text    DEFAULT 'enriched_ai',
  p_pending_review    boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_norm_domain  text;
  v_existing_id  uuid;
  v_new_org_id   uuid;
  v_winning_id   uuid;
  v_fallback     text;
  v_name_source  text;
BEGIN
  IF p_domain IS NULL OR length(trim(p_domain)) = 0 THEN
    RAISE EXCEPTION 'create_enriched_org_for_domain: p_domain is required';
  END IF;

  v_norm_domain := lower(trim(p_domain));

  -- Validate name_source — fall back to enriched_ai if the caller passed
  -- something the CHECK constraint won't accept.
  v_name_source := COALESCE(NULLIF(trim(p_name_source), ''), 'enriched_ai');
  IF v_name_source NOT IN ('enriched_ai', 'homepage', 'domain_stem') THEN
    v_name_source := 'enriched_ai';
  END IF;

  -- Step 1: fast path — domain already known via the alias table.
  -- Curated and previously-enriched orgs both surface here.
  SELECT organization_id INTO v_existing_id
  FROM public.organization_domains
  WHERE lower(domain) = v_norm_domain
  LIMIT 1;
  IF v_existing_id IS NOT NULL THEN
    RETURN v_existing_id;
  END IF;

  -- Step 2: domain not seen yet. Build a name (caller-supplied or
  -- domain-stem fallback). Spec L L2 fallback: initcap(domain stem).
  v_fallback := initcap(split_part(v_norm_domain, '.', 1));

  INSERT INTO public.organizations (
    name, domain, status, source, name_source, name_pending_review, tags, custom_fields
  )
  VALUES (
    COALESCE(NULLIF(trim(p_name), ''), v_fallback),
    v_norm_domain,
    'active',
    'enriched',                         -- row creation source (Train K.2)
    v_name_source,                      -- name provenance (Train M)
    p_pending_review,                   -- queue flag (Train M)
    '[]'::jsonb,
    jsonb_build_object('train', 'M')
  )
  RETURNING id INTO v_new_org_id;

  -- Step 3: alias-table insert pivots the race. Two concurrent workers for
  -- the same fresh domain both land here; ON CONFLICT swallows the loser's.
  -- Bare ON CONFLICT (no column spec) lets Postgres match the existing
  -- expression-based UNIQUE INDEX on lower(domain) — using `(domain)`
  -- would fail with "no unique or exclusion constraint matching" because
  -- the index is on the lowered expression, not the bare column.
  INSERT INTO public.organization_domains (organization_id, domain, is_primary, source)
  VALUES (v_new_org_id, v_norm_domain, true, 'auto-derived')
  ON CONFLICT DO NOTHING;

  -- Step 4: re-read the alias table. If we won, this returns our new org id.
  -- If we lost, it returns the winning org id and we orphan our row.
  SELECT organization_id INTO v_winning_id
  FROM public.organization_domains
  WHERE lower(domain) = v_norm_domain
  LIMIT 1;

  IF v_winning_id IS DISTINCT FROM v_new_org_id THEN
    -- We lost the race; clean up our orphan row to keep the table tidy.
    DELETE FROM public.organizations WHERE id = v_new_org_id;
  END IF;

  RETURN v_winning_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_enriched_org_for_domain(text, text, text, boolean)
  TO service_role, authenticated;

COMMENT ON FUNCTION public.create_enriched_org_for_domain(text, text, text, boolean) IS
  'Train M: race-safe org+alias create. Stamps name_source (enriched_ai | '
  'homepage | domain_stem) and name_pending_review based on resolver outcome. '
  'Old 2-arg call sites still work via parameter defaults.';

COMMIT;

-- Smoke test
DO $smoke$
DECLARE
  v_test_domain text := 'train-m-smoke-' || extract(epoch from now())::bigint || '.example';
  v_org_id      uuid;
  v_stored_ns   text;
  v_stored_pr   boolean;
BEGIN
  -- Call with new params
  v_org_id := public.create_enriched_org_for_domain(
    p_name           := 'Train M Smoke Co',
    p_domain         := v_test_domain,
    p_name_source    := 'homepage',
    p_pending_review := false
  );

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Train M smoke: create_enriched_org_for_domain returned NULL';
  END IF;

  SELECT name_source, name_pending_review INTO v_stored_ns, v_stored_pr
  FROM public.organizations WHERE id = v_org_id;

  IF v_stored_ns <> 'homepage' THEN
    RAISE EXCEPTION 'Train M smoke: name_source stored as % (expected homepage)', v_stored_ns;
  END IF;
  IF v_stored_pr THEN
    RAISE EXCEPTION 'Train M smoke: name_pending_review stored as true (expected false)';
  END IF;

  -- Old 2-arg call still works
  v_org_id := public.create_enriched_org_for_domain('Train M Smoke 2', v_test_domain || '.b');
  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Train M smoke: backward-compat 2-arg call returned NULL';
  END IF;

  -- Cleanup
  DELETE FROM public.organization_domains WHERE domain LIKE 'train-m-smoke-%';
  DELETE FROM public.organizations WHERE domain LIKE 'train-m-smoke-%';
END
$smoke$;
