-- ============================================================================
-- upsert_contact_with_org_v2 — atomic contact intake RPC
-- ============================================================================
-- Single canonical entry point for creating/updating contacts. Called by all
-- intake paths (Lambda inbound sync, Deno mailbox import, Mailchimp, manual UI,
-- CSV scripts). Atomicity from SELECT … FOR UPDATE on the contact row + the
-- whole function running in a single transaction.
--
-- See spec docs/superpowers/specs/2026-04-30-contact-enrichment-design.md §2
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- Helper: trust-merge precedence ranks for field_sources
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._field_source_rank(p_source text)
RETURNS numeric
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE p_source
    WHEN 'manual'         THEN 1.00
    WHEN 'csv_import'     THEN 0.85
    WHEN 'signature_ai'   THEN 0.70
    WHEN 'mailchimp'      THEN 0.70
    WHEN 'from_header'    THEN 0.50
    WHEN 'imap_envelope'  THEN 0.40
    ELSE                       0.30
  END
$$;

COMMENT ON FUNCTION public._field_source_rank(text) IS
  'Returns the baseline trust rank for a contact field source. Multiplied by per-write confidence to determine effective trust. See trust-merge rule in upsert_contact_with_org_v2.';

-- ----------------------------------------------------------------------------
-- Helper: should we overwrite a field given current vs proposed source?
-- ----------------------------------------------------------------------------
-- Returns true when the new (source, confidence) wins under the trust-merge rule:
--   1. If current is null/empty -> always write
--   2. If new.source = 'manual' -> always write (latest manual wins)
--   3. If current.source = 'manual' and new.source != 'manual' -> never write
--   4. Else: write if rank(new) * conf(new) > rank(current) * conf(current)
CREATE OR REPLACE FUNCTION public._field_trust_should_overwrite(
  current_source     text,
  current_confidence numeric,
  new_source         text,
  new_confidence     numeric
) RETURNS boolean
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE
    WHEN current_source IS NULL THEN true
    WHEN new_source = 'manual' THEN true
    WHEN current_source = 'manual' AND new_source <> 'manual' THEN false
    ELSE (
      public._field_source_rank(new_source) * COALESCE(new_confidence, 0.5)
      >
      public._field_source_rank(current_source) * COALESCE(current_confidence, 0.5)
    )
  END
$$;

