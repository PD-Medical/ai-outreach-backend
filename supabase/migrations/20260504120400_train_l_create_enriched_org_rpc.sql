-- ============================================================================
-- Train L — create_enriched_org_for_domain RPC
-- ============================================================================
-- Race-safe helper for the lambda enrichment pipeline. Given a domain and a
-- proposed display name, returns the organization_id that owns that domain —
-- creating an `enriched` org and the matching organization_domains alias row
-- if neither exists yet, or adopting the existing winner if a concurrent
-- session already did so.
--
-- WHY:
--   Train I removed inline org creation from upsert_contact_with_org_v2.
--   Train L moves it to async enrichment instead. The lambda needs a single
--   atomic call that handles both the "first time we see this domain" path
--   and the "two enrichment workers raced on the same fresh domain" path
--   without leaking org rows.
--
-- WHO CALLS THIS:
--   ai-outreach-lambda functions/email-sync/enrichment_core.py
--   _get_or_create_org_from_email_content() — invoked when a contact arrives
--   at enrichment with organization_id IS NULL and the domain is NOT in the
--   PERSONAL_MAIL_DOMAINS blocklist.
--
-- BEHAVIOUR:
--   1. If organization_domains already has a row for lower(p_domain),
--      return that row's organization_id immediately. No writes.
--   2. Otherwise INSERT a new row into organizations with source='enriched'.
--      organizations.domain has NO unique constraint on this DB (despite
--      the consolidated_schema declaring one — the dev DB diverged and
--      currently carries 1340+ duplicate-by-lower(domain) rows from the
--      legacy backup). So we cannot ON CONFLICT on organizations and must
--      pivot race-safety on organization_domains instead, which DOES have
--      a UNIQUE INDEX on lower(domain).
--   3. INSERT into organization_domains (org_id, domain). ON CONFLICT
--      DO NOTHING swallows the race when another session won.
--   4. Re-SELECT from organization_domains. The returned organization_id
--      is the canonical owner of this domain; if we lost the race, it
--      points at someone else's org and our step-2 row is orphaned —
--      delete the orphan to keep the table clean.
--
--   The K.2 source guard in lambda's update_organization_from_enrichment
--   continues to protect seeded/manual names. This RPC only writes
--   source='enriched' on org rows it actually creates.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.create_enriched_org_for_domain(
  p_name   text,
  p_domain text
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
BEGIN
  IF p_domain IS NULL OR length(trim(p_domain)) = 0 THEN
    RAISE EXCEPTION 'create_enriched_org_for_domain: p_domain is required';
  END IF;

  v_norm_domain := lower(trim(p_domain));

  -- Step 1: fast path — domain already known via the alias table.
  -- Curated and previously-enriched orgs both surface here.
  SELECT organization_id INTO v_existing_id
  FROM public.organization_domains
  WHERE lower(domain) = v_norm_domain
  LIMIT 1;
  IF v_existing_id IS NOT NULL THEN
    RETURN v_existing_id;
  END IF;

  -- Step 2: domain not seen yet. Build a name (LLM-supplied or
  -- domain-stem fallback). Spec L L2 fallback: initcap(domain stem).
  v_fallback := initcap(split_part(v_norm_domain, '.', 1));

  -- Plain INSERT — no ON CONFLICT possible because organizations has no
  -- UNIQUE constraint on (domain) on this DB (1340+ duplicates from
  -- legacy backup). Race safety pivots on the alias-table insert below.
  INSERT INTO public.organizations (name, domain, status, source, tags, custom_fields)
  VALUES (
    COALESCE(NULLIF(trim(p_name), ''), v_fallback),
    v_norm_domain,
    'active',
    'enriched',
    '[]'::jsonb,
    '{}'::jsonb
  )
  RETURNING id INTO v_new_org_id;

  -- Step 3: claim the alias. organization_domains has UNIQUE INDEX on
  -- lower(domain). ON CONFLICT DO NOTHING swallows the race when another
  -- session got there first.
  INSERT INTO public.organization_domains (organization_id, domain, is_primary, source)
  VALUES (v_new_org_id, v_norm_domain, true, 'auto-derived')
  ON CONFLICT DO NOTHING;

  -- Step 4: re-resolve through the alias table — that's the canonical
  -- domain → org pointer. If step 3 won, returns v_new_org_id. If step 3
  -- lost the race, returns the winning session's org_id and our step-2
  -- row is orphaned.
  SELECT organization_id INTO v_winning_id
  FROM public.organization_domains
  WHERE lower(domain) = v_norm_domain
  LIMIT 1;

  -- Step 5: clean up the orphan if we lost the race. Tight scope:
  -- only delete the row WE just created (matched by id), and only when
  -- it's not the canonical winner. Avoids any chance of touching an
  -- unrelated org that happens to share this domain in the legacy data.
  IF v_winning_id IS DISTINCT FROM v_new_org_id THEN
    DELETE FROM public.organizations WHERE id = v_new_org_id;
  END IF;

  RETURN v_winning_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_enriched_org_for_domain(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_enriched_org_for_domain(text, text)
  TO service_role, authenticated;

COMMENT ON FUNCTION public.create_enriched_org_for_domain(text, text) IS
  'Train L: race-safe lookup-or-create for an org keyed on email domain. '
  'Returns the existing organization_id if the domain is already in '
  'organization_domains; otherwise inserts a new organizations row with '
  'source=enriched and a matching alias row, returning the id. Called '
  'from the lambda enrichment pipeline (_get_or_create_org_from_email_content).';

-- Smoke test: function exists, executable, returns uuid for a fresh domain
DO $smoke$
DECLARE
  v_test_domain text := '__train_l_smoke_test_domain.invalid';
  v_first_id    uuid;
  v_second_id   uuid;
BEGIN
  -- First call creates
  v_first_id := public.create_enriched_org_for_domain('Smoke Test Org', v_test_domain);
  IF v_first_id IS NULL THEN
    RAISE EXCEPTION 'Train L smoke test failed: first call returned NULL';
  END IF;

  -- Second call adopts (idempotent)
  v_second_id := public.create_enriched_org_for_domain('Smoke Test Org Again', v_test_domain);
  IF v_second_id IS DISTINCT FROM v_first_id THEN
    RAISE EXCEPTION 'Train L smoke test failed: second call returned different id (% vs %)',
      v_first_id, v_second_id;
  END IF;

  -- Cleanup
  DELETE FROM public.organization_domains WHERE lower(domain) = v_test_domain;
  DELETE FROM public.organizations WHERE id = v_first_id;
END;
$smoke$;

COMMIT;
