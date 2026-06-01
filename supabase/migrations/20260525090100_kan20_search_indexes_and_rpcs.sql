-- KAN-20: search improvement — GIN trigram indexes + search RPCs
--
-- Creates:
--   contacts_search_gin       — GIN trigram expression index on contact local fields
--   organizations_search_gin  — GIN trigram expression index on organisation local fields
--   emails_search_gin         — GIN trigram expression index on email local fields including body_clean
--   search_contacts(q, ...)   — tokenised, multi-field RPC; matches contact OR linked org
--   search_emails(q, ...)     — tokenised, multi-field RPC; matches email OR linked contact OR linked org
--
-- Tokenisation: q is split on whitespace; every token must match SOMEWHERE
-- across the local fields of the row OR its joined neighbours. Implemented
-- via NOT EXISTS over the unmatched-token set so the index can be used per
-- predicate branch and the planner picks bitmap-OR when helpful.
--
-- Index build note: this migration uses plain CREATE INDEX, which acquires
-- a SHARE lock on the table during build. At PD Medical's current scale
-- (~50k contacts, ~200k emails) build time is order-of-minutes. For
-- production, consider running the index DDL separately with CREATE INDEX
-- CONCURRENTLY (cannot run inside a transaction, so cannot live in a
-- standard supabase migration).
--
-- See tasks/kan-20-search-improvement.html for the full plan.

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS contacts_search_gin
  ON public.contacts USING gin (
    (
      coalesce(first_name, '')   || ' ' ||
      coalesce(last_name, '')    || ' ' ||
      coalesce(email, '')        || ' ' ||
      coalesce(job_title, '')    || ' ' ||
      coalesce(phone_search, '') || ' ' ||
      coalesce(notes, '')
    ) gin_trgm_ops
  );

CREATE INDEX IF NOT EXISTS organizations_search_gin
  ON public.organizations USING gin (
    (
      coalesce(name, '')    || ' ' ||
      coalesce(domain, '')  || ' ' ||
      coalesce(phone, '')   || ' ' ||
      coalesce(city, '')    || ' ' ||
      coalesce(state, '')   || ' ' ||
      coalesce(suburb, '')  || ' ' ||
      coalesce(region, '')
    ) gin_trgm_ops
  );

CREATE INDEX IF NOT EXISTS emails_search_gin
  ON public.emails USING gin (
    (
      coalesce(subject, '')      || ' ' ||
      coalesce(from_email, '')   || ' ' ||
      coalesce(from_name, '')    || ' ' ||
      array_to_string(coalesce(to_emails,  ARRAY[]::text[]), ' ') || ' ' ||
      array_to_string(coalesce(cc_emails,  ARRAY[]::text[]), ' ') || ' ' ||
      array_to_string(coalesce(bcc_emails, ARRAY[]::text[]), ' ') || ' ' ||
      coalesce(body_clean, '')
    ) gin_trgm_ops
  );

-- ---------------------------------------------------------------------------
-- search_contacts(q, p_limit, p_offset)
-- ---------------------------------------------------------------------------
-- Returns contact rows where every whitespace-separated token in q appears
-- somewhere in either the contact's own local fields OR the linked
-- organisation's local fields. Matches the existing Contacts.tsx search
-- behaviour (contact fields + org name/city/state/suburb/phone) but adds
-- tokenisation so "Mel Fitzgerald" works.

