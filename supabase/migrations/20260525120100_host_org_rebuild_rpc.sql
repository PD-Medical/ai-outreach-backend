-- RPC invoked by host-org-rebuild-scopes Edge Function.
-- Recomputes is_internal for emails whose participants include p_domain or any
-- alias domain attached to the same organization.
--
-- The is_host_domain() helper reads the live registry, so this matches whatever
-- host-org state is current. Idempotent.

CREATE OR REPLACE FUNCTION public.rebuild_email_scopes_for_domain(p_domain text)
RETURNS void
LANGUAGE sql
AS $$
  WITH scope_domains AS (
    SELECT DISTINCT lower(od.domain)::text AS domain
    FROM public.organization_domains od
    WHERE od.organization_id IN (
      SELECT o.id
      FROM public.organizations o
      LEFT JOIN public.organization_domains od_match ON od_match.organization_id = o.id
      WHERE lower(o.domain) = lower(p_domain)
         OR lower(od_match.domain) = lower(p_domain)
    )
    UNION
    SELECT lower(p_domain)::text
  )
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
  ), FALSE)
  WHERE EXISTS (
    SELECT 1 FROM unnest(
      array_remove(
        ARRAY[e.from_email] || COALESCE(e.to_emails, ARRAY[]::text[])
                            || COALESCE(e.cc_emails, ARRAY[]::text[])
                            || COALESCE(e.bcc_emails, ARRAY[]::text[]),
        NULL
      )
    ) AS addr
    WHERE lower(split_part(addr, '@', 2)) = lower(p_domain)
       OR lower(split_part(trim(both ' <>"' from addr), '@', 2)) IN (
         SELECT domain FROM scope_domains
       )
  );
$$;
