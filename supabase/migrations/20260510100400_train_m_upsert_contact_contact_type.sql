-- ============================================================================
-- Train M — upsert_contact_with_org_v2 gains p_contact_type
-- ============================================================================
-- Two coordinated changes to the contact intake path:
--
-- 1. _is_role_address now matches ONLY system-tier patterns. role/shared
--    patterns added in the Train M categories migration (info@, accounts@,
--    sales@, ...) no longer cause the RPC to reject — those become real
--    contacts with contact_type='role' or 'shared'.
--
-- 2. upsert_contact_with_org_v2 gains a `p_contact_type` parameter
--    (defaults to NULL → falls back to server-side classify via the new
--    _classify_contact_type helper). The category gets stored in
--    contacts.contact_type at insert time. Existing-contact updates
--    don't touch contact_type — operator changes via the UI win.
--
-- Body of upsert_contact_with_org_v2 is otherwise byte-identical to the
-- Train K.1 version (20260504071238), preserving the organization_id
-- ambiguity fix and the Train I/L NULL-org behaviour.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. _is_role_address — narrow to category='system' only
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._is_role_address(p_email text)
RETURNS boolean
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_local  text;
  v_match  int;
BEGIN
  IF p_email IS NULL OR position('@' IN p_email) = 0 THEN
    RETURN true;  -- garbage input treated as role
  END IF;
  v_local := lower(split_part(p_email, '@', 1)) || '@';
  SELECT COUNT(*) INTO v_match
  FROM public.role_address_patterns
  WHERE is_active
    AND category = 'system'   -- TRAIN M: only system-tier rejects
    AND v_local ~ pattern;
  RETURN v_match > 0;
END;
$$;

COMMENT ON FUNCTION public._is_role_address(text) IS
  'Train M: returns true only when the local part matches a system-tier '
  'role_address_pattern (noreply, mailer-daemon, postmaster, etc.). '
  'role/shared categories (info@, accounts@, sales@) return false here so '
  'the upsert RPC creates them as contacts with contact_type set. Use '
  '_classify_contact_type to get the full category tag.';

-- ----------------------------------------------------------------------------
-- 2. _classify_contact_type — server-side mirror of the Python helper
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._classify_contact_type(p_email text)
RETURNS text
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_local    text;
  v_category text;
BEGIN
  IF p_email IS NULL OR position('@' IN p_email) = 0 THEN
    RETURN 'system';
  END IF;
  v_local := lower(split_part(p_email, '@', 1)) || '@';

  SELECT category INTO v_category
  FROM public.role_address_patterns
  WHERE is_active
    AND v_local ~ pattern
  ORDER BY
    CASE category
      WHEN 'system' THEN 0  -- prefer system over role/shared if multiple match
      WHEN 'role'   THEN 1
      WHEN 'shared' THEN 2
    END
  LIMIT 1;

  RETURN COALESCE(v_category, 'person');
END;
$$;

COMMENT ON FUNCTION public._classify_contact_type(text) IS
  'Returns one of person | role | shared | system based on the email local '
  'part. Used by upsert_contact_with_org_v2 to populate contacts.contact_type '
  'when no explicit p_contact_type is passed by the caller.';

GRANT EXECUTE ON FUNCTION public._classify_contact_type(text)
  TO service_role, authenticated;

-- ----------------------------------------------------------------------------
-- 3. upsert_contact_with_org_v2 — add p_contact_type, persist on insert
-- ----------------------------------------------------------------------------
-- Body otherwise identical to Train K.1 (20260504071238). Only changes:
--   - new p_contact_type parameter (default NULL → server-side classify)
--   - INSERT writes contact_type column
--   - existing-contact update branch leaves contact_type alone (operator
--     edits via UI are sticky)

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
  p_source_confidence numeric DEFAULT 0.5,
  p_contact_type      text DEFAULT NULL
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
  v_contact_type text;
BEGIN
  -- 1. Reject empty / malformed email
  IF p_email IS NULL OR position('@' in p_email) = 0 THEN
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, false, false, ARRAY[]::text[];
    RETURN;
  END IF;

  -- 1b. Reject system-tier role addresses (noreply, mailer-daemon, ...)
  -- TRAIN M: role/shared categories no longer reject — they get a contact_type tag.
  IF public._is_role_address(p_email) THEN
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, false, true, ARRAY[]::text[];
    RETURN;
  END IF;

  -- 1c. Resolve contact_type. Caller's explicit value wins; otherwise classify.
  v_contact_type := COALESCE(
    NULLIF(trim(p_contact_type), ''),
    public._classify_contact_type(p_email)
  );
  IF v_contact_type NOT IN ('person', 'role', 'shared', 'system') THEN
    v_contact_type := 'person';
  END IF;
  -- Defence-in-depth: if classify returned 'system' (shouldn't happen since
  -- _is_role_address would have already rejected), still bail.
  IF v_contact_type = 'system' THEN
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
  --    Train L L3 routing in lambda enrichment fills it in async.

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
      organization_id, status, contact_type, field_sources, created_at, updated_at
    )
    VALUES (
      p_email, p_first_name, p_last_name, p_job_title, p_role, p_phone, p_department,
      v_org_id, 'active', v_contact_type, v_field_sources, v_now, v_now
    )
    RETURNING id INTO contact_id;

    organization_id := v_org_id;
    is_new_contact := true;
    is_role_address := false;
  ELSE
    -- Existing contact — apply trust-merge. contact_type is left alone here:
    -- operator edits in the UI are sticky, and we don't want a later soft-tag
    -- change in the role_address_patterns table to silently flip a contact's
    -- type back. M3 UI surfaces the type and lets operators correct it manually.
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