CREATE OR REPLACE FUNCTION public.search_contacts(
  q text,
  p_limit int DEFAULT 50,
  p_offset int DEFAULT 0
)
RETURNS SETOF public.contacts
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH tokens AS (
    SELECT '%' || token || '%' AS pat
    FROM regexp_split_to_table(trim(coalesce(q, '')), '\s+') AS token
    WHERE length(token) > 0
  )
  SELECT c.*
  FROM public.contacts c
  LEFT JOIN public.organizations o ON o.id = c.organization_id
  WHERE NOT EXISTS (
    SELECT 1 FROM tokens t
    WHERE NOT (
      (
        coalesce(c.first_name, '')   || ' ' ||
        coalesce(c.last_name, '')    || ' ' ||
        coalesce(c.email, '')        || ' ' ||
        coalesce(c.job_title, '')    || ' ' ||
        coalesce(c.phone_search, '') || ' ' ||
        coalesce(c.notes, '')
      ) ILIKE t.pat
      OR
      (
        coalesce(o.name, '')    || ' ' ||
        coalesce(o.domain, '')  || ' ' ||
        coalesce(o.phone, '')   || ' ' ||
        coalesce(o.city, '')    || ' ' ||
        coalesce(o.state, '')   || ' ' ||
        coalesce(o.suburb, '')  || ' ' ||
        coalesce(o.region, '')
      ) ILIKE t.pat
    )
  )
  ORDER BY c.updated_at DESC
  LIMIT greatest(p_limit, 0)
  OFFSET greatest(p_offset, 0);
$$;

COMMENT ON FUNCTION public.search_contacts(text, int, int) IS
  'Tokenised search across contact local fields + linked organisation local fields. Every whitespace-separated token in q must match somewhere. Returns SETOF contacts (frontend resolves org from its existing org cache). SECURITY INVOKER — existing RLS on contacts applies. See KAN-20.';

GRANT EXECUTE ON FUNCTION public.search_contacts(text, int, int) TO authenticated;

-- ---------------------------------------------------------------------------
-- search_emails(q, p_limit, p_offset)
-- ---------------------------------------------------------------------------
-- Returns email rows where every token matches across email local fields
-- (subject / from / to / cc / bcc / body_clean) OR the linked contact's
-- name+email OR the linked organisation's name+location. Fixes the existing
-- subject-only matching in useConversations.ts.

CREATE OR REPLACE FUNCTION public.search_emails(
  q text,
  p_limit int DEFAULT 50,
  p_offset int DEFAULT 0
)
RETURNS SETOF public.emails
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH tokens AS (
    SELECT '%' || token || '%' AS pat
    FROM regexp_split_to_table(trim(coalesce(q, '')), '\s+') AS token
    WHERE length(token) > 0
  )
  SELECT e.*
  FROM public.emails e
  LEFT JOIN public.contacts c ON c.id = e.contact_id
  LEFT JOIN public.organizations o ON o.id = e.organization_id
  WHERE NOT EXISTS (
    SELECT 1 FROM tokens t
    WHERE NOT (
      (
        coalesce(e.subject, '')    || ' ' ||
        coalesce(e.from_email, '') || ' ' ||
        coalesce(e.from_name, '')  || ' ' ||
        array_to_string(coalesce(e.to_emails,  ARRAY[]::text[]), ' ') || ' ' ||
        array_to_string(coalesce(e.cc_emails,  ARRAY[]::text[]), ' ') || ' ' ||
        array_to_string(coalesce(e.bcc_emails, ARRAY[]::text[]), ' ') || ' ' ||
        coalesce(e.body_clean, '')
      ) ILIKE t.pat
      OR
      (
        coalesce(c.first_name, '') || ' ' ||
        coalesce(c.last_name, '')  || ' ' ||
        coalesce(c.email, '')      || ' ' ||
        coalesce(c.job_title, '')  || ' ' ||
        coalesce(c.phone_search, '')
      ) ILIKE t.pat
      OR
      (
        coalesce(o.name, '')    || ' ' ||
        coalesce(o.city, '')    || ' ' ||
        coalesce(o.state, '')   || ' ' ||
        coalesce(o.suburb, '')
      ) ILIKE t.pat
    )
  )
  ORDER BY e.received_at DESC
  LIMIT greatest(p_limit, 0)
  OFFSET greatest(p_offset, 0);
$$;

COMMENT ON FUNCTION public.search_emails(text, int, int) IS
  'Tokenised search across email local fields (subject/from/to/cc/bcc/body_clean) + linked contact + linked organisation. Every whitespace-separated token in q must match somewhere. Body matches only return rows where emails.body_clean is populated; pre-#124 rows are invisible to body search until backfilled. SECURITY INVOKER — existing RLS on emails applies. See KAN-20.';

GRANT EXECUTE ON FUNCTION public.search_emails(text, int, int) TO authenticated;
