-- RPC invoked by host-org-rebuild-scopes Edge Function.
-- Recomputes is_internal for emails whose participants include p_domain.
--
-- The is_host_domain() helper reads the live registry, so this matches whatever
-- host-org state is current. Idempotent.

CREATE OR REPLACE FUNCTION public.rebuild_email_scopes_for_domain(p_domain text)
RETURNS void
LANGUAGE sql
AS $$
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
  );
$$;
