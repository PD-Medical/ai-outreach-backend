CREATE OR REPLACE FUNCTION public.get_contact_export_rows(
  p_search text DEFAULT NULL,
  p_statuses text[] DEFAULT NULL,
  p_state text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_show_internal boolean DEFAULT FALSE,
  p_limit integer DEFAULT 5000
)
RETURNS TABLE(row_data jsonb)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH tokens AS (
    SELECT '%' || token || '%' AS pat
    FROM regexp_split_to_table(trim(COALESCE(p_search, '')), '\s+') AS token
    WHERE length(token) > 0
  ),
  filtered AS (
    SELECT v.*
    FROM public.contacts c
    LEFT JOIN public.organizations o ON o.id = c.organization_id
    JOIN public.v_contact_engagement_profile v ON v.contact_id = c.id
    WHERE (p_show_internal OR COALESCE(o.is_host, FALSE) = FALSE)
      AND (
        COALESCE(array_length(p_statuses, 1), 0) = 0
        OR c.status = ANY(p_statuses)
      )
      AND (COALESCE(p_state, 'all') = 'all' OR o.state = p_state)
      AND (COALESCE(p_category, 'all') = 'all' OR o.hospital_category = p_category)
      AND NOT EXISTS (
        SELECT 1 FROM tokens t
        WHERE NOT (
          (
            COALESCE(c.first_name, '')   || ' ' ||
            COALESCE(c.last_name, '')    || ' ' ||
            COALESCE(c.email, '')        || ' ' ||
            COALESCE(c.job_title, '')    || ' ' ||
            COALESCE(c.phone_search, '') || ' ' ||
            COALESCE(c.notes, '')
          ) ILIKE t.pat
          OR
          (
            COALESCE(o.name, '')    || ' ' ||
            COALESCE(o.domain, '')  || ' ' ||
            COALESCE(o.phone, '')   || ' ' ||
            COALESCE(o.city, '')    || ' ' ||
            COALESCE(o.state, '')   || ' ' ||
            COALESCE(o.suburb, '')  || ' ' ||
            COALESCE(o.region, '')
          ) ILIKE t.pat
        )
      )
  )
  SELECT to_jsonb(f) AS row_data
  FROM filtered f
  ORDER BY lower(COALESCE(f.email, '')) ASC, f.contact_id
  LIMIT LEAST(GREATEST(p_limit, 1), 5000);
$$;

COMMENT ON FUNCTION public.get_contact_export_rows(text, text[], text, text, boolean, integer) IS
  'Returns contact export rows matching the Contacts page server-side filters without requiring page-sized contact_ids.';

GRANT EXECUTE ON FUNCTION public.get_contact_export_rows(text, text[], text, text, boolean, integer) TO authenticated, service_role;
