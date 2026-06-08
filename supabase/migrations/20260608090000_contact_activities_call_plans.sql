-- ============================================================================
-- Hot Leads UI/UX Phase 1: contact-led CRM activity timeline and call planning
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.contact_context_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id uuid NOT NULL REFERENCES public.contacts(id) ON DELETE CASCADE,
  purpose text NOT NULL DEFAULT 'engagement_summary',
  context_hash text NOT NULL,
  manifest jsonb NOT NULL DEFAULT '{}'::jsonb,
  package jsonb,
  latest_email_at timestamptz,
  latest_activity_at timestamptz,
  conversation_count integer NOT NULL DEFAULT 0,
  activity_count integer NOT NULL DEFAULT 0,
  open_follow_up_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.contact_activities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id uuid NOT NULL REFERENCES public.contacts(id) ON DELETE CASCADE,
  organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL,
  action_item_id uuid REFERENCES public.action_items(id) ON DELETE SET NULL,
  activity_type text NOT NULL,
  title text NOT NULL,
  body text,
  status text NOT NULL DEFAULT 'open',
  priority text NOT NULL DEFAULT 'medium',
  direction text,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  due_at timestamptz,
  completed_at timestamptz,
  completed_by uuid,
  assigned_to uuid,
  created_by uuid,
  visibility text NOT NULL DEFAULT 'team',
  source_type text NOT NULL DEFAULT 'manual',
  source_id uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  deleted_at timestamptz,
  deleted_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT contact_activities_type_check CHECK (
    activity_type IN ('call', 'follow_up', 'note', 'file', 'email', 'campaign', 'meeting', 'system')
  ),
  CONSTRAINT contact_activities_status_check CHECK (
    status IN ('open', 'in_progress', 'completed', 'cancelled')
  ),
  CONSTRAINT contact_activities_priority_check CHECK (
    priority IN ('low', 'medium', 'high', 'urgent')
  ),
  CONSTRAINT contact_activities_direction_check CHECK (
    direction IS NULL OR direction IN ('inbound', 'outbound')
  ),
  CONSTRAINT contact_activities_visibility_check CHECK (
    visibility IN ('team', 'private', 'system')
  )
);

CREATE TABLE IF NOT EXISTS public.contact_activity_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id uuid NOT NULL REFERENCES public.contact_activities(id) ON DELETE CASCADE,
  storage_bucket text NOT NULL DEFAULT 'crm-activity-attachments',
  storage_path text NOT NULL,
  file_name text NOT NULL,
  content_type text,
  file_size bigint,
  uploaded_by uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.contact_activity_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id uuid NOT NULL REFERENCES public.contact_activities(id) ON DELETE CASCADE,
  edited_by uuid NOT NULL,
  previous_payload jsonb NOT NULL,
  new_payload jsonb NOT NULL,
  edited_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.contact_call_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id uuid NOT NULL REFERENCES public.contacts(id) ON DELETE CASCADE,
  context_snapshot_id uuid REFERENCES public.contact_context_snapshots(id) ON DELETE SET NULL,
  context_hash text,
  instruction text,
  opener text,
  objective text,
  talking_points text[] NOT NULL DEFAULT '{}',
  questions text[] NOT NULL DEFAULT '{}',
  likely_objections text[] NOT NULL DEFAULT '{}',
  next_step text,
  after_call_prompt text,
  status text NOT NULL DEFAULT 'active',
  model text,
  tokens_input integer NOT NULL DEFAULT 0,
  tokens_output integer NOT NULL DEFAULT 0,
  superseded_by uuid REFERENCES public.contact_call_plans(id) ON DELETE SET NULL,
  generated_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT contact_call_plans_status_check CHECK (status IN ('active', 'superseded', 'failed'))
);

ALTER TABLE public.action_items
  ADD COLUMN IF NOT EXISTS contact_activity_id uuid REFERENCES public.contact_activities(id) ON DELETE SET NULL;
ALTER TABLE public.contact_activities
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_by uuid;