-- ----------------------------------------------------------------------------
-- Helper: dedup-normalise an email
-- ----------------------------------------------------------------------------
-- Lowercase + strip plus-addressing local-part suffix.
-- Returns NULL if input doesn't look like an email.
-- Pure SQL so PostgreSQL accepts it as IMMUTABLE for use in functional indexes.
CREATE OR REPLACE FUNCTION public._normalise_email_for_dedup(p_email text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_email IS NULL OR position('@' IN p_email) = 0 THEN NULL
    ELSE split_part(lower(split_part(p_email, '@', 1)), '+', 1)
         || '@' || lower(split_part(p_email, '@', 2))
  END
$$;

-- Functional index so the RPC's contact dedup query is an index scan,
-- not a sequential scan. Non-unique because dev/prod may carry historical
-- plus-addressing duplicates we don't want to fail on at index build time.
CREATE INDEX IF NOT EXISTS contacts_normalised_email_idx
  ON public.contacts (public._normalise_email_for_dedup(email));

-- ----------------------------------------------------------------------------
-- Helper: walk subdomain chain, return first matching org_id
-- ----------------------------------------------------------------------------
-- Given an email's domain, look up organization_domains. If exact miss, strip
-- one label from the left and retry. Returns NULL if no match in the chain.
CREATE OR REPLACE FUNCTION public._resolve_org_by_domain(p_domain text)
RETURNS uuid
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_candidate text;
  v_org_id    uuid;
  v_dot_pos   int;
BEGIN
  IF p_domain IS NULL OR p_domain = '' THEN
    RETURN NULL;
  END IF;
  v_candidate := lower(p_domain);
  LOOP
    SELECT od.organization_id INTO v_org_id
    FROM public.organization_domains od
    WHERE lower(od.domain) = v_candidate
    LIMIT 1;
    IF v_org_id IS NOT NULL THEN
      RETURN v_org_id;
    END IF;
    -- Strip one label from the left
    v_dot_pos := position('.' IN v_candidate);
    EXIT WHEN v_dot_pos = 0;
    v_candidate := substring(v_candidate FROM v_dot_pos + 1);
    -- Stop if we've reduced to a single-label TLD (no dot left)
    EXIT WHEN position('.' IN v_candidate) = 0;
  END LOOP;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public._resolve_org_by_domain(text) IS
  'Walk subdomain chain to find an organisation in organization_domains. Returns NULL on no match. Used by upsert_contact_with_org_v2.';

-- ----------------------------------------------------------------------------
-- Helper: facility-hint matching for contacts arriving on a parent org
-- ----------------------------------------------------------------------------
-- When the resolved org has children (parent_organization_id present below it)
-- and the caller passed a facility hint (e.g. extracted from display name),
-- try to match a child by name similarity.
CREATE OR REPLACE FUNCTION public._narrow_to_facility(
  p_parent_org_id uuid,
  p_hint          text
) RETURNS uuid
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_facility_id uuid;
BEGIN
  IF p_parent_org_id IS NULL OR p_hint IS NULL OR length(trim(p_hint)) < 3 THEN
    RETURN p_parent_org_id;
  END IF;
  SELECT id INTO v_facility_id
  FROM public.organizations
  WHERE parent_organization_id = p_parent_org_id
    AND name ILIKE '%' || p_hint || '%'
  ORDER BY length(name) ASC  -- prefer the most specific match (shortest matching name)
  LIMIT 1;
  RETURN COALESCE(v_facility_id, p_parent_org_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- Helper: is this a role/system address?
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
    AND v_local ~ pattern;
  RETURN v_match > 0;
END;
$$;

-- ----------------------------------------------------------------------------
-- Main RPC: upsert_contact_with_org_v2
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.upsert_contact_with_org_v2(
  varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, numeric
);
DROP FUNCTION IF EXISTS public.upsert_contact_with_org_v2(
  varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, numeric
);

CREATE FUNCTION public.upsert_contact_with_org_v2(
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

  -- Helper inline check
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

  -- 5. If still no org, create a placeholder so contacts.organization_id NOT NULL holds.
  --    Tagged auto_created_from_intake so later AI cleanup can refine it.
  --
  --    Race-safety: organizations.domain has a UNIQUE constraint
  --    (customer_organizations_domain_key). Two concurrent intake calls for
  --    the same brand-new domain would otherwise abort one transaction with
  --    a constraint violation. ON CONFLICT (domain) DO UPDATE with a trivial
  --    SET lets RETURNING work either way: if we won, we get the new row's
  --    id; if we lost, we adopt the existing row's id.
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
    ON CONFLICT (domain) DO UPDATE
      SET updated_at = now()
    RETURNING id INTO v_org_id;

    -- Race-safety belt-and-braces: if for some reason RETURNING gave us NULL
    -- (shouldn't with DO UPDATE, but be defensive), re-resolve through the
    -- alias table — the racing session may have created the alias by now.
    IF v_org_id IS NULL THEN
      v_org_id := public._resolve_org_by_domain(v_email_domain);
    END IF;

    INSERT INTO public.organization_domains (organization_id, domain, is_primary, source)
    VALUES (v_org_id, v_email_domain, true, 'auto-derived')
    ON CONFLICT (organization_id, domain) DO NOTHING;
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

    -- Build initial field_sources entries for non-null inputs
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

    -- first_name
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

    -- last_name
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

    -- job_title
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

    -- role (informal description, often AI-extracted from signatures)
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

    -- phone
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

    -- department
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

    -- If existing contact's organization_id is NULL or pointed at a placeholder,
    -- and we resolved a real org now, update it. Otherwise keep the existing link
    -- (don't move contacts between orgs without explicit user action).
    IF v_existing.organization_id IS NULL OR v_org_id <> v_existing.organization_id THEN
      -- Only relink if existing org was an auto-created placeholder
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

COMMENT ON FUNCTION public.upsert_contact_with_org_v2(
  varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, numeric
) IS
  'Single canonical contact-intake RPC. Atomic. Resolves org via organization_domains (subdomain walk). Applies trust-merge rules to existing contacts. See spec §2.';

-- Allow authenticated users (manual UI form, future frontend callers) and
-- the service_role (Lambda + edge functions). anon must NOT be able to
-- upsert contacts — it's an unauthenticated role used for public-facing
-- read-only Supabase access.
GRANT EXECUTE ON FUNCTION public.upsert_contact_with_org_v2(
  varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, numeric
) TO authenticated, service_role;

COMMIT;
