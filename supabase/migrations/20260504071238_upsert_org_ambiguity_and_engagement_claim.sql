-- ============================================================================
-- Train K.1: Fix organization_id ambiguity in upsert_contact_with_org_v2
--            + add jsonb overload of _field_trust_should_overwrite
--            + add claim_contact_for_engagement RPC
--
-- WHY:
--
-- (1) ORGANIZATION_ID AMBIGUITY (#16) — runtime-blocking
--     Local profiling on 2026-05-04 surfaced this when running enrichment
--     against existing contacts:
--       call_upsert_rpc HTTP 400 code=42702
--         message=column reference "organization_id" is ambiguous
--         details=It could refer to either a PL/pgSQL variable or a table
--                column.
--     The function declares `organization_id` as an OUT parameter (RETURNS
--     TABLE(...organization_id uuid...)) and also references the contacts
--     table column `organization_id` inside its UPDATE clause. PL/pgSQL
--     refuses to compile when the bare identifier could mean either.
--     This was originally fixed in Train H (20260502140000) for the varchar
--     overload, but Train I (20260503055937) recreated the function with
--     text params and lost the fix; Train K (20260504040736) propagated the
--     regression. The new-contact INSERT branch is unaffected (which is why
--     bulk import succeeded for first-touch contacts), but every existing-
--     contact trust-merge call (signature-AI extraction, repeated emails
--     from the same sender) hits the error.
--     Fix: qualify each ambiguous reference as `contacts.organization_id`
--     inside the UPDATE clause's CASE expression.
--
-- (2) _FIELD_TRUST_SHOULD_OVERWRITE JSONB OVERLOAD — promote dev hot-fix
--     The Train I/K body calls _field_trust_should_overwrite with
--     (jsonb, text, text, numeric) but the canonical signature was
--     (text, numeric, text, numeric). Hot-fixed dev with a wrapper that
--     extracts the source/confidence from the jsonb arg and delegates to
--     the canonical version. This migration redefines the wrapper as a
--     CREATE OR REPLACE so the source-of-truth migration history is correct.
--
-- (3) CLAIM_CONTACT_FOR_ENGAGEMENT — race-free engagement summary
--     Mirrors the conversation-summary claim pattern from Train C.1.1.
--     Without it, two concurrent SQS workers for the same contact_id can
--     both run the LLM call. Bounded by the 30s coalescing window today,
--     but a real claim is cheaper and clearer.
--
-- WHAT THIS MIGRATION DOES (single transaction):
--   1. CREATE OR REPLACE _field_trust_should_overwrite(jsonb, text, text, numeric)
--   2. CREATE OR REPLACE upsert_contact_with_org_v2(text, ...) with
--      organization_id qualified in the existing-contact UPDATE branch.
--   3. CREATE OR REPLACE claim_contact_for_engagement(uuid, integer)
--   4. Smoke tests.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. _field_trust_should_overwrite — jsonb overload (promote hot-fix)
-- ----------------------------------------------------------------------------
-- Delegates to the canonical (text, numeric, text, numeric) version after
-- extracting source/confidence from the field_sources jsonb. Both overloads
-- coexist; PostgreSQL picks based on caller arg types.

CREATE OR REPLACE FUNCTION public._field_trust_should_overwrite(
  p_field_sources  jsonb,
  p_field_name     text,
  p_new_source     text,
  p_new_confidence numeric
) RETURNS boolean
LANGUAGE sql IMMUTABLE
AS $$
  SELECT public._field_trust_should_overwrite(
    p_field_sources -> p_field_name ->> 'source',
    NULLIF(p_field_sources -> p_field_name ->> 'confidence', '')::numeric,
    p_new_source,
    p_new_confidence
  )
$$;


-- ----------------------------------------------------------------------------
-- 2. upsert_contact_with_org_v2 — fix organization_id ambiguity
-- ----------------------------------------------------------------------------
-- Body is byte-identical to Train K (20260504040736) except for the four
-- references to `organization_id` in the existing-contact UPDATE branch
-- (around lines 233-240 of the prior version), which are now qualified as
-- `contacts.organization_id` to disambiguate from the OUT parameter.

CREATE OR REPLACE FUNCTION public.upsert_contact_with_org_v2(
  p_email             text,
  p_first_name        text DEFAULT NULL,
  p_last_name         text DEFAULT NULL,
  p_job_title         text DEFAULT NULL,
  p_role              text DEFAULT NULL,
  p_phone             text DEFAULT NULL,
  p_department        text DEFAULT NULL,
  p_facility_hint     text DEFAULT NULL,
  p_signature_org_name text DEFAULT NULL,
  p_source            text DEFAULT 'unknown',
  p_source_confidence numeric DEFAULT 0.5
)
RETURNS TABLE (
  contact_id      uuid,
  organization_id uuid,
  is_new_contact  boolean,
  is_role_address boolean,
  fields_set      text[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_email_norm   text;
  v_email_domain text;
  v_org_id       uuid;
  v_existing     public.contacts%ROWTYPE;
  v_now          timestamptz := now();
  v_field_sources jsonb;
  v_fields       text[] := ARRAY[]::text[];
BEGIN
  -- 1. Reject empty / malformed email
  IF p_email IS NULL OR position('@' in p_email) = 0 THEN
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, false, false, ARRAY[]::text[];
    RETURN;
  END IF;

  -- 1b. Reject role addresses (purchase@, info@, accounts@, etc.)
  IF public._is_role_address(p_email) THEN
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, false, true, ARRAY[]::text[];
    RETURN;
  END IF;

  -- 2. Normalise
  v_email_norm   := public._normalise_email_for_dedup(p_email);
  v_email_domain := lower(split_part(p_email, '@', 2));

  -- 3. Resolve organization (with subdomain walk).
  v_org_id := public._resolve_org_by_domain(v_email_domain);

  -- 4. If org has children, narrow to facility based on hint
  IF v_org_id IS NOT NULL AND p_facility_hint IS NOT NULL THEN
    v_org_id := public._narrow_to_facility(v_org_id, p_facility_hint);
  END IF;

  -- 5. (Removed in Train I) Previously auto-created a placeholder org;
  --    contacts now get organization_id = NULL when domain unknown.

  -- 6. Lock-and-upsert contact. Match on normalised email.
  SELECT * INTO v_existing
  FROM public.contacts
  WHERE public._normalise_email_for_dedup(email) = v_email_norm
  FOR UPDATE
  LIMIT 1;

  IF v_existing.id IS NULL THEN
    -- New contact
    v_field_sources := '{}'::jsonb;

    IF p_first_name IS NOT NULL THEN
      v_field_sources := v_field_sources || jsonb_build_object('first_name',
        jsonb_build_object('source', p_source, 'confidence', p_source_confidence, 'set_at', v_now));
      v_fields := array_append(v_fields, 'first_name');
    END IF;
    IF p_last_name IS NOT NULL THEN
      v_field_sources := v_field_sources || jsonb_build_object('last_name',
        jsonb_build_object('source', p_source, 'confidence', p_source_confidence, 'set_at', v_now));
      v_fields := array_append(v_fields, 'last_name');
    END IF;
    IF p_job_title IS NOT NULL THEN
      v_field_sources := v_field_sources || jsonb_build_object('job_title',
        jsonb_build_object('source', p_source, 'confidence', p_source_confidence, 'set_at', v_now));
      v_fields := array_append(v_fields, 'job_title');
    END IF;
    IF p_role IS NOT NULL THEN
      v_field_sources := v_field_sources || jsonb_build_object('role',
        jsonb_build_object('source', p_source, 'confidence', p_source_confidence, 'set_at', v_now));
      v_fields := array_append(v_fields, 'role');
    END IF;
    IF p_phone IS NOT NULL THEN
      v_field_sources := v_field_sources || jsonb_build_object('phone',
        jsonb_build_object('source', p_source, 'confidence', p_source_confidence, 'set_at', v_now));
      v_fields := array_append(v_fields, 'phone');
    END IF;
    IF p_department IS NOT NULL THEN
      v_field_sources := v_field_sources || jsonb_build_object('department',
        jsonb_build_object('source', p_source, 'confidence', p_source_confidence, 'set_at', v_now));
      v_fields := array_append(v_fields, 'department');
    END IF;

    INSERT INTO public.contacts (
      email, first_name, last_name, job_title, role, phone, department,
      organization_id, status, field_sources, created_at, updated_at
    )
    VALUES (
      p_email, p_first_name, p_last_name, p_job_title, p_role, p_phone, p_department,
      v_org_id, 'active', v_field_sources, v_now, v_now
    )
    RETURNING id INTO contact_id;

    organization_id := v_org_id;
    is_new_contact := true;
    is_role_address := false;
  ELSE
    -- Existing contact — apply trust-merge
    contact_id      := v_existing.id;
    is_new_contact  := false;
    is_role_address := false;

    PERFORM public._field_trust_should_overwrite(
      v_existing.field_sources, 'first_name', p_source, p_source_confidence
    );
    UPDATE public.contacts SET
      first_name = CASE WHEN public._field_trust_should_overwrite(
        field_sources, 'first_name', p_source, p_source_confidence
      ) AND p_first_name IS NOT NULL THEN p_first_name ELSE first_name END,
      last_name = CASE WHEN public._field_trust_should_overwrite(
        field_sources, 'last_name', p_source, p_source_confidence
      ) AND p_last_name IS NOT NULL THEN p_last_name ELSE last_name END,
      job_title = CASE WHEN public._field_trust_should_overwrite(
        field_sources, 'job_title', p_source, p_source_confidence
      ) AND p_job_title IS NOT NULL THEN p_job_title ELSE job_title END,
      role = CASE WHEN public._field_trust_should_overwrite(
        field_sources, 'role', p_source, p_source_confidence
      ) AND p_role IS NOT NULL THEN p_role ELSE role END,
      phone = CASE WHEN public._field_trust_should_overwrite(
        field_sources, 'phone', p_source, p_source_confidence
      ) AND p_phone IS NOT NULL THEN p_phone ELSE phone END,
      department = CASE WHEN public._field_trust_should_overwrite(
        field_sources, 'department', p_source, p_source_confidence
      ) AND p_department IS NOT NULL THEN p_department ELSE department END,
      field_sources = (
        SELECT COALESCE(field_sources, '{}'::jsonb)
          || CASE WHEN public._field_trust_should_overwrite(
                field_sources, 'first_name', p_source, p_source_confidence
              ) AND p_first_name IS NOT NULL THEN jsonb_build_object('first_name',
                jsonb_build_object('source', p_source, 'confidence', p_source_confidence, 'set_at', v_now)) ELSE '{}'::jsonb END
          || CASE WHEN public._field_trust_should_overwrite(
                field_sources, 'last_name', p_source, p_source_confidence
              ) AND p_last_name IS NOT NULL THEN jsonb_build_object('last_name',
                jsonb_build_object('source', p_source, 'confidence', p_source_confidence, 'set_at', v_now)) ELSE '{}'::jsonb END
          || CASE WHEN public._field_trust_should_overwrite(
                field_sources, 'job_title', p_source, p_source_confidence
              ) AND p_job_title IS NOT NULL THEN jsonb_build_object('job_title',
                jsonb_build_object('source', p_source, 'confidence', p_source_confidence, 'set_at', v_now)) ELSE '{}'::jsonb END
          || CASE WHEN public._field_trust_should_overwrite(
                field_sources, 'role', p_source, p_source_confidence
              ) AND p_role IS NOT NULL THEN jsonb_build_object('role',
                jsonb_build_object('source', p_source, 'confidence', p_source_confidence, 'set_at', v_now)) ELSE '{}'::jsonb END
          || CASE WHEN public._field_trust_should_overwrite(
                field_sources, 'phone', p_source, p_source_confidence
              ) AND p_phone IS NOT NULL THEN jsonb_build_object('phone',
                jsonb_build_object('source', p_source, 'confidence', p_source_confidence, 'set_at', v_now)) ELSE '{}'::jsonb END
          || CASE WHEN public._field_trust_should_overwrite(
                field_sources, 'department', p_source, p_source_confidence
              ) AND p_department IS NOT NULL THEN jsonb_build_object('department',
                jsonb_build_object('source', p_source, 'confidence', p_source_confidence, 'set_at', v_now)) ELSE '{}'::jsonb END
        FROM public.contacts WHERE id = v_existing.id
      ),
      -- Backfill organization_id only if currently NULL or pointed at an
      -- auto-created placeholder. Don't relink curated assignments.
      -- TRAIN K.1 FIX (#16): qualify ambiguous references as
      -- `contacts.organization_id` to avoid 42702 against the OUT param.
      organization_id = CASE
        WHEN contacts.organization_id IS NULL AND v_org_id IS NOT NULL THEN v_org_id
        WHEN v_org_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM public.organizations o
          WHERE o.id = contacts.organization_id
            AND COALESCE(o.custom_fields->>'auto_created_from_intake','false')::boolean
        ) THEN v_org_id
        ELSE contacts.organization_id
      END,
      updated_at = v_now
    WHERE id = v_existing.id;

    organization_id := COALESCE(
      (SELECT c.organization_id FROM public.contacts c WHERE c.id = v_existing.id),
      v_org_id
    );
  END IF;

  fields_set := v_fields;
  RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_contact_with_org_v2(text,text,text,text,text,text,text,text,text,text,numeric)
  TO service_role, authenticated;

COMMENT ON FUNCTION public.upsert_contact_with_org_v2(text,text,text,text,text,text,text,text,text,text,numeric) IS
  'Train K.1: fixed organization_id ambiguity (#16) — qualified as '
  'contacts.organization_id in existing-contact UPDATE branch. Train H '
  '(20260502140000) had this fix; Train I/K regressed it.';


-- ----------------------------------------------------------------------------
-- 3. claim_contact_for_engagement — race-free claim for engagement summary
-- ----------------------------------------------------------------------------
-- Mirrors claim_conversation_for_summary. Atomically advances
-- engagement_conv_count_at_last_summary so concurrent SQS workers
-- handling the same contact see the marker and bail.

CREATE OR REPLACE FUNCTION public.claim_contact_for_engagement(
  p_contact_id uuid,
  p_conv_count integer
)
RETURNS TABLE(claimed boolean, prior_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prior integer;
BEGIN
  SELECT COALESCE(engagement_conv_count_at_last_summary, 0)
  INTO v_prior
  FROM public.contacts
  WHERE id = p_contact_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 0;
    RETURN;
  END IF;

  IF v_prior >= p_conv_count THEN
    RETURN QUERY SELECT false, v_prior;
    RETURN;
  END IF;

  UPDATE public.contacts
  SET engagement_conv_count_at_last_summary = p_conv_count
  WHERE id = p_contact_id;

  RETURN QUERY SELECT true, v_prior;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_contact_for_engagement(uuid, integer)
  TO service_role, authenticated;

COMMENT ON FUNCTION public.claim_contact_for_engagement(uuid, integer) IS
  'Train K.1: atomic claim for engagement summary generation. Mirrors '
  'claim_conversation_for_summary. Returns claimed=true if this caller '
  'should run the LLM; false if another worker already advanced past '
  'p_conv_count.';


-- ----------------------------------------------------------------------------
-- 4. Smoke tests
-- ----------------------------------------------------------------------------
DO $smoke$
DECLARE
  v_overload_count int;
  v_helper_jsonb_overload_exists boolean;
  v_claim_exists boolean;
BEGIN
  -- One canonical upsert overload remains
  SELECT count(*) INTO v_overload_count
  FROM pg_proc
  WHERE proname = 'upsert_contact_with_org_v2'
    AND pronamespace = 'public'::regnamespace;
  IF v_overload_count <> 1 THEN
    RAISE EXCEPTION 'K.1 smoke test failed: expected 1 upsert overload, found %', v_overload_count;
  END IF;

  -- jsonb overload of _field_trust_should_overwrite exists
  SELECT EXISTS(
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE p.proname = '_field_trust_should_overwrite'
      AND n.nspname = 'public'
      AND pg_get_function_arguments(p.oid) LIKE '%jsonb%'
  ) INTO v_helper_jsonb_overload_exists;
  IF NOT v_helper_jsonb_overload_exists THEN
    RAISE EXCEPTION 'K.1 smoke test failed: jsonb overload of _field_trust_should_overwrite not found';
  END IF;

  -- claim_contact_for_engagement exists
  SELECT EXISTS(
    SELECT 1 FROM pg_proc
    WHERE proname = 'claim_contact_for_engagement'
      AND pronamespace = 'public'::regnamespace
  ) INTO v_claim_exists;
  IF NOT v_claim_exists THEN
    RAISE EXCEPTION 'K.1 smoke test failed: claim_contact_for_engagement not found';
  END IF;
END;
$smoke$;

-- ----------------------------------------------------------------------------
-- 5. End-to-end exercise of the existing-contact UPDATE branch
-- ----------------------------------------------------------------------------
-- Verify the #16 fix by upserting twice for the same (synthetic) email.
-- The second call exercises the previously-broken branch.

DO $verify$
DECLARE
  v_test_email   text := 'k1-smoke-' || extract(epoch from now())::bigint || '@example.com';
  v_first_run    record;
  v_second_run   record;
BEGIN
  -- First call (creates new contact)
  SELECT * INTO v_first_run
  FROM public.upsert_contact_with_org_v2(
    p_email := v_test_email,
    p_first_name := 'K1',
    p_last_name := 'SmokeTest',
    p_source := 'k1_smoke',
    p_source_confidence := 0.9::numeric
  );
  IF v_first_run.contact_id IS NULL THEN
    RAISE EXCEPTION 'K.1 smoke test failed: first upsert did not create contact';
  END IF;

  -- Second call exercises the existing-contact UPDATE branch (was broken
  -- pre-K.1 due to ambiguous organization_id reference).
  SELECT * INTO v_second_run
  FROM public.upsert_contact_with_org_v2(
    p_email := v_test_email,
    p_first_name := 'K1Updated',
    p_source := 'k1_smoke_v2',
    p_source_confidence := 0.95::numeric
  );
  IF v_second_run.contact_id IS NULL THEN
    RAISE EXCEPTION 'K.1 smoke test failed: second upsert returned NULL contact_id';
  END IF;
  IF v_second_run.is_new_contact THEN
    RAISE EXCEPTION 'K.1 smoke test failed: second upsert reported is_new_contact=true (expected false)';
  END IF;

  -- Cleanup the synthetic contact
  DELETE FROM public.contacts WHERE id = v_first_run.contact_id;
END;
$verify$;

COMMIT;