GRANT EXECUTE ON FUNCTION public.upsert_contact_with_org_v2(text,text,text,text,text,text,text,text,text,text,numeric,text)
  TO service_role, authenticated;

COMMENT ON FUNCTION public.upsert_contact_with_org_v2(text,text,text,text,text,text,text,text,text,text,numeric,text) IS
  'Train M: adds p_contact_type parameter. role/shared categories now create '
  'contacts with the type tag instead of being rejected. Existing-contact '
  'updates leave contact_type alone (operator UI edits are sticky).';

-- Drop the old 11-arg overload to avoid PostgREST ambiguity.
DROP FUNCTION IF EXISTS public.upsert_contact_with_org_v2(
  text, text, text, text, text, text, text, text, text, text, numeric
);

COMMIT;

-- ----------------------------------------------------------------------------
-- Smoke tests
-- ----------------------------------------------------------------------------
DO $smoke$
DECLARE
  v_overload_count int;
  v_role_classify  text;
  v_shared_classify text;
  v_system_classify text;
  v_person_classify text;
BEGIN
  -- One overload remains
  SELECT count(*) INTO v_overload_count
  FROM pg_proc
  WHERE proname = 'upsert_contact_with_org_v2'
    AND pronamespace = 'public'::regnamespace;
  IF v_overload_count <> 1 THEN
    RAISE EXCEPTION 'Train M smoke: expected 1 upsert overload, found %', v_overload_count;
  END IF;

  -- Classification correctness
  v_person_classify := public._classify_contact_type('jane@example.com');
  v_role_classify   := public._classify_contact_type('accounts@example.com');
  v_shared_classify := public._classify_contact_type('info@example.com');
  v_system_classify := public._classify_contact_type('noreply@example.com');

  IF v_person_classify <> 'person' THEN
    RAISE EXCEPTION 'Train M smoke: jane@ classified as % (expected person)', v_person_classify;
  END IF;
  IF v_role_classify <> 'role' THEN
    RAISE EXCEPTION 'Train M smoke: accounts@ classified as % (expected role)', v_role_classify;
  END IF;
  IF v_shared_classify <> 'shared' THEN
    RAISE EXCEPTION 'Train M smoke: info@ classified as % (expected shared)', v_shared_classify;
  END IF;
  IF v_system_classify <> 'system' THEN
    RAISE EXCEPTION 'Train M smoke: noreply@ classified as % (expected system)', v_system_classify;
  END IF;

  -- _is_role_address narrowed to system-only
  IF public._is_role_address('accounts@example.com') THEN
    RAISE EXCEPTION 'Train M smoke: _is_role_address still rejects accounts@ (should not)';
  END IF;
  IF NOT public._is_role_address('noreply@example.com') THEN
    RAISE EXCEPTION 'Train M smoke: _is_role_address fails to reject noreply@';
  END IF;
END
$smoke$;

-- End-to-end: round-trip a role-typed contact
DO $verify$
DECLARE
  v_test_email text := 'm-smoke-accounts-' || extract(epoch from now())::bigint || '@example.com';
  v_run        record;
  v_stored_type text;
BEGIN
  -- Insert pattern matching v_test_email's local-part prefix
  -- (using a one-off pattern so we don't pollute the table)
  INSERT INTO public.role_address_patterns (pattern, description, category)
  VALUES ('^m-smoke-accounts-', 'Train M smoke test pattern', 'role')
  ON CONFLICT (pattern) DO UPDATE SET category = EXCLUDED.category;

  SELECT * INTO v_run
  FROM public.upsert_contact_with_org_v2(
    p_email := v_test_email,
    p_first_name := 'Accounts Team',
    p_source := 'm_smoke',
    p_source_confidence := 0.5::numeric
  );
  IF v_run.contact_id IS NULL THEN
    RAISE EXCEPTION 'Train M smoke: role-typed contact not created';
  END IF;

  SELECT contact_type INTO v_stored_type
  FROM public.contacts WHERE id = v_run.contact_id;
  IF v_stored_type <> 'role' THEN
    RAISE EXCEPTION 'Train M smoke: contact_type stored as % (expected role)', v_stored_type;
  END IF;

  -- Cleanup
  DELETE FROM public.contacts WHERE id = v_run.contact_id;
  DELETE FROM public.role_address_patterns WHERE pattern = '^m-smoke-accounts-';
END
$verify$;