CREATE INDEX IF NOT EXISTS idx_contact_activities_contact_occurred
  ON public.contact_activities(contact_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_contact_activities_contact_deleted
  ON public.contact_activities(contact_id, deleted_at);
CREATE INDEX IF NOT EXISTS idx_contact_activities_contact_due_open
  ON public.contact_activities(contact_id, due_at)
  WHERE activity_type = 'follow_up' AND status IN ('open', 'in_progress');
CREATE INDEX IF NOT EXISTS idx_contact_activities_action_item
  ON public.contact_activities(action_item_id);
CREATE INDEX IF NOT EXISTS idx_contact_activity_attachments_activity
  ON public.contact_activity_attachments(activity_id);
CREATE INDEX IF NOT EXISTS idx_contact_activity_revisions_activity
  ON public.contact_activity_revisions(activity_id, edited_at DESC);
CREATE INDEX IF NOT EXISTS idx_contact_call_plans_contact_active
  ON public.contact_call_plans(contact_id, generated_at DESC)
  WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_contact_context_snapshots_contact_created
  ON public.contact_context_snapshots(contact_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_contact_context_snapshots_contact_purpose_created
  ON public.contact_context_snapshots(contact_id, purpose, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_action_items_contact_activity
  ON public.action_items(contact_activity_id);

DROP TRIGGER IF EXISTS update_contact_activities_updated_at ON public.contact_activities;
CREATE TRIGGER update_contact_activities_updated_at
BEFORE UPDATE ON public.contact_activities
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.contact_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_activity_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_activity_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_call_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_context_snapshots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "contact_activities read authenticated" ON public.contact_activities;
CREATE POLICY "contact_activities read authenticated"
  ON public.contact_activities FOR SELECT TO authenticated
  USING (true);
DROP POLICY IF EXISTS "contact_activities write authenticated" ON public.contact_activities;

DROP POLICY IF EXISTS "contact_activity_revisions read authenticated" ON public.contact_activity_revisions;
CREATE POLICY "contact_activity_revisions read authenticated"
  ON public.contact_activity_revisions FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "contact_activity_attachments read authenticated" ON public.contact_activity_attachments;
CREATE POLICY "contact_activity_attachments read authenticated"
  ON public.contact_activity_attachments FOR SELECT TO authenticated
  USING (true);
DROP POLICY IF EXISTS "contact_activity_attachments write authenticated" ON public.contact_activity_attachments;

DROP POLICY IF EXISTS "contact_call_plans read authenticated" ON public.contact_call_plans;
CREATE POLICY "contact_call_plans read authenticated"
  ON public.contact_call_plans FOR SELECT TO authenticated
  USING (true);
DROP POLICY IF EXISTS "contact_call_plans write authenticated" ON public.contact_call_plans;

DROP POLICY IF EXISTS "contact_context_snapshots read authenticated" ON public.contact_context_snapshots;
CREATE POLICY "contact_context_snapshots read authenticated"
  ON public.contact_context_snapshots FOR SELECT TO authenticated
  USING (true);
DROP POLICY IF EXISTS "contact_context_snapshots write authenticated" ON public.contact_context_snapshots;

GRANT SELECT ON public.contact_activities TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.contact_activities FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.contact_activities TO service_role;
GRANT SELECT ON public.contact_activity_attachments TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.contact_activity_attachments FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.contact_activity_attachments TO service_role;
GRANT SELECT ON public.contact_activity_revisions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.contact_activity_revisions TO service_role;
GRANT SELECT ON public.contact_call_plans TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.contact_call_plans FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.contact_call_plans TO service_role;
GRANT SELECT ON public.contact_context_snapshots TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.contact_context_snapshots FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.contact_context_snapshots TO service_role;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'crm-activity-attachments',
  'crm-activity-attachments',
  false,
  26214400,
  NULL
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = NULL;

DROP POLICY IF EXISTS "Users can read crm activity attachments" ON storage.objects;

DROP POLICY IF EXISTS "Users can upload crm activity attachments" ON storage.objects;
CREATE POLICY "Users can upload crm activity attachments"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'crm-activity-attachments'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Users can update crm activity attachments" ON storage.objects;

DROP POLICY IF EXISTS "Users can delete crm activity attachments" ON storage.objects;
CREATE POLICY "Users can delete crm activity attachments"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'crm-activity-attachments'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE OR REPLACE FUNCTION public._contact_activity_actor()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT auth.uid();
$$;

CREATE OR REPLACE FUNCTION public._contact_activity_actor_profile()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT p.profile_id
  FROM public.profiles p
  WHERE p.auth_user_id = auth.uid()
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.create_contact_activity(
  p_contact_id uuid,
  p_activity_type text,
  p_title text,
  p_body text DEFAULT NULL,
  p_status text DEFAULT 'open',
  p_priority text DEFAULT 'medium',
  p_direction text DEFAULT NULL,
  p_occurred_at timestamptz DEFAULT now(),
  p_due_at timestamptz DEFAULT NULL,
  p_assigned_to uuid DEFAULT NULL,
  p_visibility text DEFAULT 'team',
  p_metadata jsonb DEFAULT '{}'::jsonb,
  p_create_action_item boolean DEFAULT true
)
RETURNS public.contact_activities
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_contact contacts%ROWTYPE;
  v_activity contact_activities%ROWTYPE;
  v_action_id uuid;
  v_actor uuid := public._contact_activity_actor();
BEGIN
  IF p_contact_id IS NULL THEN
    RAISE EXCEPTION 'contact_id is required';
  END IF;
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'authenticated user required';
  END IF;
  IF NULLIF(trim(p_title), '') IS NULL THEN
    RAISE EXCEPTION 'title is required';
  END IF;
  IF p_activity_type NOT IN ('call', 'follow_up', 'note', 'file') THEN
    RAISE EXCEPTION 'invalid manual activity type';
  END IF;
  IF COALESCE(p_priority, 'medium') NOT IN ('low', 'medium', 'high', 'urgent') THEN
    RAISE EXCEPTION 'invalid priority';
  END IF;
  IF p_direction IS NOT NULL AND p_direction NOT IN ('inbound', 'outbound') THEN
    RAISE EXCEPTION 'invalid direction';
  END IF;

  SELECT * INTO v_contact
  FROM public.contacts
  WHERE id = p_contact_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'contact not found';
  END IF;

  INSERT INTO public.contact_activities (
    contact_id,
    organization_id,
    activity_type,
    title,
    body,
    status,
    priority,
    direction,
    occurred_at,
    due_at,
    assigned_to,
    visibility,
    metadata,
    created_by
  )
  VALUES (
    p_contact_id,
    v_contact.organization_id,
    p_activity_type,
    trim(p_title),
    NULLIF(trim(COALESCE(p_body, '')), ''),
    COALESCE(p_status, 'open'),
    COALESCE(p_priority, 'medium'),
    NULLIF(p_direction, ''),
    COALESCE(p_occurred_at, now()),
    p_due_at,
    p_assigned_to,
    COALESCE(p_visibility, 'team'),
    COALESCE(p_metadata, '{}'::jsonb),
    v_actor
  )
  RETURNING * INTO v_activity;

  IF p_activity_type = 'follow_up' AND p_create_action_item AND COALESCE(p_status, 'open') IN ('open', 'in_progress') THEN
    INSERT INTO public.action_items (
      title,
      description,
      contact_id,
      action_type,
      priority,
      status,
      due_date,
      assigned_to,
      contact_activity_id,
      created_at,
      updated_at
    )
    VALUES (
      trim(p_title),
      NULLIF(trim(COALESCE(p_body, '')), ''),
      p_contact_id,
      'follow_up',
      COALESCE(p_priority, 'medium'),
      'open',
      p_due_at,
      p_assigned_to,
      v_activity.id,
      now(),
      now()
    )
    RETURNING id INTO v_action_id;

    UPDATE public.contact_activities
    SET action_item_id = v_action_id
    WHERE id = v_activity.id
    RETURNING * INTO v_activity;
  END IF;

  IF p_activity_type = 'follow_up' AND COALESCE(p_status, 'open') IN ('open', 'in_progress') THEN
    UPDATE public.contacts
    SET needs_follow_up = true, updated_at = now()
    WHERE id = p_contact_id;
  END IF;

  RETURN v_activity;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_file_contact_activity(
  p_contact_id uuid,
  p_title text,
  p_body text DEFAULT NULL,
  p_storage_path text DEFAULT NULL,
  p_file_name text DEFAULT NULL,
  p_content_type text DEFAULT NULL,
  p_file_size bigint DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS public.contact_activities
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_contact contacts%ROWTYPE;
  v_activity contact_activities%ROWTYPE;
  v_actor uuid := public._contact_activity_actor();
  v_metadata jsonb;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'authenticated user required';
  END IF;
  IF p_contact_id IS NULL THEN
    RAISE EXCEPTION 'contact_id is required';
  END IF;
  IF NULLIF(trim(COALESCE(p_title, '')), '') IS NULL THEN
    RAISE EXCEPTION 'title is required';
  END IF;
  IF NULLIF(trim(COALESCE(p_storage_path, '')), '') IS NULL THEN
    RAISE EXCEPTION 'storage_path is required';
  END IF;
  IF NULLIF(trim(COALESCE(p_file_name, '')), '') IS NULL THEN
    RAISE EXCEPTION 'file_name is required';
  END IF;
  IF split_part(p_storage_path, '/', 1) <> v_actor::text THEN
    RAISE EXCEPTION 'storage_path must be under the authenticated user prefix';
  END IF;
  IF split_part(p_storage_path, '/', 2) <> p_contact_id::text THEN
    RAISE EXCEPTION 'storage_path must include the contact_id as the second path segment';
  END IF;
  IF p_file_size IS NOT NULL AND p_file_size < 0 THEN
    RAISE EXCEPTION 'file_size must be non-negative';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM storage.objects obj
    WHERE obj.bucket_id = 'crm-activity-attachments'
      AND obj.name = trim(p_storage_path)
  ) THEN
    RAISE EXCEPTION 'uploaded file not found';
  END IF;

  SELECT * INTO v_contact
  FROM public.contacts
  WHERE id = p_contact_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'contact not found';
  END IF;

  v_metadata := COALESCE(p_metadata, '{}'::jsonb) || jsonb_build_object(
    'attachment_count', 1,
    'file_name', trim(p_file_name),
    'storage_bucket', 'crm-activity-attachments',
    'storage_path', trim(p_storage_path)
  );

  INSERT INTO public.contact_activities (
    contact_id,
    organization_id,
    activity_type,
    title,
    body,
    status,
    priority,
    occurred_at,
    visibility,
    source_type,
    metadata,
    created_by
  )
  VALUES (
    p_contact_id,
    v_contact.organization_id,
    'file',
    trim(p_title),
    NULLIF(trim(COALESCE(p_body, '')), ''),
    'completed',
    'medium',
    now(),
    'team',
    'manual',
    v_metadata,
    v_actor
  )
  RETURNING * INTO v_activity;

  INSERT INTO public.contact_activity_attachments (
    activity_id,
    storage_bucket,
    storage_path,
    file_name,
    content_type,
    file_size,
    uploaded_by,
    metadata
  )
  VALUES (
    v_activity.id,
    'crm-activity-attachments',
    trim(p_storage_path),
    trim(p_file_name),
    NULLIF(trim(COALESCE(p_content_type, '')), ''),
    p_file_size,
    v_actor,
    '{}'::jsonb
  );

  RETURN v_activity;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_contact_follow_up(p_activity_id uuid)
RETURNS public.contact_activities
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity contact_activities%ROWTYPE;
  v_actor uuid := public._contact_activity_actor();
  v_actor_profile uuid := public._contact_activity_actor_profile();
  v_previous jsonb;
  v_completed_at timestamptz := now();
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'authenticated user required';
  END IF;
  IF p_activity_id IS NULL THEN
    RAISE EXCEPTION 'activity_id is required';
  END IF;

  SELECT *
  INTO v_activity
  FROM public.contact_activities
  WHERE id = p_activity_id
    AND activity_type = 'follow_up'
    AND deleted_at IS NULL
    AND status IN ('open', 'in_progress');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'open follow-up activity not found';
  END IF;

  v_previous := jsonb_build_object(
    'status', v_activity.status,
    'completed_at', v_activity.completed_at,
    'completed_by', v_activity.completed_by
  );

  INSERT INTO public.contact_activity_revisions (
    activity_id,
    edited_by,
    previous_payload,
    new_payload
  )
  VALUES (
    p_activity_id,
    v_actor,
    v_previous,
    jsonb_build_object(
      'status', 'completed',
      'completed_at', v_completed_at,
      'completed_by', v_actor
    )
  );

  UPDATE public.contact_activities
  SET status = 'completed',
      completed_at = v_completed_at,
      completed_by = v_actor,
      updated_at = v_completed_at
  WHERE id = p_activity_id
    AND activity_type = 'follow_up'
    AND deleted_at IS NULL
    AND status IN ('open', 'in_progress')
  RETURNING * INTO v_activity;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'open follow-up activity not found';
  END IF;

  IF v_activity.action_item_id IS NOT NULL THEN
    UPDATE public.action_items
    SET status = 'completed',
        completed_at = v_completed_at,
        completed_by = COALESCE(completed_by, v_actor_profile),
        updated_at = v_completed_at
    WHERE id = v_activity.action_item_id;
  END IF;

  UPDATE public.contacts c
  SET needs_follow_up = EXISTS (
    SELECT 1
    FROM public.contact_activities ca
    WHERE ca.contact_id = v_activity.contact_id
      AND ca.deleted_at IS NULL
      AND ca.activity_type = 'follow_up'
      AND ca.status IN ('open', 'in_progress')
  ),
  updated_at = v_completed_at
  WHERE c.id = v_activity.contact_id;

  RETURN v_activity;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_contact_activity(
  p_activity_id uuid,
  p_title text,
  p_body text DEFAULT NULL,
  p_due_at timestamptz DEFAULT NULL,
  p_priority text DEFAULT 'medium',
  p_direction text DEFAULT NULL,
  p_metadata jsonb DEFAULT NULL
)
RETURNS public.contact_activities
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity contact_activities%ROWTYPE;
  v_updated contact_activities%ROWTYPE;
  v_actor uuid := public._contact_activity_actor();
  v_previous jsonb;
  v_next jsonb;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'authenticated user required';
  END IF;
  IF p_activity_id IS NULL THEN
    RAISE EXCEPTION 'activity_id is required';
  END IF;
  IF NULLIF(trim(p_title), '') IS NULL THEN
    RAISE EXCEPTION 'title is required';
  END IF;
  IF COALESCE(p_priority, 'medium') NOT IN ('low', 'medium', 'high', 'urgent') THEN
    RAISE EXCEPTION 'invalid priority';
  END IF;
  IF p_direction IS NOT NULL AND p_direction NOT IN ('inbound', 'outbound') THEN
    RAISE EXCEPTION 'invalid direction';
  END IF;

  SELECT *
  INTO v_activity
  FROM public.contact_activities
  WHERE id = p_activity_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'activity not found';
  END IF;
  IF v_activity.created_by IS DISTINCT FROM v_actor THEN
    RAISE EXCEPTION 'only the activity owner can edit this activity';
  END IF;
  IF v_activity.source_type <> 'manual'
    OR v_activity.activity_type NOT IN ('call', 'follow_up', 'note', 'file') THEN
    RAISE EXCEPTION 'this activity type is read-only';
  END IF;
  IF v_activity.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'deleted activities cannot be edited';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.contact_activities next_activity
    WHERE next_activity.contact_id = v_activity.contact_id
      AND next_activity.deleted_at IS NULL
      AND (
        next_activity.occurred_at > v_activity.occurred_at
        OR (
          next_activity.occurred_at = v_activity.occurred_at
          AND next_activity.created_at > v_activity.created_at
        )
      )
  )
  OR EXISTS (
    SELECT 1
    FROM public.campaign_events next_campaign
    WHERE next_campaign.contact_id = v_activity.contact_id
      AND next_campaign.event_timestamp > v_activity.occurred_at
  ) THEN
    RAISE EXCEPTION 'activity can no longer be edited because newer timeline activity exists';
  END IF;

  v_previous := jsonb_build_object(
    'title', v_activity.title,
    'body', v_activity.body,
    'due_at', v_activity.due_at,
    'priority', v_activity.priority,
    'direction', v_activity.direction,
    'metadata', v_activity.metadata
  );

  v_next := jsonb_build_object(
    'title', trim(p_title),
    'body', NULLIF(trim(COALESCE(p_body, '')), ''),
    'due_at', p_due_at,
    'priority', COALESCE(p_priority, 'medium'),
    'direction', NULLIF(p_direction, ''),
    'metadata', COALESCE(p_metadata, v_activity.metadata, '{}'::jsonb)
  );

  INSERT INTO public.contact_activity_revisions (
    activity_id,
    edited_by,
    previous_payload,
    new_payload
  )
  VALUES (
    p_activity_id,
    v_actor,
    v_previous,
    v_next
  );

  UPDATE public.contact_activities
  SET title = trim(p_title),
      body = NULLIF(trim(COALESCE(p_body, '')), ''),
      due_at = p_due_at,
      priority = COALESCE(p_priority, 'medium'),
      direction = NULLIF(p_direction, ''),
      metadata = COALESCE(p_metadata, metadata, '{}'::jsonb),
      updated_at = now()
  WHERE id = p_activity_id
  RETURNING * INTO v_updated;

  IF v_updated.activity_type = 'follow_up' AND v_updated.action_item_id IS NOT NULL THEN
    UPDATE public.action_items
    SET title = v_updated.title,
        description = v_updated.body,
        priority = v_updated.priority,
        due_date = v_updated.due_at,
        updated_at = now()
    WHERE id = v_updated.action_item_id;
  END IF;

  RETURN v_updated;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_contact_activity(p_activity_id uuid)
RETURNS public.contact_activities
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity contact_activities%ROWTYPE;
  v_deleted contact_activities%ROWTYPE;
  v_actor uuid := public._contact_activity_actor();
  v_previous jsonb;
  v_deleted_at timestamptz := now();
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'authenticated user required';
  END IF;
  IF p_activity_id IS NULL THEN
    RAISE EXCEPTION 'activity_id is required';
  END IF;

  SELECT *
  INTO v_activity
  FROM public.contact_activities
  WHERE id = p_activity_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'activity not found';
  END IF;
  IF v_activity.created_by IS DISTINCT FROM v_actor THEN
    RAISE EXCEPTION 'only the activity owner can delete this activity';
  END IF;
  IF v_activity.source_type <> 'manual'
    OR v_activity.activity_type NOT IN ('call', 'follow_up', 'note', 'file') THEN
    RAISE EXCEPTION 'this activity type is read-only';
  END IF;
  IF v_activity.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'activity is already deleted';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.contact_activities next_activity
    WHERE next_activity.contact_id = v_activity.contact_id
      AND next_activity.deleted_at IS NULL
      AND (
        next_activity.occurred_at > v_activity.occurred_at
        OR (
          next_activity.occurred_at = v_activity.occurred_at
          AND next_activity.created_at > v_activity.created_at
        )
      )
  )
  OR EXISTS (
    SELECT 1
    FROM public.campaign_events next_campaign
    WHERE next_campaign.contact_id = v_activity.contact_id
      AND next_campaign.event_timestamp > v_activity.occurred_at
  ) THEN
    RAISE EXCEPTION 'activity can no longer be deleted because newer timeline activity exists';
  END IF;

  v_previous := jsonb_build_object(
    'title', v_activity.title,
    'body', v_activity.body,
    'due_at', v_activity.due_at,
    'priority', v_activity.priority,
    'direction', v_activity.direction,
    'metadata', v_activity.metadata,
    'status', v_activity.status,
    'deleted_at', v_activity.deleted_at
  );

  INSERT INTO public.contact_activity_revisions (
    activity_id,
    edited_by,
    previous_payload,
    new_payload
  )
  VALUES (
    p_activity_id,
    v_actor,
    v_previous,
    jsonb_build_object(
      'deleted_at', v_deleted_at,
      'deleted_by', v_actor,
      'status', 'cancelled'
    )
  );

  UPDATE public.contact_activities
  SET deleted_at = v_deleted_at,
      deleted_by = v_actor,
      status = 'cancelled',
      updated_at = v_deleted_at
  WHERE id = p_activity_id
  RETURNING * INTO v_deleted;

  IF v_deleted.action_item_id IS NOT NULL THEN
    UPDATE public.action_items
    SET status = 'cancelled',
        updated_at = v_deleted_at
    WHERE id = v_deleted.action_item_id
      AND status IN ('open', 'in_progress');
  END IF;

  UPDATE public.contacts c
  SET needs_follow_up = EXISTS (
    SELECT 1
    FROM public.contact_activities ca
    WHERE ca.contact_id = v_deleted.contact_id
      AND ca.deleted_at IS NULL
      AND ca.activity_type = 'follow_up'
      AND ca.status IN ('open', 'in_progress')
  ),
  updated_at = v_deleted_at
  WHERE c.id = v_deleted.contact_id;

  RETURN v_deleted;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_contact_context_manifest(p_contact_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_actor uuid := public._contact_activity_actor();
  v_manifest jsonb;
BEGIN
  IF v_actor IS NULL AND COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'authenticated user required';
  END IF;
  IF p_contact_id IS NULL THEN
    RAISE EXCEPTION 'contact_id is required';
  END IF;

  WITH conversation_stats AS (
    SELECT
      count(*)::int AS conversation_count,
      max(last_email_at) AS latest_email_at,
      coalesce(sum(coalesce(email_count_at_last_summary, 0)), 0)::int AS summarized_email_count
    FROM public.conversations
    WHERE primary_contact_id = p_contact_id
  ),
  activity_stats AS (
    SELECT
      count(*)::int AS activity_count,
      max(updated_at) AS latest_activity_at,
      count(*) FILTER (
        WHERE activity_type = 'follow_up' AND status IN ('open', 'in_progress')
      )::int AS open_follow_up_count,
      md5(coalesce(jsonb_agg(
        jsonb_build_object(
          'id', id,
          'activity_type', activity_type,
          'title', title,
          'body', body,
          'status', status,
          'priority', priority,
          'direction', direction,
          'due_at', due_at,
          'completed_at', completed_at,
          'deleted_at', deleted_at,
          'updated_at', updated_at,
          'metadata', metadata
        )
        ORDER BY updated_at DESC, id
      )::text, '[]')) AS activity_fingerprint
    FROM public.contact_activities
    WHERE contact_id = p_contact_id
  ),
  attachment_stats AS (
    SELECT
      count(a.*)::int AS attachment_count,
      md5(coalesce(jsonb_agg(
        jsonb_build_object(
          'id', a.id,
          'activity_id', a.activity_id,
          'storage_path', a.storage_path,
          'file_name', a.file_name,
          'content_type', a.content_type,
          'file_size', a.file_size,
          'created_at', a.created_at
        )
        ORDER BY a.created_at DESC, a.id
      )::text, '[]')) AS attachment_fingerprint
    FROM public.contact_activity_attachments a
    JOIN public.contact_activities ca ON ca.id = a.activity_id
    WHERE ca.contact_id = p_contact_id
  ),
  campaign_stats AS (
    SELECT
      count(*)::int AS campaign_event_count,
      max(event_timestamp) AS latest_campaign_at,
      md5(coalesce(jsonb_agg(
        jsonb_build_object(
          'id', id,
          'event_type', event_type,
          'event_timestamp', event_timestamp,
          'score', score,
          'campaign_id', campaign_id
        )
        ORDER BY event_timestamp DESC, id
      )::text, '[]')) AS campaign_fingerprint
    FROM public.campaign_events
    WHERE contact_id = p_contact_id
  )
  SELECT jsonb_build_object(
    'contact_id', p_contact_id,
    'latest_email_at', conversation_stats.latest_email_at,
    'latest_activity_at', activity_stats.latest_activity_at,
    'latest_campaign_at', campaign_stats.latest_campaign_at,
    'conversation_count', conversation_stats.conversation_count,
    'activity_count', activity_stats.activity_count,
    'attachment_count', attachment_stats.attachment_count,
    'campaign_event_count', campaign_stats.campaign_event_count,
    'open_follow_up_count', activity_stats.open_follow_up_count,
    'summarized_email_count', conversation_stats.summarized_email_count,
    'activity_fingerprint', activity_stats.activity_fingerprint,
    'attachment_fingerprint', attachment_stats.attachment_fingerprint,
    'campaign_fingerprint', campaign_stats.campaign_fingerprint,
    'context_hash', md5(
      concat_ws(
        '|',
        p_contact_id::text,
        coalesce(conversation_stats.latest_email_at::text, ''),
        coalesce(activity_stats.latest_activity_at::text, ''),
        coalesce(campaign_stats.latest_campaign_at::text, ''),
        conversation_stats.summarized_email_count::text,
        activity_stats.activity_count::text,
        activity_stats.open_follow_up_count::text,
        coalesce(activity_stats.activity_fingerprint, ''),
        attachment_stats.attachment_count::text,
        coalesce(attachment_stats.attachment_fingerprint, ''),
        campaign_stats.campaign_event_count::text,
        coalesce(campaign_stats.campaign_fingerprint, '')
      )
    )
  )
  INTO v_manifest
  FROM conversation_stats, activity_stats, attachment_stats, campaign_stats;

  RETURN v_manifest;
END;
$$;

DROP FUNCTION IF EXISTS public.get_contact_timeline(uuid, text, timestamptz, integer);
CREATE OR REPLACE FUNCTION public.get_contact_timeline(
  p_contact_id uuid,
  p_activity_type text DEFAULT NULL,
  p_cursor timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 50
)
RETURNS TABLE(
  id text,
  source_type text,
  activity_type text,
  title text,
  body text,
  occurred_at timestamptz,
  due_at timestamptz,
  status text,
  priority text,
  direction text,
  author_name text,
  created_by uuid,
  can_edit boolean,
  can_delete boolean,
  edited_at timestamptz,
  has_revisions boolean,
  metadata jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_actor uuid := public._contact_activity_actor();
BEGIN
  IF v_actor IS NULL AND COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'authenticated user required';
  END IF;
  IF p_contact_id IS NULL THEN
    RAISE EXCEPTION 'contact_id is required';
  END IF;

  RETURN QUERY
  WITH activity_rows AS (
    SELECT
      ca.id::text AS id,
      ca.source_type,
      ca.activity_type,
      ca.title,
      ca.body,
      ca.occurred_at,
      ca.due_at,
      ca.status,
      ca.priority,
      ca.direction,
      coalesce(p.full_name, 'Team') AS author_name,
      ca.created_by,
      (
        ca.created_by = auth.uid()
        AND ca.source_type = 'manual'
        AND ca.activity_type IN ('call', 'follow_up', 'note', 'file')
        AND NOT COALESCE(lock_state.has_next_activity, false)
      ) AS can_edit,
      (
        ca.created_by = auth.uid()
        AND ca.source_type = 'manual'
        AND ca.activity_type IN ('call', 'follow_up', 'note', 'file')
        AND NOT COALESCE(lock_state.has_next_activity, false)
      ) AS can_delete,
      rev.edited_at,
      COALESCE(rev.revision_count, 0) > 0 AS has_revisions,
      ca.metadata || jsonb_build_object(
        'activity_id', ca.id,
        'attachment_count', (
          SELECT count(*)
          FROM public.contact_activity_attachments a
          WHERE a.activity_id = ca.id
        ),
        'attachments', (
          SELECT COALESCE(
            jsonb_agg(
              jsonb_build_object(
                'id', a.id,
                'file_name', a.file_name,
                'content_type', a.content_type,
                'file_size', a.file_size,
                'storage_bucket', a.storage_bucket,
                'storage_path', a.storage_path,
                'created_at', a.created_at
              )
              ORDER BY a.created_at ASC
            ),
            '[]'::jsonb
          )
          FROM public.contact_activity_attachments a
          WHERE a.activity_id = ca.id
        )
      ) AS metadata
    FROM public.contact_activities ca
    LEFT JOIN public.profiles p ON p.auth_user_id = ca.created_by
    LEFT JOIN LATERAL (
      SELECT
        max(car.edited_at) AS edited_at,
        count(*)::int AS revision_count
      FROM public.contact_activity_revisions car
      WHERE car.activity_id = ca.id
    ) rev ON true
    LEFT JOIN LATERAL (
      SELECT (
        EXISTS (
          SELECT 1
          FROM public.contact_activities next_activity
          WHERE next_activity.contact_id = ca.contact_id
            AND next_activity.deleted_at IS NULL
            AND (
              next_activity.occurred_at > ca.occurred_at
              OR (
                next_activity.occurred_at = ca.occurred_at
                AND next_activity.created_at > ca.created_at
              )
            )
        )
        OR EXISTS (
          SELECT 1
          FROM public.campaign_events next_campaign
          WHERE next_campaign.contact_id = ca.contact_id
            AND next_campaign.event_timestamp > ca.occurred_at
        )
      ) AS has_next_activity
    ) lock_state ON true
    WHERE ca.contact_id = p_contact_id
      AND ca.deleted_at IS NULL
      AND (p_activity_type IS NULL OR ca.activity_type = p_activity_type)
      AND (p_cursor IS NULL OR ca.occurred_at < p_cursor)
  ),
  campaign_rows AS (
    SELECT
      ce.id::text AS id,
      'campaign'::text AS source_type,
      'campaign'::text AS activity_type,
      initcap(replace(coalesce(ce.event_type::text, 'campaign_event'), '_', ' ')) AS title,
      coalesce(c.name, c.subject, 'Campaign engagement') AS body,
      ce.event_timestamp AS occurred_at,
      NULL::timestamptz AS due_at,
      'completed'::text AS status,
      'medium'::text AS priority,
      NULL::text AS direction,
      'System'::text AS author_name,
      NULL::uuid AS created_by,
      false AS can_edit,
      false AS can_delete,
      NULL::timestamptz AS edited_at,
      false AS has_revisions,
      jsonb_build_object(
        'campaign_id', ce.campaign_id,
        'score', ce.score,
        'event_type', ce.event_type::text,
        'subject', c.subject
      ) AS metadata
    FROM public.campaign_events ce
    LEFT JOIN public.campaigns c ON c.id = ce.campaign_id
    WHERE ce.contact_id = p_contact_id
      AND (p_activity_type IS NULL OR p_activity_type = 'campaign')
      AND (p_cursor IS NULL OR ce.event_timestamp < p_cursor)
  )
  SELECT
    r.id,
    r.source_type,
    r.activity_type,
    r.title,
    r.body,
    r.occurred_at,
    r.due_at,
    r.status,
    r.priority,
    r.direction,
    r.author_name,
    r.created_by,
    r.can_edit,
    r.can_delete,
    r.edited_at,
    r.has_revisions,
    r.metadata
  FROM (
    SELECT * FROM activity_rows
    UNION ALL
    SELECT * FROM campaign_rows
  ) r
  ORDER BY r.occurred_at DESC NULLS LAST
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_hot_leads_workbench(
  p_search text DEFAULT NULL,
  p_needs_follow_up boolean DEFAULT false,
  p_page integer DEFAULT 1,
  p_page_size integer DEFAULT 25
)
RETURNS TABLE(
  contact_id uuid,
  email text,
  first_name text,
  last_name text,
  phone text,
  organization_id uuid,
  organization_name text,
  organization_state text,
  total_score integer,
  campaign_score integer,
  workflow_score integer,
  tier text,
  reasons jsonb,
  open_follow_up_count integer,
  latest_activity jsonb,
  engagement_summary text,
  engagement_summary_at timestamptz,
  engagement_action_items text[],
  summary_stale boolean,
  latest_call_plan jsonb,
  call_plan_stale boolean,
  last_active_at timestamptz,
  total_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_actor uuid := public._contact_activity_actor();
BEGIN
  IF v_actor IS NULL AND COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'authenticated user required';
  END IF;

  RETURN QUERY
  WITH campaign_scores AS (
    SELECT
      contact_id,
      coalesce(sum(total_score), 0)::int AS campaign_score,
      max(last_event_at) AS latest_campaign_at,
      count(*) FILTER (WHERE opened)::int AS total_opens,
      count(*) FILTER (WHERE clicked)::int AS total_clicks
    FROM public.campaign_contact_summary
    GROUP BY contact_id
  ),
  activity_stats AS (
    SELECT
      contact_id,
      count(*) FILTER (WHERE activity_type = 'follow_up' AND status IN ('open', 'in_progress'))::int AS open_follow_up_count,
      min(due_at) FILTER (WHERE activity_type = 'follow_up' AND status IN ('open', 'in_progress')) AS next_follow_up_at,
      max(updated_at) AS latest_activity_updated_at,
      max(occurred_at) AS latest_activity_at
    FROM public.contact_activities
    WHERE deleted_at IS NULL
    GROUP BY contact_id
  ),
  latest_activity AS (
    SELECT DISTINCT ON (contact_id)
      contact_id,
      jsonb_build_object(
        'id', id,
        'activity_type', activity_type,
        'title', title,
        'body', body,
        'status', status,
        'priority', priority,
        'occurred_at', occurred_at,
        'due_at', due_at
      ) AS payload
    FROM public.contact_activities
    WHERE deleted_at IS NULL
    ORDER BY contact_id, occurred_at DESC
  ),
  latest_plan AS (
    SELECT DISTINCT ON (contact_id)
      contact_id,
      generated_at,
      context_hash,
      jsonb_build_object(
        'id', id,
        'opener', opener,
        'objective', objective,
        'talking_points', talking_points,
        'questions', questions,
        'likely_objections', likely_objections,
        'next_step', next_step,
        'after_call_prompt', after_call_prompt,
        'instruction', instruction,
        'generated_at', generated_at
      ) AS payload
    FROM public.contact_call_plans
    WHERE status = 'active'
    ORDER BY contact_id, generated_at DESC
  ),
  base AS (
    SELECT
      c.id AS contact_id,
      c.email::text,
      c.first_name::text,
      c.last_name::text,
      c.phone::text,
      c.organization_id,
      o.name::text AS organization_name,
      o.state::text AS organization_state,
      coalesce(cs.campaign_score, 0) AS campaign_score,
      coalesce(c.lead_score, 0) AS workflow_score,
      coalesce(ast.open_follow_up_count, 0) AS open_follow_up_count,
      ast.next_follow_up_at,
      greatest(
        coalesce(cs.latest_campaign_at, '-infinity'::timestamptz),
        coalesce(ast.latest_activity_at, '-infinity'::timestamptz),
        coalesce(c.last_contact_date, '-infinity'::timestamptz),
        coalesce(c.updated_at, '-infinity'::timestamptz)
      ) AS last_active_at,
      ast.latest_activity_updated_at,
      la.payload AS latest_activity,
      lp.payload AS latest_call_plan,
      lp.generated_at AS latest_plan_at,
      c.engagement_summary::text,
      c.engagement_summary_at,
      c.engagement_action_items,
      coalesce(c.lead_classification, 'cold')::text AS lead_classification,
      coalesce(c.lead_classification_locked, false) AS lead_classification_locked,
      coalesce(o.is_host, false) AS is_host
    FROM public.contacts c
    LEFT JOIN public.organizations o ON o.id = c.organization_id
    LEFT JOIN campaign_scores cs ON cs.contact_id = c.id
    LEFT JOIN activity_stats ast ON ast.contact_id = c.id
    LEFT JOIN latest_activity la ON la.contact_id = c.id
    LEFT JOIN latest_plan lp ON lp.contact_id = c.id
  ),
  scored AS (
    SELECT
      *,
      (campaign_score + workflow_score +
        CASE
          WHEN open_follow_up_count > 0 AND next_follow_up_at <= now() THEN 25
          WHEN open_follow_up_count > 0 THEN 15
          ELSE 0
        END
      )::int AS total_score
    FROM base
    WHERE NOT is_host
      AND (
        campaign_score > 0
        OR workflow_score > 0
        OR open_follow_up_count > 0
        OR lead_classification_locked
      )
      AND (
        p_search IS NULL
        OR NULLIF(trim(p_search), '') IS NULL
        OR email ILIKE '%' || trim(p_search) || '%'
        OR first_name ILIKE '%' || trim(p_search) || '%'
        OR last_name ILIKE '%' || trim(p_search) || '%'
        OR organization_name ILIKE '%' || trim(p_search) || '%'
      )
      AND (
        NOT p_needs_follow_up
        OR open_follow_up_count > 0
      )
  ),
  final_rows AS (
    SELECT
      *,
      CASE
        WHEN lead_classification_locked THEN upper(lead_classification)
        WHEN total_score >= 70 THEN 'HOT'
        WHEN total_score >= 40 THEN 'WARM'
        WHEN total_score >= 5 THEN 'ACTIVE'
        ELSE 'COLD'
      END AS tier,
      jsonb_strip_nulls(jsonb_build_object(
        'follow_up', CASE WHEN open_follow_up_count > 0 THEN 'Follow-up open' END,
        'due', CASE WHEN next_follow_up_at IS NOT NULL AND next_follow_up_at <= now() THEN 'Due now' END,
        'campaign', CASE WHEN campaign_score > 0 THEN 'Campaign engagement' END,
        'workflow', CASE WHEN workflow_score > 0 THEN 'Workflow score' END,
        'manual', CASE WHEN lead_classification_locked THEN 'Manual classification' END
      )) AS reasons,
      (latest_activity_updated_at IS NOT NULL AND (engagement_summary_at IS NULL OR latest_activity_updated_at > engagement_summary_at)) AS summary_stale,
      (latest_activity_updated_at IS NOT NULL AND (latest_plan_at IS NULL OR latest_activity_updated_at > latest_plan_at)) AS call_plan_stale
    FROM scored
  )
  SELECT
    fr.contact_id,
    fr.email,
    fr.first_name,
    fr.last_name,
    fr.phone,
    fr.organization_id,
    fr.organization_name,
    fr.organization_state,
    fr.total_score,
    fr.campaign_score,
    fr.workflow_score,
    fr.tier,
    fr.reasons,
    fr.open_follow_up_count,
    fr.latest_activity,
    fr.engagement_summary,
    fr.engagement_summary_at,
    fr.engagement_action_items,
    fr.summary_stale,
    fr.latest_call_plan,
    fr.call_plan_stale,
    NULLIF(fr.last_active_at, '-infinity'::timestamptz) AS last_active_at,
    count(*) OVER () AS total_count
  FROM final_rows fr
  ORDER BY
    CASE WHEN fr.open_follow_up_count > 0 THEN 0 ELSE 1 END,
    coalesce(fr.next_follow_up_at, 'infinity'::timestamptz),
    fr.total_score DESC,
    fr.last_active_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_page_size, 25), 1), 100)
  OFFSET GREATEST(COALESCE(p_page, 1) - 1, 0) * LEAST(GREATEST(COALESCE(p_page_size, 25), 1), 100);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_active_contact_call_plan(p_contact_id uuid)
RETURNS public.contact_call_plans
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := public._contact_activity_actor();
  v_plan contact_call_plans%ROWTYPE;
BEGIN
  IF v_actor IS NULL AND COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'authenticated user required';
  END IF;
  IF p_contact_id IS NULL THEN
    RAISE EXCEPTION 'contact_id is required';
  END IF;

  SELECT *
  INTO v_plan
  FROM public.contact_call_plans
  WHERE contact_id = p_contact_id
    AND status = 'active'
  ORDER BY generated_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  RETURN v_plan;
END;
$$;

CREATE OR REPLACE FUNCTION public.replace_active_contact_call_plan(
  p_contact_id uuid,
  p_context_snapshot_id uuid,
  p_context_hash text,
  p_instruction text,
  p_opener text,
  p_objective text,
  p_talking_points text[] DEFAULT '{}',
  p_questions text[] DEFAULT '{}',
  p_likely_objections text[] DEFAULT '{}',
  p_next_step text DEFAULT NULL,
  p_after_call_prompt text DEFAULT NULL,
  p_model text DEFAULT NULL,
  p_tokens_input integer DEFAULT 0,
  p_tokens_output integer DEFAULT 0
)
RETURNS public.contact_call_plans
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan contact_call_plans%ROWTYPE;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'service role required';
  END IF;
  IF p_contact_id IS NULL THEN
    RAISE EXCEPTION 'contact_id is required';
  END IF;

  INSERT INTO public.contact_call_plans (
    contact_id,
    context_snapshot_id,
    context_hash,
    instruction,
    opener,
    objective,
    talking_points,
    questions,
    likely_objections,
    next_step,
    after_call_prompt,
    status,
    model,
    tokens_input,
    tokens_output
  )
  VALUES (
    p_contact_id,
    p_context_snapshot_id,
    p_context_hash,
    NULLIF(trim(COALESCE(p_instruction, '')), ''),
    NULLIF(trim(COALESCE(p_opener, '')), ''),
    NULLIF(trim(COALESCE(p_objective, '')), ''),
    COALESCE(p_talking_points, '{}'),
    COALESCE(p_questions, '{}'),
    COALESCE(p_likely_objections, '{}'),
    NULLIF(trim(COALESCE(p_next_step, '')), ''),
    NULLIF(trim(COALESCE(p_after_call_prompt, '')), ''),
    'active',
    NULLIF(trim(COALESCE(p_model, '')), ''),
    GREATEST(COALESCE(p_tokens_input, 0), 0),
    GREATEST(COALESCE(p_tokens_output, 0), 0)
  )
  RETURNING * INTO v_plan;

  UPDATE public.contact_call_plans
  SET status = 'superseded',
      superseded_by = v_plan.id
  WHERE contact_id = p_contact_id
    AND status = 'active'
    AND id <> v_plan.id;

  RETURN v_plan;
END;
$$;

-- Best-effort backfill from the legacy contact follow-up fields. This preserves
-- existing operator intent while moving the actual workflow into the timeline.
INSERT INTO public.contact_activities (
  contact_id,
  organization_id,
  activity_type,
  title,
  body,
  status,
  priority,
  occurred_at,
  due_at,
  visibility,
  source_type,
  metadata
)
SELECT
  c.id,
  c.organization_id,
  'follow_up',
  'Follow-up',
  NULLIF(coalesce(c.custom_fields->>'followup_action', c.custom_fields->>'Followup Action', ''), ''),
  'open',
  'medium',
  coalesce(c.updated_at, now()),
  CASE
    WHEN coalesce(c.custom_fields->>'followup_date', c.custom_fields->>'Followup Date', '') ~ '^\d{4}-\d{2}-\d{2}'
      THEN (coalesce(c.custom_fields->>'followup_date', c.custom_fields->>'Followup Date'))::timestamptz
    ELSE NULL
  END,
  'team',
  'legacy_follow_up',
  jsonb_build_object('legacy_custom_fields', c.custom_fields)
FROM public.contacts c
WHERE coalesce(c.needs_follow_up, false)
  AND NOT EXISTS (
    SELECT 1
    FROM public.contact_activities ca
    WHERE ca.contact_id = c.id
      AND ca.source_type = 'legacy_follow_up'
  );

REVOKE EXECUTE ON FUNCTION public.create_contact_activity(uuid, text, text, text, text, text, text, timestamptz, timestamptz, uuid, text, jsonb, boolean) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.create_file_contact_activity(uuid, text, text, text, text, text, bigint, jsonb) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.complete_contact_follow_up(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.update_contact_activity(uuid, text, text, timestamptz, text, text, jsonb) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.delete_contact_activity(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_contact_context_manifest(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_contact_timeline(uuid, text, timestamptz, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_hot_leads_workbench(text, boolean, integer, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_active_contact_call_plan(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.replace_active_contact_call_plan(uuid, uuid, text, text, text, text, text[], text[], text[], text, text, text, integer, integer) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.create_contact_activity(uuid, text, text, text, text, text, text, timestamptz, timestamptz, uuid, text, jsonb, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_file_contact_activity(uuid, text, text, text, text, text, bigint, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_contact_follow_up(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_contact_activity(uuid, text, text, timestamptz, text, text, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.delete_contact_activity(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_contact_context_manifest(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_contact_timeline(uuid, text, timestamptz, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_hot_leads_workbench(text, boolean, integer, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_active_contact_call_plan(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.replace_active_contact_call_plan(uuid, uuid, text, text, text, text, text[], text[], text[], text, text, text, integer, integer) TO service_role;

COMMENT ON TABLE public.contact_activities IS
  'Canonical contact timeline for calls, follow-ups, notes, files, meetings, system, campaign, and email events.';
COMMENT ON TABLE public.contact_call_plans IS
  'Revisioned AI call plans generated from contact context packages.';
