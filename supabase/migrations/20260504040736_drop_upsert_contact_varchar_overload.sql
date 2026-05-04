-- ============================================================================
-- Train K: Drop legacy varchar overload of upsert_contact_with_org_v2
--          + fix is_role_address typo introduced in Train I
--
-- WHY:
--   The 7-day import test on 2026-05-04 logged 29 PGRST203 errors in a single
--   8.5-min import-batch lambda invocation. PostgREST returned HTTP 300
--   "Could not choose the best candidate function" because two overloads of
--   upsert_contact_with_org_v2 exist in the dev DB:
--     1. text-param variant (Train I canonical, returns is_new_contact /
--        is_role_address / fields_set)
--     2. varchar-param variant (legacy, returns was_created /
--        was_role_address / fields_updated)
--   PostgREST cannot disambiguate when the lambda payload sends string params
--   that match both signatures equally well.
--
--   Separately, the Train I migration body calls public.is_role_address(p_email)
--   (line 92 of 20260503055937_nullable_contact_org_and_cleanups.sql) but the
--   actual helper is public._is_role_address (underscore prefix, defined at
--   line 157 of 20260501120200_upsert_contact_with_org_v2.sql). The function
--   call therefore raised "function does not exist" at runtime, but only when
--   PostgREST happened to dispatch to the text overload — silenced under the
--   PGRST203 noise. Hot-fixed dev with a thin wrapper named is_role_address;
--   this migration replaces the typo at source and drops the wrapper.
--
-- WHAT THIS MIGRATION DOES (single transaction):
--   1. Drop the varchar overload of upsert_contact_with_org_v2.
--   2. Recreate the text overload — body verbatim from Train I migration
--      with one character changed: is_role_address -> _is_role_address.
--   3. Drop the dev-only is_role_address(text) wrapper for cleanliness.
--   4. Smoke-test: confirm exactly one upsert_contact_with_org_v2 remains
--      and _is_role_address is callable.
--
-- VERIFIED CALLERS:
--   - lambda contact_intake.py (both layers/shared and functions/shared
--     mirrors) — sends params that match the text overload by name, doesn't
--     read return-shape columns.
--   - lambda tools/contact_tools.py:189 reads rpc_result.get('was_created')
--     which is the legacy varchar shape. After this migration that key is
--     permanently None — fixed in companion lambda PR (Train K PR2) by
--     switching to is_new_contact (the text overload's column name).
-- ============================================================================

BEGIN;

-- 1. Drop the legacy varchar overload. Use full param signature to avoid
--    ambiguity (we only want to drop ONE of the two overloads).
DROP FUNCTION IF EXISTS public.upsert_contact_with_org_v2(
  character varying,
  character varying,
  character varying,
  character varying,
  character varying,
  character varying,
  character varying,
  character varying,
  character varying,
  character varying,
  numeric
);

-- 2. Recreate the text overload — body matches Train I migration verbatim,
--    except the is_role_address call on line 92 is corrected to
--    _is_role_address (the helper that's actually defined). All other logic
--    (placeholder-org elimination, normalise/resolve/narrow, lock-and-upsert,
--    field trust merge, return shape) is preserved exactly.
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
  -- TRAIN K FIX: corrected helper name from is_role_address to _is_role_address
  -- to match the canonical definition at 20260501120200_upsert_contact_with_org_v2.sql:157.
  IF public._is_role_address(p_email) THEN
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, false, true, ARRAY[]::text[];
    RETURN;
  END IF;

  -- 2. Normalise
  v_email_norm   := public._normalise_email_for_dedup(p_email);
  v_email_domain := lower(split_part(p_email, '@', 2));

  -- 3. Resolve organization (with subdomain walk). Leaves v_org_id NULL when
  --    the domain isn't in any known org's alias table.
  v_org_id := public._resolve_org_by_domain(v_email_domain);

  -- 4. If org has children, narrow to facility based on hint
  IF v_org_id IS NOT NULL AND p_facility_hint IS NOT NULL THEN
    v_org_id := public._narrow_to_facility(v_org_id, p_facility_hint);
  END IF;

  -- 5. (Removed in Train I) Previously auto-created a placeholder org when
  --    domain didn't resolve. Now we leave v_org_id NULL. The contact gets
  --    organization_id = NULL; operators can assign one explicitly via the
  --    inline editor or via a future "merge orgs" tool. Rationale: phantom
  --    orgs (one per personal-domain contact) bloated the org list and
  --    skewed v_contact_engagement_profile rollups.

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
    -- Existing contact — apply trust-merge (preserved verbatim from v2.1)
    contact_id      := v_existing.id;
    is_new_contact  := false;
    is_role_address := false;

    -- Trust-merge each editable field. Helper short-circuits manual entries
    -- so we never overwrite operator edits.
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
      -- field_sources jsonb_set per touched field — preserved from v2.1
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
      organization_id = CASE
        WHEN organization_id IS NULL AND v_org_id IS NOT NULL THEN v_org_id
        WHEN v_org_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM public.organizations o
          WHERE o.id = organization_id
            AND COALESCE(o.custom_fields->>'auto_created_from_intake','false')::boolean
        ) THEN v_org_id
        ELSE organization_id
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
  'Train K: dropped varchar overload that was causing PGRST203 disambiguation '
  'errors. This is the canonical text overload (Train I) with the '
  'is_role_address -> _is_role_address typo fix.';

-- 3. Drop the dev-only wrapper that was hot-applied to unblock the import test.
--    Now that the function body calls _is_role_address directly, the wrapper
--    has no purpose. Idempotent — safe whether or not the wrapper exists.
DROP FUNCTION IF EXISTS public.is_role_address(text);

-- 4. Smoke tests — fail loudly if anything is wrong before COMMIT.
DO $smoke$
DECLARE
  v_overload_count int;
  v_helper_exists  boolean;
  v_wrapper_exists boolean;
BEGIN
  SELECT count(*) INTO v_overload_count
  FROM pg_proc
  WHERE proname = 'upsert_contact_with_org_v2'
    AND pronamespace = 'public'::regnamespace;

  IF v_overload_count <> 1 THEN
    RAISE EXCEPTION 'Train K smoke test failed: expected 1 upsert_contact_with_org_v2 overload, found %', v_overload_count;
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM pg_proc
    WHERE proname = '_is_role_address'
      AND pronamespace = 'public'::regnamespace
  ) INTO v_helper_exists;

  IF NOT v_helper_exists THEN
    RAISE EXCEPTION 'Train K smoke test failed: _is_role_address helper not found';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM pg_proc
    WHERE proname = 'is_role_address'
      AND pronamespace = 'public'::regnamespace
  ) INTO v_wrapper_exists;

  IF v_wrapper_exists THEN
    RAISE EXCEPTION 'Train K smoke test failed: is_role_address wrapper still exists, expected dropped';
  END IF;
END;
$smoke$;

COMMIT;
