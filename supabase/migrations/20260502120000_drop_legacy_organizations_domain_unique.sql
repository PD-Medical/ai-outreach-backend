-- ============================================================================
-- Drop legacy UNIQUE constraint on organizations.domain
-- ============================================================================
-- Background:
-- ---------------------------------------------------------------------------
-- Pre-PR #66, organizations.domain was the source of truth for "which org
-- owns this email domain". The UNIQUE constraint customer_organizations_domain_key
-- enforced 1:1 mapping.
--
-- PR #66 introduced the organization_domains alias table as the new source
-- of truth (see UNIQUE INDEX organization_domains_domain_lower_idx for
-- 1:1 enforcement at the alias level). organizations.domain was kept for
-- backward compatibility (callers still SELECT it) but it is no longer
-- authoritative, and child facility rows under a hierarchical parent now
-- legitimately share a domain string with their parent (e.g. five facility
-- rows under "Canberra Health Services" all carrying canberrahealthservices.
-- act.gov.au, with the parent owning the canonical alias).
--
-- The legacy UNIQUE constraint blocks that legitimate sharing — the seed
-- file PR #66 shipped only worked because the seed pre-flight catches
-- conflicts between *different* org IDs sharing a domain, but it can't
-- catch the in-seed-itself case where multiple facility rows want to share
-- a parent's domain.
--
-- Drop the constraint. Race-safety on placeholder inserts in the RPC moves
-- from "ON CONFLICT (organizations.domain)" to "advisory lock + check the
-- alias table first" (see CREATE OR REPLACE FUNCTION below).
-- ============================================================================

BEGIN;

ALTER TABLE public.organizations
  DROP CONSTRAINT IF EXISTS customer_organizations_domain_key;

