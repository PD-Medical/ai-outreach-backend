-- ============================================================================
-- Train L — upsert_contact_with_org_v2 routes personal-mail to sentinel
-- ============================================================================
-- Train I left contacts on personal-mail addresses (gmail.com, hotmail.com,
-- etc.) with organization_id = NULL — which the contacts UI silently dropped.
-- Train L gives those contacts a home: the Unknown sentinel created in the
-- preceding migration.
--
-- ONE behavioural change vs. Train I's body:
--   If _resolve_org_by_domain returns NULL AND the domain is in the
--   hardcoded PERSONAL_MAIL_DOMAINS list, set v_org_id to the Unknown
--   sentinel UUID. Sync, fast, no LLM. Business domains still leave
--   v_org_id NULL — async enrichment (lambda L2/L3) handles those.
--
-- Everything else — role-address rejection, normalisation, facility
-- narrowing, lock-and-upsert, trust-merge, return shape — is preserved
-- verbatim from migration 20260503055937_nullable_contact_org_and_cleanups.
--
-- The personal-mail list is duplicated in two places by design (spec Open
-- Question #4: "hardcoded constant over config row"):
--   - here, as a SQL array constant inside the function body
--   - lambda PERSONAL_MAIL_DOMAINS in functions/shared/personal_mail_domains.py
-- Drift is a deliberate code-change-in-two-places, not a runtime knob.
-- ============================================================================

BEGIN;

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

  -- Hardcoded sentinel UUID — must match
  -- supabase/migrations/20260504120500_train_l_unknown_sentinel_org.sql
  -- and ai-outreach-lambda functions/shared/personal_mail_domains.py
  c_unknown_sentinel constant uuid := 'ffffffff-ffff-4fff-8fff-ffffffffffff';

  -- Hardcoded personal-mail blocklist. Mirror of the Python frozenset in
  -- ai-outreach-lambda functions/shared/personal_mail_domains.py.
  c_personal_mail_domains constant text[] := ARRAY[
    -- Major consumer providers
    'gmail.com','googlemail.com',
    'hotmail.com','outlook.com','live.com','msn.com','hotmail.com.au',
    'yahoo.com','yahoo.com.au','ymail.com',
    'icloud.com','me.com','mac.com',
    'aol.com','protonmail.com','proton.me',
    -- AU ISP-issued mailboxes
    'bigpond.com','bigpond.net.au','bigpond.com.au',
    'optusnet.com.au','iinet.net.au','internode.on.net',
    'tpg.com.au','dodo.com.au','exetel.com.au'
  ];
BEGIN
  -- 1. Reject empty / malformed email
  IF p_email IS NULL OR position('@' in p_email) = 0 THEN
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, false, false, ARRAY[]::text[];
    RETURN;
  END IF;

  -- 1b. Reject role addresses
  IF public.is_role_address(p_email) THEN
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, false, true, ARRAY[]::text[];
    RETURN;
  END IF;

  -- 2. Normalise
  v_email_norm   := public._normalise_email_for_dedup(p_email);
  v_email_domain := lower(split_part(p_email, '@', 2));

  -- 3. Resolve organization
  v_org_id := public._resolve_org_by_domain(v_email_domain);

  -- 4. Train L: route personal-mail addresses to the Unknown sentinel.
  --    Runs BEFORE facility-narrow because a personal mailbox has no facility.
  IF v_org_id IS NULL AND v_email_domain = ANY(c_personal_mail_domains) THEN
    v_org_id := c_unknown_sentinel;
  END IF;

  -- 5. If org has children, narrow to facility based on hint
  IF v_org_id IS NOT NULL
     AND v_org_id <> c_unknown_sentinel
     AND p_facility_hint IS NOT NULL THEN
    v_org_id := public._narrow_to_facility(v_org_id, p_facility_hint);
  END IF;

  -- 6. (Removed in Train I, unchanged in Train L) No inline org creation
  --    for unknown business domains. Async enrichment handles those.

  -- 7. Lock-and-upsert contact. Match on normalised email.
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
    -- Existing contact — apply trust-merge (preserved verbatim from Train I)
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
      -- Backfill organization_id only if currently NULL or pointed at a
      -- legacy auto-created placeholder. Don't relink curated assignments.
      -- Train L: also relink contacts currently on the Unknown sentinel —
      -- when a real org becomes resolvable for that domain (e.g. operator
      -- adds an alias), the next sync should move them off the catch-all.
      organization_id = CASE
        WHEN organization_id IS NULL AND v_org_id IS NOT NULL THEN v_org_id
        WHEN v_org_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM public.organizations o
          WHERE o.id = organization_id
            AND COALESCE(o.custom_fields->>'auto_created_from_intake','false')::boolean
        ) THEN v_org_id
        WHEN v_org_id IS NOT NULL
             AND v_org_id <> c_unknown_sentinel
             AND organization_id = c_unknown_sentinel THEN v_org_id
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
  'Train L: same as Train I (no inline org creation for unknown business '
  'domains) PLUS personal-mail addresses (gmail.com, hotmail.com, etc.) are '
  'linked to the Unknown sentinel org instead of returning NULL. Business '
  'domains not in any org alias still return NULL — async enrichment '
  '(_get_or_create_org_from_email_content) creates an enriched org for them.';

-- Smoke test: function still has the expected signature and a personal-mail
-- domain now resolves to the sentinel.
DO $smoke$
DECLARE
  v_result record;
  v_test_email text := '__train_l_smoke_test_' || extract(epoch from now())::bigint || '@gmail.com';
BEGIN
  SELECT * INTO v_result
  FROM public.upsert_contact_with_org_v2(
    p_email := v_test_email,
    p_first_name := 'Smoke',
    p_last_name := 'Test'
  );

  IF v_result.organization_id IS DISTINCT FROM 'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid THEN
    RAISE EXCEPTION 'Train L smoke test failed: gmail.com email did not route to Unknown sentinel (got %)',
      v_result.organization_id;
  END IF;

  -- Cleanup the smoke test contact
  DELETE FROM public.contacts WHERE id = v_result.contact_id;
END;
$smoke$;

COMMIT;
