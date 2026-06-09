-- Host organization concept
-- Spec: docs/superpowers/specs/2026-05-24-host-org-concept-design.md
--
-- Adds first-class host-org awareness:
--   * organizations.is_host  - flag identifying operator-owned organizations
--   * emails.is_internal     - true when every participant is on a host-org domain
--   * is_host_domain(text)   - SQL helper queried by triggers, RPC, and ad-hoc filters
--   * v_contacts_with_internal - view used by contact lists, lead-gen, campaign targeting
--
-- This migration is schema-only. Environment-specific host organization
-- selection and historical email reclassification are handled explicitly by
-- scripts/host_org_one_time_setup.py and rebuild_email_scopes_for_domain(domain).

BEGIN;

-- 1. Add is_host flag to organizations
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS is_host BOOLEAN NOT NULL DEFAULT FALSE;

-- 2. Add is_internal classification to emails
ALTER TABLE public.emails
  ADD COLUMN IF NOT EXISTS is_internal BOOLEAN NOT NULL DEFAULT FALSE;

-- 3. Helpers: is the given address on a host-org domain?
--    organization_domains is the source of truth for primary + alias domains.
--    organizations.domain remains as a fallback for legacy rows without aliases.
CREATE OR REPLACE FUNCTION public.host_org_domains()
RETURNS TABLE(domain text)
LANGUAGE sql
STABLE
AS $$
  SELECT DISTINCT lower(od.domain)::text AS domain
  FROM public.organization_domains od
  JOIN public.organizations o ON o.id = od.organization_id
  WHERE o.is_host = TRUE
    AND od.domain IS NOT NULL
    AND od.domain <> ''
  UNION
  SELECT DISTINCT lower(o.domain)::text AS domain
  FROM public.organizations o
  WHERE o.is_host = TRUE
    AND o.domain IS NOT NULL
    AND o.domain <> '';
$$;

CREATE OR REPLACE FUNCTION public.is_host_domain(p_address text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.host_org_domains() h
    WHERE h.domain = lower(split_part(trim(both ' <>"' from coalesce(p_address, '')), '@', 2))
  );
$$;

-- 4. Derived view: contacts with is_internal column
CREATE OR REPLACE VIEW public.v_contacts_with_internal AS
SELECT
  c.*,
  COALESCE(o.is_host, FALSE) AS is_internal
FROM public.contacts c
LEFT JOIN public.organizations o ON o.id = c.organization_id;

-- 5. Indexes for host-org filtering and later explicit rebuilds.
CREATE INDEX IF NOT EXISTS organizations_is_host_partial
  ON public.organizations (is_host) WHERE is_host = TRUE;

CREATE INDEX IF NOT EXISTS emails_is_internal_received_at
  ON public.emails (is_internal, received_at DESC);

COMMIT;
