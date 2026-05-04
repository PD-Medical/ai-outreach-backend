-- ============================================================================
-- Train I — Allow contacts to have no organization + name/seed cleanups
-- ============================================================================
-- Three related changes that hang together because they all clean up the
-- "every contact must belong to an org" assumption:
--
-- 1. Drop NOT NULL on contacts.organization_id. Some contacts (interns,
--    freelancers, generic personal email addresses) genuinely don't belong
--    to any org. Forcing a placeholder org distorts the org list and
--    creates phantom rollups in v_contact_engagement_profile.
--
-- 2. Modify upsert_contact_with_org_v2 to STOP auto-creating placeholder
--    orgs when the email domain doesn't resolve. Returning NULL is now
--    valid; downstream code already tolerates it (conversations.organization_id
--    has been NULL-able from day one; emails.organization_id is also nullable).
--
-- 3. Data cleanup, scoped to known-bad rows:
--    a. Re-set contacts on auto-created placeholder orgs (gmail.com, yahoo.com,
--       outlook.com, hotmail.com, icloud.com, etc., plus any org tagged
--       custom_fields->>'auto_created_from_intake' = 'true') to organization_id
--       = NULL. Curated hospital orgs are NOT touched.
--    b. Strip surrounding single/double quotes from contact first_name /
--       last_name. Affects rows where the From-header parser left quotes in
--       earlier code paths. New rows go through parse_from_header which
--       already strips quotes.
--    c. Conversations + emails that referenced the now-empty orgs keep their
--       link (no harm — the org rows still exist, just no contacts pointing
--       at them).
--
-- All three are forward-compatible. The NOT NULL drop is safe to redeploy
-- (no-op if already nullable). The RPC change uses CREATE OR REPLACE.
-- ============================================================================

BEGIN;

-- 1. Drop NOT NULL
ALTER TABLE public.contacts ALTER COLUMN organization_id DROP NOT NULL;

COMMENT ON COLUMN public.contacts.organization_id IS
  'Optional FK to organizations.id. NULL when the contact''s email domain '
  'does not match any curated org and intake declined to invent a placeholder. '
  'Set explicitly via the inline editor or by re-running enrichment when '
  'better data arrives.';

-- 2. Replace upsert RPC: skip placeholder org creation. The 5-step flow
--    becomes 4 steps; step 5 collapses to "leave v_org_id NULL".
--
-- The whole function body is replicated below because dropping the placeholder
-- step changes the control flow but everything else (resolve_org_by_domain,
-- narrow_to_facility, lock-and-upsert contact, trust merge, return shape) is
-- preserved verbatim.
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
  IF public.is_role_address(p_email) THEN
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
  'Train I: when email domain doesn''t match a known org (via _resolve_org_by_domain '
  'or facility narrowing), returns the contact with organization_id = NULL rather '
  'than auto-creating a placeholder. Operators can assign manually via the inline '
  'editor or wait for AI enrichment to surface a signature_org_name.';

-- 3a. Cleanup: re-set contacts on personal-domain / auto-created orgs to NULL
WITH personal_or_placeholder_orgs AS (
  SELECT id FROM public.organizations
  WHERE domain IN (
    'gmail.com','yahoo.com','yahoo.com.au','outlook.com','hotmail.com',
    'hotmail.com.au','icloud.com','live.com','me.com','aol.com','protonmail.com',
    'msn.com','bigpond.com','bigpond.net.au','optusnet.com.au','tpg.com.au'
  )
  OR COALESCE(custom_fields->>'auto_created_from_intake','false')::boolean
)
UPDATE public.contacts
SET organization_id = NULL, updated_at = now()
WHERE organization_id IN (SELECT id FROM personal_or_placeholder_orgs);

-- 3b. Cleanup: strip surrounding single/double quotes from name fields
UPDATE public.contacts
SET
  first_name = NULLIF(BTRIM(first_name, ' ''"'), ''),
  last_name  = NULLIF(BTRIM(last_name,  ' ''"'), ''),
  updated_at = now()
WHERE
  (first_name LIKE '''%' OR first_name LIKE '"%' OR first_name LIKE '%''' OR first_name LIKE '%"')
  OR
  (last_name  LIKE '''%' OR last_name  LIKE '"%' OR last_name  LIKE '%''' OR last_name  LIKE '%"');

COMMIT;
