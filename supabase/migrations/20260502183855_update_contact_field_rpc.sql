-- ============================================================================
-- Train F — RPC for inline field editor with provenance tracking
-- ============================================================================
-- The new ContactDetailModal Overview tab makes profile fields clickable.
-- Editing a field sends a single RPC call that:
--   1. Updates the column on contacts
--   2. Sets field_sources[field_name] = {source: 'manual', confidence: 1.0,
--      set_at: now()} so the trust-merge logic in upsert_contact_with_org_v2
--      preserves manual edits over future AI inferences.
--
-- The set of editable fields is whitelisted (freetext only — enum fields
-- like email_category stay AI-managed because operators editing them could
-- break workflow matching). Notes are edited via a dedicated NotesTab and
-- stored on contacts.notes — not in this RPC.
--
-- SECURITY INVOKER so RLS still applies to the underlying contacts row. Any
-- authenticated user who can SELECT a contact can also edit its profile —
-- matches the read access pattern across the app.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.update_contact_field(
  p_contact_id uuid,
  p_field      text,
  p_value      text  -- NULL or empty string clears the field
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_allowed_fields text[] := ARRAY[
    'first_name', 'last_name', 'role', 'department', 'phone'
  ];
  v_normalised   text;
  v_result       jsonb;
  v_provenance   jsonb;
BEGIN
  IF p_contact_id IS NULL THEN
    RAISE EXCEPTION 'p_contact_id is required'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF NOT (p_field = ANY(v_allowed_fields)) THEN
    RAISE EXCEPTION 'Field "%" is not editable. Allowed: %', p_field, v_allowed_fields
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Empty string normalises to NULL so clearing a field via the editor
  -- doesn't leave whitespace-only values lying around.
  v_normalised := NULLIF(BTRIM(COALESCE(p_value, '')), '');

  v_provenance := jsonb_build_object(
    'source',     'manual',
    'confidence', 1.0,
    'set_at',     to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
  );

  -- Dynamic SQL because the column name comes from p_field. format(%I) safely
  -- quotes the identifier; the whitelist above prevents arbitrary columns.
  EXECUTE format(
    'UPDATE public.contacts
        SET %I = $1,
            field_sources = jsonb_set(
              COALESCE(field_sources, ''{}''::jsonb),
              ARRAY[$2],
              $3,
              true
            ),
            updated_at = now()
      WHERE id = $4
   RETURNING jsonb_build_object(
       ''id'',            id,
       ''field'',         $2,
       ''value'',         %I,
       ''field_sources'', field_sources,
       ''updated_at'',    updated_at
     )',
    p_field, p_field
  )
  INTO v_result
  USING v_normalised, p_field, v_provenance, p_contact_id;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'Contact % not found or RLS denied access', p_contact_id
      USING ERRCODE = 'no_data_found';
  END IF;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_contact_field(uuid, text, text) TO authenticated;

COMMENT ON FUNCTION public.update_contact_field IS
  'Train F: inline field editor for ContactDetailModal Overview tab. '
  'Whitelisted to first_name, last_name, role, department, phone. Sets '
  'field_sources[field] = {source:manual, confidence:1.0, set_at:now} so '
  'subsequent AI runs respect manual entries via the trust-merge in '
  'upsert_contact_with_org_v2.';

COMMIT;
