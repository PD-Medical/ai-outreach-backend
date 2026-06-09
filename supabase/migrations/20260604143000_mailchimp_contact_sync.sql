-- Mailchimp contact sync v1
-- Sidecar state for reconciling PD Medical contacts with Mailchimp audience members.

CREATE TABLE IF NOT EXISTS public.mailchimp_audiences (
  list_id text PRIMARY KEY,
  name text NOT NULL,
  member_count integer,
  default_from_name text,
  default_reply_to_email text,
  raw_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  last_synced_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.mailchimp_contact_links (
  contact_id uuid NOT NULL REFERENCES public.contacts(id) ON DELETE CASCADE,
  list_id text NOT NULL REFERENCES public.mailchimp_audiences(list_id) ON DELETE CASCADE,
  subscriber_hash text NOT NULL,
  unique_email_id text,
  email_address text NOT NULL,
  status text NOT NULL,
  merge_fields jsonb NOT NULL DEFAULT '{}'::jsonb,
  mc_tags jsonb NOT NULL DEFAULT '[]'::jsonb,
  marketing_permissions jsonb NOT NULL DEFAULT '[]'::jsonb,
  stats jsonb NOT NULL DEFAULT '{}'::jsonb,
  vip boolean NOT NULL DEFAULT false,
  last_changed_remote timestamptz,
  last_pulled_at timestamptz,
  last_pushed_at timestamptz,
  raw_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (contact_id, list_id)
);

CREATE TABLE IF NOT EXISTS public.mailchimp_contact_sync_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  action text NOT NULL CHECK (action IN ('import', 'export', 'sync')),
  list_id text,
  status text NOT NULL CHECK (status IN ('running', 'completed', 'failed')),
  requested_by uuid,
  stats jsonb NOT NULL DEFAULT '{}'::jsonb,
  error text,
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_mailchimp_contact_links_list_hash
  ON public.mailchimp_contact_links(list_id, subscriber_hash);

CREATE INDEX IF NOT EXISTS idx_mailchimp_contact_links_last_changed
  ON public.mailchimp_contact_links(last_changed_remote DESC);

CREATE INDEX IF NOT EXISTS idx_mailchimp_contact_links_last_pushed
  ON public.mailchimp_contact_links(last_pushed_at DESC NULLS FIRST);

CREATE INDEX IF NOT EXISTS idx_mailchimp_contact_links_email
  ON public.mailchimp_contact_links(lower(email_address));

CREATE INDEX IF NOT EXISTS idx_mailchimp_contact_sync_runs_started
  ON public.mailchimp_contact_sync_runs(started_at DESC);

DROP TRIGGER IF EXISTS set_mailchimp_audiences_updated_at ON public.mailchimp_audiences;
CREATE TRIGGER set_mailchimp_audiences_updated_at
  BEFORE UPDATE ON public.mailchimp_audiences
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS set_mailchimp_contact_links_updated_at ON public.mailchimp_contact_links;
CREATE TRIGGER set_mailchimp_contact_links_updated_at
  BEFORE UPDATE ON public.mailchimp_contact_links
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.mailchimp_audiences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mailchimp_contact_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mailchimp_contact_sync_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mailchimp_audiences_select_policy ON public.mailchimp_audiences;
CREATE POLICY mailchimp_audiences_select_policy
  ON public.mailchimp_audiences
  FOR SELECT
  USING (public.has_permission('view_contacts'::text));

DROP POLICY IF EXISTS mailchimp_contact_links_select_policy ON public.mailchimp_contact_links;
CREATE POLICY mailchimp_contact_links_select_policy
  ON public.mailchimp_contact_links
  FOR SELECT
  USING (public.has_permission('view_contacts'::text));

DROP POLICY IF EXISTS mailchimp_contact_sync_runs_select_policy ON public.mailchimp_contact_sync_runs;
CREATE POLICY mailchimp_contact_sync_runs_select_policy
  ON public.mailchimp_contact_sync_runs
  FOR SELECT
  USING (public.has_permission('view_contacts'::text));

GRANT SELECT ON public.mailchimp_audiences TO authenticated;
GRANT SELECT ON public.mailchimp_contact_links TO authenticated;
GRANT SELECT ON public.mailchimp_contact_sync_runs TO authenticated;

INSERT INTO public.system_config (key, value, description)
VALUES
  ('mailchimp_default_audience_id', 'null'::jsonb, 'Default Mailchimp audience/list ID for contact export and sync.'),
  ('mailchimp_contact_sync_tag_prefix', '"mc:"'::jsonb, 'Only contact tags with this prefix sync both ways with Mailchimp.'),
  ('mailchimp_contact_sync_enabled', 'true'::jsonb, 'Enables manual Mailchimp contact import/export/sync controls.')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public._mailchimp_is_role_localpart(p_email text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(split_part(coalesce(p_email, ''), '@', 1)) = ANY (ARRAY[
    'info', 'admin', 'sales', 'support', 'hr', 'accounts', 'account',
    'contact', 'hello', 'no-reply', 'noreply', 'marketing', 'enquiries',
    'enquiry', 'reception', 'office', 'orders'
  ]);
$$;

CREATE OR REPLACE FUNCTION public.mailchimp_export_candidates(
  p_list_id text,
  p_limit integer DEFAULT 1000
)
RETURNS TABLE (
  contact_id uuid,
  email text,
  subscriber_hash text,
  first_name text,
  last_name text,
  phone text,
  status text,
  tags jsonb,
  organization_name text,
  updated_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    c.id,
    lower(c.email),
    md5(lower(c.email)),
    c.first_name,
    c.last_name,
    c.phone,
    c.status,
    coalesce(c.tags, '[]'::jsonb),
    o.name,
    c.updated_at
  FROM public.contacts c
  JOIN public.organizations o ON o.id = c.organization_id
  WHERE c.email IS NOT NULL
    AND coalesce(c.contact_type, 'person') = 'person'
    AND public._mailchimp_is_role_localpart(c.email) = false
    AND (nullif(trim(coalesce(c.first_name, '')), '') IS NOT NULL
      OR nullif(trim(coalesce(c.last_name, '')), '') IS NOT NULL)
    AND c.status IN ('active', 'ooo')
    AND NOT EXISTS (
      SELECT 1
      FROM public.mailchimp_contact_links l
      WHERE l.contact_id = c.id
        AND l.list_id = p_list_id
    )
  ORDER BY c.updated_at DESC NULLS LAST, c.created_at DESC NULLS LAST
  LIMIT greatest(0, least(coalesce(p_limit, 1000), 10000));
$$;

CREATE OR REPLACE FUNCTION public.mailchimp_export_preview(p_list_id text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_total integer;
  v_eligible integer;
  v_role integer;
  v_no_org integer;
  v_no_name integer;
  v_bad_status integer;
  v_linked integer;
  v_samples jsonb;
BEGIN
  SELECT count(*) INTO v_total FROM public.contacts WHERE email IS NOT NULL;

  SELECT count(*) INTO v_eligible
  FROM public.mailchimp_export_candidates(p_list_id, 100000);

  SELECT count(*) INTO v_role
  FROM public.contacts c
  WHERE c.email IS NOT NULL
    AND (coalesce(c.contact_type, 'person') <> 'person'
      OR public._mailchimp_is_role_localpart(c.email));

  SELECT count(*) INTO v_no_org
  FROM public.contacts c
  WHERE c.email IS NOT NULL
    AND coalesce(c.contact_type, 'person') = 'person'
    AND public._mailchimp_is_role_localpart(c.email) = false
    AND c.organization_id IS NULL;

  SELECT count(*) INTO v_no_name
  FROM public.contacts c
  WHERE c.email IS NOT NULL
    AND coalesce(c.contact_type, 'person') = 'person'
    AND public._mailchimp_is_role_localpart(c.email) = false
    AND c.organization_id IS NOT NULL
    AND nullif(trim(coalesce(c.first_name, '')), '') IS NULL
    AND nullif(trim(coalesce(c.last_name, '')), '') IS NULL;

  SELECT count(*) INTO v_bad_status
  FROM public.contacts c
  WHERE c.email IS NOT NULL
    AND c.status NOT IN ('active', 'ooo');

  SELECT count(*) INTO v_linked
  FROM public.mailchimp_contact_links
  WHERE list_id = p_list_id;

  SELECT coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb) INTO v_samples
  FROM (
    SELECT email, first_name, last_name, organization_name
    FROM public.mailchimp_export_candidates(p_list_id, 10)
  ) s;

  RETURN jsonb_build_object(
    'list_id', p_list_id,
    'total_contacts', v_total,
    'eligible', v_eligible,
    'excluded', greatest(v_total - v_eligible, 0),
    'breakdown', jsonb_build_object(
      'role_or_shared', v_role,
      'missing_organization', v_no_org,
      'missing_name', v_no_name,
      'status_not_exportable', v_bad_status,
      'already_linked', v_linked
    ),
    'samples', v_samples
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.mailchimp_export_preview(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mailchimp_export_candidates(text, integer) TO authenticated, service_role;

COMMENT ON TABLE public.mailchimp_contact_links IS
  'Sidecar state for one contact on one Mailchimp audience. Contacts remains the primary editable record.';

COMMENT ON FUNCTION public.mailchimp_export_preview(text) IS
  'Computes Mailchimp export eligibility and exclusion counts for a target audience.';