-- ----------------------------------------------------------------------------
-- Replace upsert_contact_with_org_v2 to remove the now-broken ON CONFLICT
-- (domain) placeholder-INSERT path. Use a transaction-scoped advisory lock
-- keyed on the email domain so two concurrent intake calls for a brand-new
-- domain serialize: the second one re-resolves through the alias table
-- after the first commits.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_contact_with_org_v2(
  p_email              varchar,
  p_first_name         varchar DEFAULT NULL,
  p_last_name          varchar DEFAULT NULL,
  p_job_title          varchar DEFAULT NULL,
  p_role               varchar DEFAULT NULL,
  p_phone              varchar DEFAULT NULL,
  p_department         varchar DEFAULT NULL,
  p_facility_hint      varchar DEFAULT NULL,
  p_signature_org_name varchar DEFAULT NULL,
  p_source             varchar DEFAULT 'unknown',
  p_source_confidence  numeric DEFAULT 0.5
)
RETURNS TABLE (
  contact_id        uuid,
  organization_id   uuid,
  was_created       boolean,
  was_role_address  boolean,
  fields_updated    text[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_email_norm   varchar;
  v_email_domain varchar;
  v_existing     RECORD;
  v_org_id       uuid;
  v_contact_id   uuid;
  v_was_created  boolean := false;
  v_fields       text[]  := ARRAY[]::text[];
  v_now          timestamptz := now();
  v_field_sources jsonb;
  v_meta_first   jsonb;
  v_meta_last    jsonb;
  v_meta_jt      jsonb;
  v_meta_role    jsonb;
  v_meta_phone   jsonb;
  v_meta_dept    jsonb;

  v_should_set boolean;
  v_cur_src text;
  v_cur_conf numeric;
BEGIN
  -- 1. Validate + role-address filter
  IF p_email IS NULL OR position('@' IN p_email) = 0 THEN
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, false, false, ARRAY[]::text[];
    RETURN;
  END IF;

  IF public._is_role_address(p_email) THEN
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, false, true, ARRAY[]::text[];
    RETURN;
  END IF;

  -- 2. Normalise
  v_email_norm   := public._normalise_email_for_dedup(p_email);
  v_email_domain := lower(split_part(p_email, '@', 2));

  -- 3. Resolve organization (with subdomain walk)
  v_org_id := public._resolve_org_by_domain(v_email_domain);

  -- 4. If org has children, narrow to facility based on hint
  IF v_org_id IS NOT NULL AND p_facility_hint IS NOT NULL THEN
    v_org_id := public._narrow_to_facility(v_org_id, p_facility_hint);
  END IF;

  -- 5. If still no org, create a placeholder so contacts.organization_id NOT
  --    NULL holds. Race-safety: organizations.domain no longer carries a
  --    UNIQUE constraint (dropped above), so we serialize on a transaction-
  --    scoped advisory lock keyed by the email domain. Two concurrent intake
  --    calls for the same brand-new domain take this lock in turn; the second
  --    one re-resolves through the alias table after the first commits and
  --    finds the org without creating a duplicate row. organization_domains
  --    UNIQUE INDEX on lower(domain) backstops the race.
  IF v_org_id IS NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(v_email_domain, 0));

    -- Re-check after lock acquisition
    v_org_id := public._resolve_org_by_domain(v_email_domain);

    IF v_org_id IS NULL THEN
      INSERT INTO public.organizations (name, domain, status, tags, custom_fields)
      VALUES (
        COALESCE(NULLIF(trim(p_signature_org_name), ''),
                 initcap(split_part(v_email_domain, '.', 1))),
        v_email_domain,
        'active',
        '[]'::jsonb,
        jsonb_build_object('auto_created_from_intake', true)
      )
      RETURNING id INTO v_org_id;

      INSERT INTO public.organization_domains (organization_id, domain, is_primary, source)
      VALUES (v_org_id, v_email_domain, true, 'auto-derived')
      ON CONFLICT (organization_id, domain) DO NOTHING;
    END IF;
  END IF;

  -- 6. Lock-and-upsert contact. Match on normalised email (case-insensitive,
  --    plus-addressing-stripped). Original tagged form preserved in custom_fields.
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
      organization_id, status, tags, custom_fields, field_sources
    ) VALUES (
      lower(p_email),
      p_first_name,
      p_last_name,
      p_job_title,
      p_role,
      p_phone,
      p_department,
      v_org_id,
      'active',
      '[]'::jsonb,
      CASE WHEN p_email <> lower(p_email)
           THEN jsonb_build_object('original_email', p_email)
           ELSE '{}'::jsonb
      END,
      v_field_sources
    )
    RETURNING id INTO v_contact_id;

    v_was_created := true;

  ELSE
    -- Existing contact: trust-merge
    v_contact_id := v_existing.id;

    IF p_first_name IS NOT NULL THEN
      v_meta_first := COALESCE(v_existing.field_sources -> 'first_name', NULL);
      v_cur_src := v_meta_first ->> 'source';
      v_cur_conf := (v_meta_first ->> 'confidence')::numeric;
      IF (v_existing.first_name IS NULL OR v_existing.first_name = '')
         OR public._field_trust_should_overwrite(v_cur_src, v_cur_conf, p_source, p_source_confidence) THEN
        UPDATE public.contacts
        SET first_name    = p_first_name,
            field_sources = field_sources || jsonb_build_object('first_name',
              jsonb_build_object('source', p_source, 'confidence', p_source_confidence, 'set_at', v_now)),
            updated_at    = v_now
        WHERE id = v_contact_id;
        v_fields := array_append(v_fields, 'first_name');
      END IF;
    END IF;

    IF p_last_name IS NOT NULL THEN
      v_meta_last := COALESCE(v_existing.field_sources -> 'last_name', NULL);
      v_cur_src := v_meta_last ->> 'source';
      v_cur_conf := (v_meta_last ->> 'confidence')::numeric;
      IF (v_existing.last_name IS NULL OR v_existing.last_name = '')
         OR public._field_trust_should_overwrite(v_cur_src, v_cur_conf, p_source, p_source_confidence) THEN
        UPDATE public.contacts
        SET last_name     = p_last_name,
            field_sources = field_sources || jsonb_build_object('last_name',
              jsonb_build_object('source', p_source, 'confidence', p_source_confidence, 'set_at', v_now)),
            updated_at    = v_now
        WHERE id = v_contact_id;
        v_fields := array_append(v_fields, 'last_name');
      END IF;
    END IF;

    IF p_job_title IS NOT NULL THEN
      v_meta_jt := COALESCE(v_existing.field_sources -> 'job_title', NULL);
      v_cur_src := v_meta_jt ->> 'source';
      v_cur_conf := (v_meta_jt ->> 'confidence')::numeric;
      IF (v_existing.job_title IS NULL OR v_existing.job_title = '')
         OR public._field_trust_should_overwrite(v_cur_src, v_cur_conf, p_source, p_source_confidence) THEN
        UPDATE public.contacts
        SET job_title     = p_job_title,
            field_sources = field_sources || jsonb_build_object('job_title',
              jsonb_build_object('source', p_source, 'confidence', p_source_confidence, 'set_at', v_now)),
            updated_at    = v_now
        WHERE id = v_contact_id;
        v_fields := array_append(v_fields, 'job_title');
      END IF;
    END IF;

    IF p_role IS NOT NULL THEN
      v_meta_role := COALESCE(v_existing.field_sources -> 'role', NULL);
      v_cur_src := v_meta_role ->> 'source';
      v_cur_conf := (v_meta_role ->> 'confidence')::numeric;
      IF (v_existing.role IS NULL OR v_existing.role = '')
         OR public._field_trust_should_overwrite(v_cur_src, v_cur_conf, p_source, p_source_confidence) THEN
        UPDATE public.contacts
        SET role          = p_role,
            field_sources = field_sources || jsonb_build_object('role',
              jsonb_build_object('source', p_source, 'confidence', p_source_confidence, 'set_at', v_now)),
            updated_at    = v_now
        WHERE id = v_contact_id;
        v_fields := array_append(v_fields, 'role');
      END IF;
    END IF;

    IF p_phone IS NOT NULL THEN
      v_meta_phone := COALESCE(v_existing.field_sources -> 'phone', NULL);
      v_cur_src := v_meta_phone ->> 'source';
      v_cur_conf := (v_meta_phone ->> 'confidence')::numeric;
      IF (v_existing.phone IS NULL OR v_existing.phone = '')
         OR public._field_trust_should_overwrite(v_cur_src, v_cur_conf, p_source, p_source_confidence) THEN
        UPDATE public.contacts
        SET phone         = p_phone,
            field_sources = field_sources || jsonb_build_object('phone',
              jsonb_build_object('source', p_source, 'confidence', p_source_confidence, 'set_at', v_now)),
            updated_at    = v_now
        WHERE id = v_contact_id;
        v_fields := array_append(v_fields, 'phone');
      END IF;
    END IF;

    IF p_department IS NOT NULL THEN
      v_meta_dept := COALESCE(v_existing.field_sources -> 'department', NULL);
      v_cur_src := v_meta_dept ->> 'source';
      v_cur_conf := (v_meta_dept ->> 'confidence')::numeric;
      IF (v_existing.department IS NULL OR v_existing.department = '')
         OR public._field_trust_should_overwrite(v_cur_src, v_cur_conf, p_source, p_source_confidence) THEN
        UPDATE public.contacts
        SET department    = p_department,
            field_sources = field_sources || jsonb_build_object('department',
              jsonb_build_object('source', p_source, 'confidence', p_source_confidence, 'set_at', v_now)),
            updated_at    = v_now
        WHERE id = v_contact_id;
        v_fields := array_append(v_fields, 'department');
      END IF;
    END IF;

    -- Re-link from auto-created placeholder org to a real resolved org
    IF v_existing.organization_id IS NULL OR v_org_id <> v_existing.organization_id THEN
      IF EXISTS (
        SELECT 1 FROM public.organizations o
        WHERE o.id = v_existing.organization_id
          AND o.custom_fields @> '{"auto_created_from_intake": true}'::jsonb
      ) THEN
        UPDATE public.contacts
        SET organization_id = v_org_id, updated_at = v_now
        WHERE id = v_contact_id;
        v_fields := array_append(v_fields, 'organization_id');
      END IF;
    END IF;

  END IF;

  RETURN QUERY SELECT v_contact_id, v_org_id, v_was_created, false, v_fields;
END;
$$;

COMMIT;
