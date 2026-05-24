-- Host organization concept
-- Spec: docs/superpowers/specs/2026-05-24-host-org-concept-design.md
--
-- Adds first-class host-org awareness:
--   * organizations.is_host  - flag identifying operator-owned organizations
--   * emails.is_internal     - true when every participant is on a host-org domain
--   * is_host_domain(text)   - SQL helper queried by triggers, RPC, and ad-hoc filters
--   * v_contacts_with_internal - view used by contact lists, lead-gen, campaign targeting
--
-- Backfill marks the existing PDMedical org as host (matched against active
-- mailbox domains) and recomputes is_internal for every existing email row.

BEGIN;

-- 1. Add is_host flag to organizations
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS is_host BOOLEAN NOT NULL DEFAULT FALSE;

-- 2. Add is_internal classification to emails
ALTER TABLE public.emails
  ADD COLUMN IF NOT EXISTS is_internal BOOLEAN NOT NULL DEFAULT FALSE;

-- 3. Helper: is the given address on a host-org domain?
CREATE OR REPLACE FUNCTION public.is_host_domain(p_address text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.organizations
    WHERE is_host = TRUE
      AND lower(domain) = lower(split_part(coalesce(p_address, ''), '@', 2))
  );
$$;

-- 4. Derived view: contacts with is_internal column
CREATE OR REPLACE VIEW public.v_contacts_with_internal AS
SELECT
  c.*,
  COALESCE(o.is_host, FALSE) AS is_internal
FROM public.contacts c
LEFT JOIN public.organizations o ON o.id = c.organization_id;

-- 5. Auto-detect host orgs from existing active mailboxes.
--    Matches any organization whose domain equals the domain of any active mailbox.
UPDATE public.organizations o
SET is_host = TRUE
WHERE lower(o.domain) IN (
  SELECT DISTINCT lower(split_part(m.email, '@', 2))
  FROM public.mailboxes m
  WHERE m.is_active = TRUE
);

-- 6. Backfill emails.is_internal using the new registry.
--    Email is internal iff every non-empty participant address is on a host domain.
UPDATE public.emails e
SET is_internal = COALESCE((
  SELECT bool_and(public.is_host_domain(addr))
  FROM unnest(
    array_remove(
      ARRAY[e.from_email] || COALESCE(e.to_emails, ARRAY[]::text[])
                          || COALESCE(e.cc_emails, ARRAY[]::text[])
                          || COALESCE(e.bcc_emails, ARRAY[]::text[]),
      NULL
    )
  ) AS addr
  WHERE addr IS NOT NULL AND addr <> ''
), FALSE);

-- 7. Indexes (created after backfill so they populate correctly).
CREATE INDEX IF NOT EXISTS organizations_is_host_partial
  ON public.organizations (is_host) WHERE is_host = TRUE;

CREATE INDEX IF NOT EXISTS emails_is_internal_received_at
  ON public.emails (is_internal, received_at DESC);

COMMIT;
