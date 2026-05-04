-- ============================================================================
-- Train L — Unknown sentinel organization
-- ============================================================================
-- Single hardcoded organizations row used as a catch-all "no real org yet"
-- bucket. Three paths land contacts here:
--
--   1. Sync intake (upsert_contact_with_org_v2) for personal-mail addresses
--      (gmail.com, hotmail.com, etc.) — see the M-patch migration in this
--      train.
--   2. Async enrichment (lambda _get_or_create_org_from_email_content) when
--      the sender's domain is in PERSONAL_MAIL_DOMAINS.
--   3. Operator UI when an operator chooses to detach a contact from an org
--      (future).
--
-- The sentinel UUID is hardcoded — first sentinel row in this codebase, no
-- prior convention. Using a UUIDv4-shaped literal so it's distinguishable
-- from gen_random_uuid() output but still passes any uuid-typed columns.
--
-- The sentinel is protected from rename by the K.2 source='seeded' guard in
-- the lambda's update_organization_from_enrichment, AND by the frontend
-- (HospitalEditDialog locks all fields when custom_fields.is_unknown_sentinel
-- is true — Train L F2/F3 deliverables).
--
-- organizations.domain is NOT NULL UNIQUE. We give the sentinel a synthetic
-- value `__unknown_sentinel__` that cannot collide with a real DNS name (no
-- real domain begins with an underscore at the label boundary). The sentinel
-- has NO row in organization_domains — it's a catch-all, not domain-bound,
-- so _resolve_org_by_domain never returns it.
-- ============================================================================

BEGIN;

-- Hardcoded sentinel UUID — must stay in lock-step with:
--   ai-outreach-lambda functions/shared/personal_mail_domains.py
--     UNKNOWN_ORG_SENTINEL_ID
--   ai-outreach-frontend src/lib/sentinel.ts (or wherever F2/F3 reference it)
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
  name          = EXCLUDED.name,
  source        = 'seeded',
  custom_fields = public.organizations.custom_fields
                  || jsonb_build_object('is_unknown_sentinel', true),
  updated_at    = now();

COMMENT ON TABLE public.organizations IS
  'Customer organisations. Includes one Unknown sentinel row '
  '(custom_fields.is_unknown_sentinel = true) used as a catch-all bucket '
  'for personal-mail contacts that have no business org. The sentinel is '
  'never renamed (source=seeded, locked by K.2 guard + frontend F2/F3).';

-- Smoke test: exactly one sentinel exists with the expected shape
DO $smoke$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.organizations
  WHERE id = 'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid
    AND name = 'Unknown'
    AND source = 'seeded'
    AND COALESCE((custom_fields->>'is_unknown_sentinel')::boolean, false) = true;

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Train L smoke test failed: Unknown sentinel row missing or malformed (count=%)', v_count;
  END IF;
END;
$smoke$;

COMMIT;
