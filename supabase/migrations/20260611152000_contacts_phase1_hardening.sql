-- Contacts Phase 1 hardening.
--
-- Keeps the Unknown sentinel invariant explicit after the page-sized Contacts
-- RPC rollout and adds indexes for the new grouped expansion/list query shape.

INSERT INTO public.organizations (
  id,
  name,
  domain,
  status,
  source,
  tags,
  custom_fields
)
VALUES (
  'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid,
  'Unknown',
  '__unknown_sentinel__',
  'active',
  'seeded',
  '[]'::jsonb,
  jsonb_build_object('is_unknown_sentinel', true)
)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  domain = EXCLUDED.domain,
  status = EXCLUDED.status,
  source = 'seeded',
  custom_fields = COALESCE(public.organizations.custom_fields, '{}'::jsonb)
    || jsonb_build_object('is_unknown_sentinel', true),
  updated_at = now();

CREATE OR REPLACE FUNCTION public.prevent_unknown_sentinel_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.id = 'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid
     OR COALESCE((OLD.custom_fields->>'is_unknown_sentinel')::boolean, false) = true THEN
    RAISE EXCEPTION
      'Cannot delete the Unknown sentinel organisation (%, %). Re-assign contacts to a real organisation instead.',
      OLD.id, OLD.name;
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_unknown_sentinel_delete ON public.organizations;
CREATE TRIGGER trg_prevent_unknown_sentinel_delete
  BEFORE DELETE ON public.organizations
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_unknown_sentinel_delete();

CREATE INDEX IF NOT EXISTS contacts_coalesced_org_updated_idx
  ON public.contacts (
    (COALESCE(organization_id, 'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid)),
    updated_at DESC NULLS LAST,
    created_at DESC NULLS LAST,
    id
  );

CREATE INDEX IF NOT EXISTS contacts_coalesced_org_status_updated_idx
  ON public.contacts (
    (COALESCE(organization_id, 'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid)),
    status,
    updated_at DESC NULLS LAST,
    created_at DESC NULLS LAST,
    id
  );

CREATE INDEX IF NOT EXISTS contacts_status_created_idx
  ON public.contacts (
    status,
    created_at DESC NULLS LAST,
    updated_at DESC NULLS LAST,
    id
  );

CREATE INDEX IF NOT EXISTS organizations_hospital_category_idx
  ON public.organizations (hospital_category)
  WHERE hospital_category IS NOT NULL;

DO $$
DECLARE
  v_count integer;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.organizations
  WHERE id = 'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid
    AND name = 'Unknown'
    AND source = 'seeded'
    AND COALESCE((custom_fields->>'is_unknown_sentinel')::boolean, false) = true;

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Contacts Phase 1 hardening failed: Unknown sentinel row missing or malformed';
  END IF;
END;
$$;
