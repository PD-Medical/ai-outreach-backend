-- Canonical email messages cutover.
--
-- The old `emails` table represented both the real email and the mailbox copy
-- where that email was observed. The canonical model keeps the current row IDs
-- as mailbox-copy IDs by renaming `emails` to `email_mailbox_copies`, then adds
-- `email_messages` as the content/message source of truth.

DROP VIEW IF EXISTS public.v_email_activity CASCADE;

ALTER TABLE IF EXISTS public.emails
  RENAME TO email_mailbox_copies;

ALTER TABLE public.email_mailbox_copies
  ADD COLUMN IF NOT EXISTS email_message_id uuid;

ALTER TABLE public.email_mailbox_copies
  DROP CONSTRAINT IF EXISTS emails_unique_message_id;

COMMENT ON TABLE public.email_mailbox_copies IS
  'One row per mailbox/folder/UID copy of an email. The id is the copy/source id used by imports, drafts, replies, and activity diagnostics.';

COMMENT ON COLUMN public.email_mailbox_copies.message_id IS
  'Mirrored RFC Message-ID retained for rollback/compatibility. It is intentionally non-unique across mailbox copies.';

CREATE TABLE IF NOT EXISTS public.email_messages (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  message_key text NOT NULL,
  message_id character varying,
  thread_id character varying NOT NULL,
  conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
  in_reply_to character varying,
  email_references text,
  subject character varying,
  from_email character varying NOT NULL,
  from_name character varying,
  to_emails text[] NOT NULL DEFAULT '{}',
  cc_emails text[] DEFAULT '{}',
  bcc_emails text[] DEFAULT '{}',
  body_html text,
  body_plain text,
  body_clean text,
  contact_id uuid REFERENCES public.contacts(id) ON DELETE SET NULL,
  organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL,
  headers jsonb DEFAULT '{}'::jsonb,
  attachments jsonb DEFAULT '[]'::jsonb,
  sent_at timestamptz,
  received_at timestamptz NOT NULL,
  needs_parsing boolean DEFAULT false,
  intent character varying,
  email_category character varying,
  sentiment character varying,
  priority_score integer,
  spam_score numeric(3,2),
  ai_processed_at timestamptz,
  ai_model_version character varying,
  ai_confidence_score numeric(3,2),
  enrichment_status text DEFAULT 'pending'
    CHECK (enrichment_status IN ('pending', 'enriched', 'failed', 'rate_limited', 'skipped')),
  enriched_at timestamptz,
  last_enrichment_error text,
  message_kind public.email_message_kind NOT NULL DEFAULT 'human',
  is_internal boolean NOT NULL DEFAULT false,
  mailchimp_newsletter_id uuid REFERENCES public.mailchimp_newsletters(id) ON DELETE SET NULL,
  mailchimp_match_method text,
  mailchimp_match_confidence numeric(4,3),
  mailchimp_match_reason text,
  auth_user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  workflow_matched_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT email_messages_message_key_unique UNIQUE (message_key),
  CONSTRAINT email_messages_ai_confidence_check CHECK (
    ai_confidence_score IS NULL OR (ai_confidence_score >= 0 AND ai_confidence_score <= 1)
  ),
  CONSTRAINT email_messages_priority_score_check CHECK (
    priority_score IS NULL OR (priority_score >= 0 AND priority_score <= 100)
  ),
  CONSTRAINT email_messages_spam_score_check CHECK (
    spam_score IS NULL OR (spam_score >= 0 AND spam_score <= 1)
  )
);

ALTER TABLE public.email_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS email_messages_select_policy ON public.email_messages;
CREATE POLICY email_messages_select_policy
  ON public.email_messages FOR SELECT
  USING (public.has_permission('view_emails'::text));

DROP POLICY IF EXISTS email_messages_insert_policy ON public.email_messages;
CREATE POLICY email_messages_insert_policy
  ON public.email_messages FOR INSERT TO service_role
  WITH CHECK (true);

DROP POLICY IF EXISTS email_messages_update_policy ON public.email_messages;
CREATE POLICY email_messages_update_policy
  ON public.email_messages FOR UPDATE TO service_role
  USING (true);

DROP POLICY IF EXISTS email_messages_delete_policy ON public.email_messages;
CREATE POLICY email_messages_delete_policy
  ON public.email_messages FOR DELETE
  USING (public.is_admin());

CREATE INDEX IF NOT EXISTS idx_email_messages_message_id
  ON public.email_messages (message_id)
  WHERE message_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_email_messages_thread_id
  ON public.email_messages (thread_id);
CREATE INDEX IF NOT EXISTS idx_email_messages_conversation_id
  ON public.email_messages (conversation_id);
CREATE INDEX IF NOT EXISTS idx_email_messages_received_at
  ON public.email_messages (received_at DESC);
CREATE INDEX IF NOT EXISTS idx_email_messages_contact_id
  ON public.email_messages (contact_id);
CREATE INDEX IF NOT EXISTS idx_email_messages_organization_id
  ON public.email_messages (organization_id);
CREATE INDEX IF NOT EXISTS idx_email_messages_category
  ON public.email_messages (email_category)
  WHERE email_category IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_email_messages_enrichment_pending
  ON public.email_messages (created_at)
  WHERE enrichment_status = 'pending';
CREATE INDEX IF NOT EXISTS idx_email_messages_enrichment_failed
  ON public.email_messages (enriched_at DESC NULLS LAST)
  WHERE enrichment_status = 'failed';
CREATE INDEX IF NOT EXISTS idx_email_messages_message_kind
  ON public.email_messages (message_kind)
  WHERE message_kind <> 'human';
CREATE INDEX IF NOT EXISTS idx_email_messages_is_internal_received_at
  ON public.email_messages (is_internal, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_email_messages_mailchimp_newsletter_id
  ON public.email_messages (mailchimp_newsletter_id)
  WHERE mailchimp_newsletter_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS email_messages_search_gin
  ON public.email_messages USING gin (
    (
      lower(
        coalesce(subject, '') || ' ' ||
        coalesce(from_email, '') || ' ' ||
        coalesce(from_name, '') || ' ' ||
        array_to_string(coalesce(to_emails, '{}'), ' ') || ' ' ||
        array_to_string(coalesce(cc_emails, '{}'), ' ') || ' ' ||
        array_to_string(coalesce(bcc_emails, '{}'), ' ') || ' ' ||
        coalesce(body_clean, '')
      )
    ) gin_trgm_ops
  );

CREATE INDEX IF NOT EXISTS idx_email_mailbox_copies_message_id
  ON public.email_mailbox_copies (email_message_id);
CREATE INDEX IF NOT EXISTS idx_email_mailbox_copies_message_mailbox
  ON public.email_mailbox_copies (email_message_id, mailbox_id);
CREATE INDEX IF NOT EXISTS idx_email_mailbox_copies_mailbox_folder_uid
  ON public.email_mailbox_copies (mailbox_id, imap_folder, imap_uid);
CREATE INDEX IF NOT EXISTS idx_email_mailbox_copies_mailbox_received
  ON public.email_mailbox_copies (mailbox_id, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_email_mailbox_copies_direction
  ON public.email_mailbox_copies (direction);

ALTER TABLE public.email_mailbox_copies
  DROP CONSTRAINT IF EXISTS email_mailbox_copies_email_message_id_fkey;

ALTER TABLE public.email_mailbox_copies
  ADD CONSTRAINT email_mailbox_copies_email_message_id_fkey
  FOREIGN KEY (email_message_id) REFERENCES public.email_messages(id) ON DELETE CASCADE;

ALTER TABLE public.workflow_executions
  ADD COLUMN IF NOT EXISTS email_message_id uuid REFERENCES public.email_messages(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_workflow_executions_email_message
  ON public.workflow_executions (email_message_id);

CREATE UNIQUE INDEX IF NOT EXISTS workflow_executions_unique_workflow_message
  ON public.workflow_executions (workflow_id, email_message_id)
  WHERE email_message_id IS NOT NULL;

ALTER TABLE public.email_drafts
  ADD COLUMN IF NOT EXISTS source_email_message_id uuid REFERENCES public.email_messages(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS sent_email_message_id uuid REFERENCES public.email_messages(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_email_drafts_source_email_message
  ON public.email_drafts (source_email_message_id)
  WHERE source_email_message_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_email_drafts_sent_email_message
  ON public.email_drafts (sent_email_message_id)
  WHERE sent_email_message_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.normalize_email_message_id(p_message_id text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(lower(trim(both '<>' from btrim(coalesce(p_message_id, '')))), '');
$$;

CREATE OR REPLACE FUNCTION public.email_message_key(
  p_message_id text,
  p_mailbox_id uuid,
  p_imap_folder text,
  p_imap_uid integer
)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN public.normalize_email_message_id(p_message_id) IS NOT NULL
      THEN 'rfc:' || public.normalize_email_message_id(p_message_id)
    ELSE 'copy:' || p_mailbox_id::text || ':' || coalesce(p_imap_folder, '') || ':' || coalesce(p_imap_uid::text, '')
  END;
$$;

CREATE OR REPLACE FUNCTION public.set_email_messages_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_email_messages_updated_at ON public.email_messages;
CREATE TRIGGER set_email_messages_updated_at
  BEFORE UPDATE ON public.email_messages
  FOR EACH ROW EXECUTE FUNCTION public.set_email_messages_updated_at();

CREATE OR REPLACE FUNCTION public.trigger_workflow_matching_for_message(p_email_message_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_email_message_copy(
  message_payload jsonb,
  copy_payload jsonb
)
RETURNS TABLE(email_message_id uuid, mailbox_copy_id uuid, copy_created boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_message_id text := NULLIF(coalesce(message_payload->>'message_id', copy_payload->>'message_id'), '');
  v_mailbox_id uuid := NULLIF(copy_payload->>'mailbox_id', '')::uuid;
  v_folder text := copy_payload->>'imap_folder';
  v_uid integer := NULLIF(copy_payload->>'imap_uid', '')::integer;
  v_existing_copy_id uuid;
  v_copy_id uuid := coalesce(NULLIF(copy_payload->>'id', '')::uuid, gen_random_uuid());
  v_message_key text := CASE
    WHEN public.normalize_email_message_id(v_message_id) IS NOT NULL
      THEN 'rfc:' || public.normalize_email_message_id(v_message_id)
    WHEN v_uid IS NOT NULL
      THEN public.email_message_key(v_message_id, v_mailbox_id, v_folder, v_uid)
    ELSE 'copy:' || v_copy_id::text
  END;
BEGIN
  INSERT INTO public.email_messages (
    message_key, message_id, thread_id, conversation_id, in_reply_to, email_references,
    subject, from_email, from_name, to_emails, cc_emails, bcc_emails, body_html,
    body_plain, body_clean, contact_id, organization_id, headers, attachments,
    sent_at, received_at, needs_parsing, intent, email_category, sentiment,
    priority_score, spam_score, ai_processed_at, ai_model_version, ai_confidence_score,
    enrichment_status, enriched_at, last_enrichment_error, message_kind, is_internal,
    mailchimp_newsletter_id, mailchimp_match_method, mailchimp_match_confidence,
    mailchimp_match_reason, auth_user_id, workflow_matched_at
  )
  VALUES (
    v_message_key,
    public.normalize_email_message_id(v_message_id),
    coalesce(message_payload->>'thread_id', copy_payload->>'thread_id'),
    NULLIF(coalesce(message_payload->>'conversation_id', copy_payload->>'conversation_id'), '')::uuid,
    NULLIF(coalesce(message_payload->>'in_reply_to', copy_payload->>'in_reply_to'), ''),
    NULLIF(coalesce(message_payload->>'email_references', copy_payload->>'email_references'), ''),
    NULLIF(coalesce(message_payload->>'subject', copy_payload->>'subject'), ''),
    coalesce(message_payload->>'from_email', copy_payload->>'from_email'),
    NULLIF(coalesce(message_payload->>'from_name', copy_payload->>'from_name'), ''),
    ARRAY(SELECT jsonb_array_elements_text(coalesce(message_payload->'to_emails', copy_payload->'to_emails', '[]'::jsonb))),
    ARRAY(SELECT jsonb_array_elements_text(coalesce(message_payload->'cc_emails', copy_payload->'cc_emails', '[]'::jsonb))),
    ARRAY(SELECT jsonb_array_elements_text(coalesce(message_payload->'bcc_emails', copy_payload->'bcc_emails', '[]'::jsonb))),
    coalesce(message_payload->>'body_html', copy_payload->>'body_html'),
    coalesce(message_payload->>'body_plain', copy_payload->>'body_plain'),
    coalesce(message_payload->>'body_clean', copy_payload->>'body_clean'),
    NULLIF(coalesce(message_payload->>'contact_id', copy_payload->>'contact_id'), '')::uuid,
    NULLIF(coalesce(message_payload->>'organization_id', copy_payload->>'organization_id'), '')::uuid,
    coalesce(message_payload->'headers', copy_payload->'headers', '{}'::jsonb),
    coalesce(message_payload->'attachments', copy_payload->'attachments', '[]'::jsonb),
    NULLIF(coalesce(message_payload->>'sent_at', copy_payload->>'sent_at'), '')::timestamptz,
    coalesce(NULLIF(message_payload->>'received_at', ''), NULLIF(copy_payload->>'received_at', ''))::timestamptz,
    coalesce((message_payload->>'needs_parsing')::boolean, (copy_payload->>'needs_parsing')::boolean, false),
    NULLIF(coalesce(message_payload->>'intent', copy_payload->>'intent'), ''),
    NULLIF(coalesce(message_payload->>'email_category', copy_payload->>'email_category'), ''),
    NULLIF(coalesce(message_payload->>'sentiment', copy_payload->>'sentiment'), ''),
    NULLIF(coalesce(message_payload->>'priority_score', copy_payload->>'priority_score'), '')::integer,
    NULLIF(coalesce(message_payload->>'spam_score', copy_payload->>'spam_score'), '')::numeric,
    NULLIF(coalesce(message_payload->>'ai_processed_at', copy_payload->>'ai_processed_at'), '')::timestamptz,
    NULLIF(coalesce(message_payload->>'ai_model_version', copy_payload->>'ai_model_version'), ''),
    NULLIF(coalesce(message_payload->>'ai_confidence_score', copy_payload->>'ai_confidence_score'), '')::numeric,
    coalesce(NULLIF(message_payload->>'enrichment_status', ''), NULLIF(copy_payload->>'enrichment_status', ''), 'pending'),
    NULLIF(coalesce(message_payload->>'enriched_at', copy_payload->>'enriched_at'), '')::timestamptz,
    NULLIF(coalesce(message_payload->>'last_enrichment_error', copy_payload->>'last_enrichment_error'), ''),
    coalesce(NULLIF(message_payload->>'message_kind', ''), NULLIF(copy_payload->>'message_kind', ''), 'human')::public.email_message_kind,
    coalesce((message_payload->>'is_internal')::boolean, (copy_payload->>'is_internal')::boolean, false),
    NULLIF(coalesce(message_payload->>'mailchimp_newsletter_id', copy_payload->>'mailchimp_newsletter_id'), '')::uuid,
    NULLIF(coalesce(message_payload->>'mailchimp_match_method', copy_payload->>'mailchimp_match_method'), ''),
    NULLIF(coalesce(message_payload->>'mailchimp_match_confidence', copy_payload->>'mailchimp_match_confidence'), '')::numeric,
    NULLIF(coalesce(message_payload->>'mailchimp_match_reason', copy_payload->>'mailchimp_match_reason'), ''),
    NULLIF(coalesce(message_payload->>'auth_user_id', copy_payload->>'auth_user_id'), '')::uuid,
    NULLIF(coalesce(message_payload->>'workflow_matched_at', copy_payload->>'workflow_matched_at'), '')::timestamptz
  )
  ON CONFLICT (message_key) DO UPDATE SET
    thread_id = coalesce(EXCLUDED.thread_id, public.email_messages.thread_id),
    conversation_id = coalesce(EXCLUDED.conversation_id, public.email_messages.conversation_id),
    in_reply_to = coalesce(EXCLUDED.in_reply_to, public.email_messages.in_reply_to),
    email_references = coalesce(EXCLUDED.email_references, public.email_messages.email_references),
    subject = coalesce(EXCLUDED.subject, public.email_messages.subject),
    from_email = coalesce(EXCLUDED.from_email, public.email_messages.from_email),
    from_name = coalesce(EXCLUDED.from_name, public.email_messages.from_name),
    to_emails = CASE WHEN cardinality(EXCLUDED.to_emails) > 0 THEN EXCLUDED.to_emails ELSE public.email_messages.to_emails END,
    cc_emails = CASE WHEN cardinality(EXCLUDED.cc_emails) > 0 THEN EXCLUDED.cc_emails ELSE public.email_messages.cc_emails END,
    bcc_emails = CASE WHEN cardinality(EXCLUDED.bcc_emails) > 0 THEN EXCLUDED.bcc_emails ELSE public.email_messages.bcc_emails END,
    body_html = coalesce(EXCLUDED.body_html, public.email_messages.body_html),
    body_plain = coalesce(EXCLUDED.body_plain, public.email_messages.body_plain),
    body_clean = coalesce(EXCLUDED.body_clean, public.email_messages.body_clean),
    contact_id = coalesce(EXCLUDED.contact_id, public.email_messages.contact_id),
    organization_id = coalesce(EXCLUDED.organization_id, public.email_messages.organization_id),
    headers = CASE WHEN EXCLUDED.headers <> '{}'::jsonb THEN EXCLUDED.headers ELSE public.email_messages.headers END,
    attachments = CASE WHEN EXCLUDED.attachments <> '[]'::jsonb THEN EXCLUDED.attachments ELSE public.email_messages.attachments END,
    sent_at = coalesce(EXCLUDED.sent_at, public.email_messages.sent_at),
    received_at = CASE
      WHEN EXCLUDED.received_at IS NULL THEN public.email_messages.received_at
      WHEN public.email_messages.received_at IS NULL THEN EXCLUDED.received_at
      ELSE LEAST(public.email_messages.received_at, EXCLUDED.received_at)
    END,
    needs_parsing = EXCLUDED.needs_parsing,
    intent = coalesce(EXCLUDED.intent, public.email_messages.intent),
    email_category = coalesce(EXCLUDED.email_category, public.email_messages.email_category),
    sentiment = coalesce(EXCLUDED.sentiment, public.email_messages.sentiment),
    priority_score = coalesce(EXCLUDED.priority_score, public.email_messages.priority_score),
    spam_score = coalesce(EXCLUDED.spam_score, public.email_messages.spam_score),
    ai_processed_at = coalesce(EXCLUDED.ai_processed_at, public.email_messages.ai_processed_at),
    ai_model_version = coalesce(EXCLUDED.ai_model_version, public.email_messages.ai_model_version),
    ai_confidence_score = coalesce(EXCLUDED.ai_confidence_score, public.email_messages.ai_confidence_score),
    enrichment_status = CASE
      WHEN EXCLUDED.enrichment_status IS NULL OR EXCLUDED.enrichment_status = 'pending'
        THEN public.email_messages.enrichment_status
      WHEN public.email_messages.enrichment_status IS NULL OR public.email_messages.enrichment_status = 'pending'
        THEN EXCLUDED.enrichment_status
      WHEN EXCLUDED.enriched_at IS NOT NULL
        AND (public.email_messages.enriched_at IS NULL OR EXCLUDED.enriched_at >= public.email_messages.enriched_at)
        THEN EXCLUDED.enrichment_status
      ELSE public.email_messages.enrichment_status
    END,
    enriched_at = coalesce(EXCLUDED.enriched_at, public.email_messages.enriched_at),
    last_enrichment_error = coalesce(EXCLUDED.last_enrichment_error, public.email_messages.last_enrichment_error),
    message_kind = EXCLUDED.message_kind,
    is_internal = EXCLUDED.is_internal,
    mailchimp_newsletter_id = coalesce(EXCLUDED.mailchimp_newsletter_id, public.email_messages.mailchimp_newsletter_id),
    mailchimp_match_method = coalesce(EXCLUDED.mailchimp_match_method, public.email_messages.mailchimp_match_method),
    mailchimp_match_confidence = coalesce(EXCLUDED.mailchimp_match_confidence, public.email_messages.mailchimp_match_confidence),
    mailchimp_match_reason = coalesce(EXCLUDED.mailchimp_match_reason, public.email_messages.mailchimp_match_reason),
    workflow_matched_at = coalesce(public.email_messages.workflow_matched_at, EXCLUDED.workflow_matched_at),
    auth_user_id = coalesce(EXCLUDED.auth_user_id, public.email_messages.auth_user_id)
  RETURNING id INTO email_message_id;

  IF v_uid IS NOT NULL THEN
    SELECT id INTO v_existing_copy_id
    FROM public.email_mailbox_copies
    WHERE mailbox_id = v_mailbox_id
      AND imap_folder = v_folder
      AND imap_uid = v_uid
    LIMIT 1;
  END IF;

  IF v_existing_copy_id IS NULL THEN
    SELECT id INTO v_existing_copy_id
    FROM public.email_mailbox_copies
    WHERE id = v_copy_id
    LIMIT 1;
  END IF;

  IF v_existing_copy_id IS NOT NULL THEN
    UPDATE public.email_mailbox_copies
       SET email_message_id = upsert_email_message_copy.email_message_id,
           is_seen = coalesce((copy_payload->>'is_seen')::boolean, is_seen),
           is_flagged = coalesce((copy_payload->>'is_flagged')::boolean, is_flagged),
           is_answered = coalesce((copy_payload->>'is_answered')::boolean, is_answered),
           is_draft = coalesce((copy_payload->>'is_draft')::boolean, is_draft),
           is_deleted = coalesce((copy_payload->>'is_deleted')::boolean, is_deleted),
           skip_workflows = coalesce((copy_payload->>'skip_workflows')::boolean, skip_workflows),
           updated_at = now()
     WHERE id = v_existing_copy_id
     RETURNING id INTO mailbox_copy_id;
    copy_created := false;
  ELSE
    INSERT INTO public.email_mailbox_copies (
      id, email_message_id, message_id, thread_id, conversation_id, in_reply_to,
      email_references, subject, from_email, from_name, to_emails, cc_emails,
      bcc_emails, body_html, body_plain, body_clean, mailbox_id, contact_id,
      organization_id, direction, is_seen, is_flagged, is_answered, is_draft,
      is_deleted, imap_folder, imap_uid, headers, attachments, sent_at,
      received_at, needs_parsing, intent, email_category, sentiment,
      priority_score, spam_score, ai_processed_at, ai_model_version,
      ai_confidence_score, auth_user_id, workflow_matched_at, skip_workflows,
      enrichment_status, enriched_at, last_enrichment_error, message_kind,
      is_internal, mailchimp_newsletter_id, mailchimp_match_method,
      mailchimp_match_confidence, mailchimp_match_reason, created_at
    )
    VALUES (
      v_copy_id,
      email_message_id,
      coalesce(public.normalize_email_message_id(v_message_id), 'synthetic-' || coalesce(v_uid::text, v_copy_id::text)),
      coalesce(copy_payload->>'thread_id', message_payload->>'thread_id'),
      NULLIF(coalesce(copy_payload->>'conversation_id', message_payload->>'conversation_id'), '')::uuid,
      NULLIF(coalesce(copy_payload->>'in_reply_to', message_payload->>'in_reply_to'), ''),
      NULLIF(coalesce(copy_payload->>'email_references', message_payload->>'email_references'), ''),
      NULLIF(coalesce(copy_payload->>'subject', message_payload->>'subject'), ''),
      coalesce(copy_payload->>'from_email', message_payload->>'from_email'),
      NULLIF(coalesce(copy_payload->>'from_name', message_payload->>'from_name'), ''),
      ARRAY(SELECT jsonb_array_elements_text(coalesce(copy_payload->'to_emails', message_payload->'to_emails', '[]'::jsonb))),
      ARRAY(SELECT jsonb_array_elements_text(coalesce(copy_payload->'cc_emails', message_payload->'cc_emails', '[]'::jsonb))),
      ARRAY(SELECT jsonb_array_elements_text(coalesce(copy_payload->'bcc_emails', message_payload->'bcc_emails', '[]'::jsonb))),
      coalesce(copy_payload->>'body_html', message_payload->>'body_html'),
      coalesce(copy_payload->>'body_plain', message_payload->>'body_plain'),
      coalesce(copy_payload->>'body_clean', message_payload->>'body_clean'),
      v_mailbox_id,
      NULLIF(coalesce(copy_payload->>'contact_id', message_payload->>'contact_id'), '')::uuid,
      NULLIF(coalesce(copy_payload->>'organization_id', message_payload->>'organization_id'), '')::uuid,
      copy_payload->>'direction',
      coalesce((copy_payload->>'is_seen')::boolean, false),
      coalesce((copy_payload->>'is_flagged')::boolean, false),
      coalesce((copy_payload->>'is_answered')::boolean, false),
      coalesce((copy_payload->>'is_draft')::boolean, false),
      coalesce((copy_payload->>'is_deleted')::boolean, false),
      v_folder,
      v_uid,
      coalesce(copy_payload->'headers', message_payload->'headers', '{}'::jsonb),
      coalesce(copy_payload->'attachments', message_payload->'attachments', '[]'::jsonb),
      NULLIF(coalesce(copy_payload->>'sent_at', message_payload->>'sent_at'), '')::timestamptz,
      coalesce(NULLIF(copy_payload->>'received_at', ''), NULLIF(message_payload->>'received_at', ''))::timestamptz,
      coalesce((copy_payload->>'needs_parsing')::boolean, (message_payload->>'needs_parsing')::boolean, false),
      NULLIF(coalesce(copy_payload->>'intent', message_payload->>'intent'), ''),
      NULLIF(coalesce(copy_payload->>'email_category', message_payload->>'email_category'), ''),
      NULLIF(coalesce(copy_payload->>'sentiment', message_payload->>'sentiment'), ''),
      NULLIF(coalesce(copy_payload->>'priority_score', message_payload->>'priority_score'), '')::integer,
      NULLIF(coalesce(copy_payload->>'spam_score', message_payload->>'spam_score'), '')::numeric,
      NULLIF(coalesce(copy_payload->>'ai_processed_at', message_payload->>'ai_processed_at'), '')::timestamptz,
      NULLIF(coalesce(copy_payload->>'ai_model_version', message_payload->>'ai_model_version'), ''),
      NULLIF(coalesce(copy_payload->>'ai_confidence_score', message_payload->>'ai_confidence_score'), '')::numeric,
      NULLIF(coalesce(copy_payload->>'auth_user_id', message_payload->>'auth_user_id'), '')::uuid,
      NULLIF(coalesce(copy_payload->>'workflow_matched_at', message_payload->>'workflow_matched_at'), '')::timestamptz,
      coalesce((copy_payload->>'skip_workflows')::boolean, false),
      coalesce(NULLIF(copy_payload->>'enrichment_status', ''), NULLIF(message_payload->>'enrichment_status', ''), 'pending'),
      NULLIF(coalesce(copy_payload->>'enriched_at', message_payload->>'enriched_at'), '')::timestamptz,
      NULLIF(coalesce(copy_payload->>'last_enrichment_error', message_payload->>'last_enrichment_error'), ''),
      coalesce(NULLIF(copy_payload->>'message_kind', ''), NULLIF(message_payload->>'message_kind', ''), 'human')::public.email_message_kind,
      coalesce((copy_payload->>'is_internal')::boolean, (message_payload->>'is_internal')::boolean, false),
      NULLIF(coalesce(copy_payload->>'mailchimp_newsletter_id', message_payload->>'mailchimp_newsletter_id'), '')::uuid,
      NULLIF(coalesce(copy_payload->>'mailchimp_match_method', message_payload->>'mailchimp_match_method'), ''),
      NULLIF(coalesce(copy_payload->>'mailchimp_match_confidence', message_payload->>'mailchimp_match_confidence'), '')::numeric,
      NULLIF(coalesce(copy_payload->>'mailchimp_match_reason', message_payload->>'mailchimp_match_reason'), ''),
      coalesce(NULLIF(copy_payload->>'created_at', ''), now()::text)::timestamptz
    )
    RETURNING id INTO mailbox_copy_id;
    copy_created := true;
  END IF;

  PERFORM public.trigger_workflow_matching_for_message(email_message_id);

  RETURN NEXT;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.upsert_email_message_copy(jsonb, jsonb) FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.upsert_email_message_copy(jsonb, jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.backfill_email_canonical_references()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_workflows integer;
  v_source_drafts integer;
  v_sent_drafts integer;
BEGIN
  UPDATE public.workflow_executions we
     SET email_message_id = c.email_message_id
  FROM public.email_mailbox_copies c
  WHERE we.email_id = c.id
    AND we.email_message_id IS NULL
    AND c.email_message_id IS NOT NULL;
  GET DIAGNOSTICS v_workflows = ROW_COUNT;

  UPDATE public.email_drafts d
     SET source_email_message_id = c.email_message_id
  FROM public.email_mailbox_copies c
  WHERE d.source_email_id = c.id
    AND d.source_email_message_id IS NULL
    AND c.email_message_id IS NOT NULL;
  GET DIAGNOSTICS v_source_drafts = ROW_COUNT;

  UPDATE public.email_drafts d
     SET sent_email_message_id = c.email_message_id
  FROM public.email_mailbox_copies c
  WHERE d.sent_email_id = c.id
    AND d.sent_email_message_id IS NULL
    AND c.email_message_id IS NOT NULL;
  GET DIAGNOSTICS v_sent_drafts = ROW_COUNT;

  RETURN jsonb_build_object(
    'workflow_executions', v_workflows,
    'source_drafts', v_source_drafts,
    'sent_drafts', v_sent_drafts
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.backfill_email_canonical_references() FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.backfill_email_canonical_references() TO service_role;

CREATE OR REPLACE FUNCTION public.trigger_workflow_matching_for_message(p_email_message_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  lambda_url text;
  source_copy_id uuid;
  v_email_category text;
  v_workflow_matched_at timestamptz;
  v_marked boolean := false;
BEGIN
  SELECT email_category, workflow_matched_at
    INTO v_email_category, v_workflow_matched_at
  FROM public.email_messages
  WHERE id = p_email_message_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_workflow_matched_at IS NOT NULL THEN
    RETURN false;
  END IF;

  IF v_email_category IS NULL
     OR NOT v_email_category LIKE 'business-%'
     OR v_email_category = 'business-transactional' THEN
    RETURN false;
  END IF;

  SELECT c.id INTO source_copy_id
  FROM public.email_mailbox_copies c
  WHERE c.email_message_id = p_email_message_id
    AND c.direction = 'incoming'
    AND COALESCE(c.skip_workflows, false) = false
    AND COALESCE(c.is_deleted, false) = false
  ORDER BY c.received_at ASC, c.created_at ASC
  LIMIT 1;

  IF source_copy_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT value #>> '{}' INTO lambda_url
  FROM public.system_config
  WHERE key = 'workflow_matcher_url';

  IF lambda_url IS NULL OR lambda_url = '' THEN
    RETURN false;
  END IF;

  UPDATE public.email_messages
     SET workflow_matched_at = now()
   WHERE id = p_email_message_id
     AND workflow_matched_at IS NULL
   RETURNING true INTO v_marked;

  IF NOT coalesce(v_marked, false) THEN
    RETURN false;
  END IF;

  BEGIN
    PERFORM net.http_post(
      url := lambda_url,
      headers := '{"Content-Type": "application/json"}'::jsonb,
      body := json_build_object(
        'email_id', source_copy_id,
        'email_message_id', p_email_message_id
      )::jsonb,
      timeout_milliseconds := 30000
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Failed to trigger workflow matcher for canonical email message %: %', p_email_message_id, SQLERRM;
  END;

  RETURN true;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.trigger_workflow_matching_for_message(uuid) FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.trigger_workflow_matching_for_message(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.trigger_workflow_matching()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.email_category IS NOT DISTINCT FROM NEW.email_category THEN
    RETURN NEW;
  END IF;

  PERFORM public.trigger_workflow_matching_for_message(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_match_workflows ON public.email_mailbox_copies;
DROP TRIGGER IF EXISTS trigger_match_workflows ON public.email_messages;
CREATE TRIGGER trigger_match_workflows
  AFTER INSERT OR UPDATE OF email_category ON public.email_messages
  FOR EACH ROW
  WHEN (NEW.email_category IS NOT NULL AND NEW.email_category LIKE 'business-%')
  EXECUTE FUNCTION public.trigger_workflow_matching();

CREATE OR REPLACE FUNCTION public.update_conversation_stats(p_conversation_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_email_count integer;
  v_first_email_at timestamptz;
  v_last_email_at timestamptz;
  v_last_direction text;
BEGIN
  WITH visible_messages AS (
    SELECT DISTINCT ON (m.id)
      m.id,
      m.received_at,
      c.direction
    FROM public.email_messages m
    JOIN public.email_mailbox_copies c ON c.email_message_id = m.id
    WHERE m.conversation_id = p_conversation_id
      AND COALESCE(c.is_deleted, false) = false
    ORDER BY m.id, c.received_at DESC, c.created_at DESC
  ),
  ordered AS (
    SELECT * FROM visible_messages ORDER BY received_at ASC
  )
  SELECT
    COUNT(*),
    MIN(received_at),
    MAX(received_at),
    (ARRAY_AGG(direction ORDER BY received_at DESC))[1]
  INTO v_email_count, v_first_email_at, v_last_email_at, v_last_direction
  FROM ordered;

  UPDATE public.conversations
  SET email_count = COALESCE(v_email_count, 0),
      first_email_at = v_first_email_at,
      last_email_at = v_last_email_at,
      last_email_direction = v_last_direction,
      requires_response = (v_last_direction = 'incoming'),
      updated_at = now()
  WHERE id = p_conversation_id;
END;
$$;

CREATE OR REPLACE VIEW public.emails
WITH (security_invoker = true) AS
SELECT
  c.id,
  coalesce(m.message_id, c.message_id) AS message_id,
  coalesce(m.thread_id, c.thread_id) AS thread_id,
  coalesce(m.conversation_id, c.conversation_id) AS conversation_id,
  coalesce(m.in_reply_to, c.in_reply_to) AS in_reply_to,
  coalesce(m.email_references, c.email_references) AS email_references,
  coalesce(m.subject, c.subject) AS subject,
  coalesce(m.from_email, c.from_email) AS from_email,
  coalesce(m.from_name, c.from_name) AS from_name,
  coalesce(m.to_emails, c.to_emails) AS to_emails,
  coalesce(m.cc_emails, c.cc_emails) AS cc_emails,
  coalesce(m.bcc_emails, c.bcc_emails) AS bcc_emails,
  coalesce(m.body_html, c.body_html) AS body_html,
  coalesce(m.body_plain, c.body_plain) AS body_plain,
  coalesce(m.body_clean, c.body_clean) AS body_clean,
  c.mailbox_id,
  coalesce(m.contact_id, c.contact_id) AS contact_id,
  coalesce(m.organization_id, c.organization_id) AS organization_id,
  c.direction,
  c.is_seen,
  c.is_flagged,
  c.is_answered,
  c.is_draft,
  c.is_deleted,
  c.imap_folder,
  c.imap_uid,
  coalesce(m.headers, c.headers) AS headers,
  coalesce(m.attachments, c.attachments) AS attachments,
  coalesce(m.sent_at, c.sent_at) AS sent_at,
  coalesce(m.received_at, c.received_at) AS received_at,
  c.created_at,
  c.updated_at,
  coalesce(m.needs_parsing, c.needs_parsing) AS needs_parsing,
  coalesce(m.intent, c.intent) AS intent,
  coalesce(m.email_category, c.email_category) AS email_category,
  coalesce(m.sentiment, c.sentiment) AS sentiment,
  coalesce(m.priority_score, c.priority_score) AS priority_score,
  coalesce(m.spam_score, c.spam_score) AS spam_score,
  coalesce(m.ai_processed_at, c.ai_processed_at) AS ai_processed_at,
  coalesce(m.ai_model_version, c.ai_model_version) AS ai_model_version,
  coalesce(m.ai_confidence_score, c.ai_confidence_score) AS ai_confidence_score,
  coalesce(m.auth_user_id, c.auth_user_id) AS auth_user_id,
  coalesce(m.workflow_matched_at, c.workflow_matched_at) AS workflow_matched_at,
  c.skip_workflows,
  coalesce(m.enrichment_status, c.enrichment_status) AS enrichment_status,
  coalesce(m.enriched_at, c.enriched_at) AS enriched_at,
  coalesce(m.last_enrichment_error, c.last_enrichment_error) AS last_enrichment_error,
  coalesce(m.message_kind, c.message_kind) AS message_kind,
  coalesce(m.is_internal, c.is_internal) AS is_internal,
  coalesce(m.mailchimp_newsletter_id, c.mailchimp_newsletter_id) AS mailchimp_newsletter_id,
  coalesce(m.mailchimp_match_method, c.mailchimp_match_method) AS mailchimp_match_method,
  coalesce(m.mailchimp_match_confidence, c.mailchimp_match_confidence) AS mailchimp_match_confidence,
  coalesce(m.mailchimp_match_reason, c.mailchimp_match_reason) AS mailchimp_match_reason,
  c.email_message_id,
  m.message_key
FROM public.email_mailbox_copies c
LEFT JOIN public.email_messages m ON m.id = c.email_message_id;

GRANT SELECT ON public.emails TO authenticated, service_role;

COMMENT ON VIEW public.emails IS
  'Read-only compatibility view joining email_mailbox_copies to email_messages. id remains the mailbox-copy id.';

CREATE OR REPLACE VIEW public.v_email_activity
WITH (security_invoker = true) AS
SELECT
  c.id,
  c.mailbox_id,
  mb.email AS mailbox_email,
  mb.name AS mailbox_name,
  coalesce(m.from_email, c.from_email) AS from_address,
  coalesce(m.from_name, c.from_name) AS from_name,
  coalesce(m.subject, c.subject) AS subject,
  coalesce(m.message_id, c.message_id) AS message_id,
  c.imap_folder,
  c.imap_uid,
  coalesce(m.received_at, c.received_at) AS received_at,
  c.created_at AS imported_at,
  coalesce(m.enrichment_status, c.enrichment_status) AS enrichment_status,
  coalesce(m.enriched_at, c.enriched_at) AS enriched_at,
  coalesce(m.last_enrichment_error, c.last_enrichment_error) AS last_enrichment_error,
  (
    SELECT json_build_object(
      'workflow_id', we.workflow_id,
      'workflow_name', w.name,
      'status', we.status,
      'matched_at', we.started_at
    )
    FROM public.workflow_executions we
    LEFT JOIN public.workflows w ON w.id = we.workflow_id
    WHERE we.email_id = c.id
       OR (we.email_message_id IS NOT NULL AND we.email_message_id = c.email_message_id)
    ORDER BY we.started_at DESC
    LIMIT 1
  ) AS latest_workflow,
  (
    SELECT json_build_object(
      'error_id', err.id,
      'error_class', err.error_class,
      'error_message', err.error_message,
      'failure_group_id', err.failure_group_id
    )
    FROM public.email_import_errors err
    WHERE err.mailbox_id = c.mailbox_id
      AND err.imap_folder = c.imap_folder
      AND err.imap_uid = c.imap_uid
      AND err.resolved_at IS NULL
    ORDER BY err.created_at DESC
    LIMIT 1
  ) AS latest_error
FROM public.email_mailbox_copies c
LEFT JOIN public.email_messages m ON m.id = c.email_message_id
LEFT JOIN public.mailboxes mb ON mb.id = c.mailbox_id

UNION ALL

SELECT
  err.id,
  err.mailbox_id,
  mb.email AS mailbox_email,
  mb.name AS mailbox_name,
  NULL::text AS from_address,
  NULL::text AS from_name,
  NULL::text AS subject,
  err.message_id,
  err.imap_folder,
  err.imap_uid,
  NULL::timestamptz AS received_at,
  err.created_at AS imported_at,
  'import_failed'::text AS enrichment_status,
  NULL::timestamptz AS enriched_at,
  NULL::text AS last_enrichment_error,
  NULL::json AS latest_workflow,
  json_build_object(
    'error_id', err.id,
    'error_class', err.error_class,
    'error_message', err.error_message,
    'failure_group_id', err.failure_group_id
  ) AS latest_error
FROM public.email_import_errors err
LEFT JOIN public.mailboxes mb ON mb.id = err.mailbox_id
WHERE err.resolved_at IS NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.email_mailbox_copies c2
    WHERE c2.mailbox_id = err.mailbox_id
      AND c2.imap_folder = err.imap_folder
      AND c2.imap_uid = err.imap_uid
  );

GRANT SELECT ON public.v_email_activity TO service_role;

CREATE OR REPLACE FUNCTION public.search_emails(
  q text,
  p_limit int DEFAULT 50,
  p_offset int DEFAULT 0
)
RETURNS TABLE(
  id uuid,
  email_message_id uuid,
  conversation_id uuid,
  subject text,
  from_email text,
  from_name text,
  received_at timestamptz,
  rank real
)
LANGUAGE sql
SECURITY INVOKER
AS $$
  WITH tokens AS (
    SELECT lower(trim(t)) AS token
    FROM regexp_split_to_table(coalesce(q, ''), '\s+') AS t
    WHERE length(trim(t)) > 0
  ),
  message_matches AS (
    SELECT
      m.id AS email_message_id,
      min(c.id) AS display_copy_id,
      m.conversation_id,
      m.subject::text,
      m.from_email::text,
      m.from_name::text,
      m.received_at,
      count(*)::real AS rank
    FROM public.email_messages m
    JOIN public.email_mailbox_copies c ON c.email_message_id = m.id
    LEFT JOIN public.contacts ct ON ct.id = m.contact_id
    LEFT JOIN public.organizations o ON o.id = m.organization_id
    WHERE COALESCE(c.is_deleted, false) = false
      AND NOT EXISTS (
        SELECT 1
        FROM tokens t
        WHERE (
          lower(
            coalesce(m.subject, '') || ' ' ||
            coalesce(m.from_email, '') || ' ' ||
            coalesce(m.from_name, '') || ' ' ||
            array_to_string(coalesce(m.to_emails, '{}'), ' ') || ' ' ||
            array_to_string(coalesce(m.cc_emails, '{}'), ' ') || ' ' ||
            array_to_string(coalesce(m.bcc_emails, '{}'), ' ') || ' ' ||
            coalesce(m.body_clean, '') || ' ' ||
            coalesce(ct.email, '') || ' ' ||
            coalesce(ct.first_name, '') || ' ' ||
            coalesce(ct.last_name, '') || ' ' ||
            coalesce(o.name, '')
          ) NOT LIKE '%' || t.token || '%'
        )
      )
    GROUP BY m.id, m.conversation_id, m.subject, m.from_email, m.from_name, m.received_at
  )
  SELECT
    display_copy_id AS id,
    email_message_id,
    conversation_id,
    subject,
    from_email,
    from_name,
    received_at,
    rank
  FROM message_matches
  ORDER BY rank DESC, received_at DESC
  LIMIT greatest(p_limit, 0)
  OFFSET greatest(p_offset, 0);
$$;

GRANT EXECUTE ON FUNCTION public.search_emails(text, int, int) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_conversation_category_counts(
  p_mailbox_id uuid DEFAULT NULL,
  p_show_internal boolean DEFAULT false
)
RETURNS TABLE(all_count integer, business integer, spam integer, personal integer, other integer)
LANGUAGE sql
SECURITY INVOKER
AS $$
  WITH latest AS (
    SELECT DISTINCT ON (c.conversation_id)
      c.conversation_id,
      c.email_category,
      c.is_internal
    FROM (
      SELECT
        m.conversation_id,
        m.email_category,
        m.is_internal,
        m.received_at,
        CASE WHEN COALESCE(m.message_kind::text, 'human') <> 'auto_reply' THEN 0 ELSE 1 END AS auto_rank
      FROM public.email_messages m
      JOIN public.email_mailbox_copies copy ON copy.email_message_id = m.id
      WHERE m.conversation_id IS NOT NULL
        AND COALESCE(copy.is_deleted, false) = false
        AND (p_mailbox_id IS NULL OR copy.mailbox_id = p_mailbox_id)
    ) c
    ORDER BY c.conversation_id, c.auto_rank ASC, c.received_at DESC
  ),
  filtered AS (
    SELECT *
    FROM latest
    WHERE p_show_internal OR COALESCE(is_internal, false) = false
  )
  SELECT
    count(*)::integer,
    count(*) FILTER (WHERE email_category LIKE 'business-%')::integer,
    count(*) FILTER (WHERE email_category LIKE 'spam-%')::integer,
    count(*) FILTER (WHERE email_category LIKE 'personal-%')::integer,
    count(*) FILTER (
      WHERE email_category IS NULL
         OR (
           email_category NOT LIKE 'business-%'
           AND email_category NOT LIKE 'spam-%'
           AND email_category NOT LIKE 'personal-%'
         )
    )::integer
  FROM filtered;
$$;

GRANT EXECUTE ON FUNCTION public.get_conversation_category_counts(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.rebuild_email_scopes_for_domain(p_domain text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
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
  ),
  scoped AS (
    SELECT m.id,
      COALESCE((
        SELECT bool_and(public.is_host_domain(addr))
        FROM unnest(
          array_remove(
            ARRAY[m.from_email] || COALESCE(m.to_emails, ARRAY[]::text[])
                                || COALESCE(m.cc_emails, ARRAY[]::text[])
                                || COALESCE(m.bcc_emails, ARRAY[]::text[]),
            NULL
          )
        ) AS addr
        WHERE addr IS NOT NULL AND addr <> ''
      ), FALSE) AS next_is_internal
    FROM public.email_messages m
    WHERE EXISTS (
      SELECT 1
      FROM unnest(
        array_remove(
          ARRAY[m.from_email] || COALESCE(m.to_emails, ARRAY[]::text[])
                              || COALESCE(m.cc_emails, ARRAY[]::text[])
                              || COALESCE(m.bcc_emails, ARRAY[]::text[]),
          NULL
        )
      ) AS addr
      WHERE lower(split_part(addr, '@', 2)) = lower(p_domain)
         OR lower(split_part(trim(both ' <>"' from addr), '@', 2)) IN (
           SELECT domain FROM scope_domains
         )
    )
  ),
  updated_messages AS (
    UPDATE public.email_messages m
       SET is_internal = scoped.next_is_internal
    FROM scoped
    WHERE scoped.id = m.id
    RETURNING m.id, m.is_internal
  )
  UPDATE public.email_mailbox_copies c
     SET is_internal = updated_messages.is_internal
  FROM updated_messages
  WHERE c.email_message_id = updated_messages.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_conversation_summaries(
  p_mailbox_id uuid DEFAULT NULL,
  p_category_type text DEFAULT 'all',
  p_category_subtype text DEFAULT NULL,
  p_intents text[] DEFAULT NULL,
  p_sentiments text[] DEFAULT NULL,
  p_requires_response boolean DEFAULT NULL,
  p_unread boolean DEFAULT NULL,
  p_priority_min integer DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_show_internal boolean DEFAULT FALSE,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  conversation jsonb,
  total_count bigint
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH tokens AS (
    SELECT '%' || token || '%' AS pat
    FROM regexp_split_to_table(trim(COALESCE(p_search, '')), '\s+') AS token
    WHERE length(token) > 0
  ),
  latest_candidates AS (
    SELECT
      m.*,
      dc.id AS display_copy_id,
      dc.mailbox_id AS display_mailbox_id,
      dc.direction AS display_direction,
      dc.is_seen AS display_is_seen,
      dc.received_at AS display_received_at,
      dc.created_at AS display_created_at
    FROM public.email_messages m
    JOIN LATERAL (
      SELECT c.*
      FROM public.email_mailbox_copies c
      WHERE c.email_message_id = m.id
        AND COALESCE(c.is_deleted, FALSE) = FALSE
        AND (p_mailbox_id IS NULL OR c.mailbox_id = p_mailbox_id)
      ORDER BY c.received_at ASC NULLS LAST, c.created_at ASC, c.id
      LIMIT 1
    ) dc ON TRUE
    WHERE m.conversation_id IS NOT NULL
  ),
  latest_ranked AS (
    SELECT
      lc.*,
      ROW_NUMBER() OVER (
        PARTITION BY lc.conversation_id
        ORDER BY
          CASE WHEN COALESCE(lc.message_kind::text, 'human') <> 'auto_reply' THEN 0 ELSE 1 END,
          lc.received_at DESC NULLS LAST,
          lc.created_at DESC NULLS LAST,
          lc.id DESC
      ) AS rn
    FROM latest_candidates lc
  ),
  latest AS (
    SELECT *
    FROM latest_ranked
    WHERE rn = 1
  ),
  filtered AS (
    SELECT
      c.*,
      mb.id AS mailbox_id_out,
      mb.email AS mailbox_email,
      mb.name AS mailbox_name,
      o.id AS organization_id_out,
      o.name AS organization_name,
      pc.id AS contact_id_out,
      pc.email AS contact_email,
      pc.first_name AS contact_first_name,
      pc.last_name AS contact_last_name,
      le.id AS latest_email_message_id,
      le.display_copy_id,
      le.from_email,
      le.from_name,
      le.subject AS latest_subject,
      le.body_clean,
      le.body_plain,
      le.email_category,
      le.intent,
      le.sentiment,
      le.priority_score,
      le.received_at,
      le.display_direction AS direction,
      le.display_is_seen AS is_seen,
      le.message_kind,
      le.mailchimp_newsletter_id,
      le.mailchimp_match_method,
      le.mailchimp_match_confidence,
      le.is_internal,
      mn.id AS newsletter_id,
      mn.subject AS newsletter_subject,
      mn.sent_at AS newsletter_sent_at,
      mn.from_name AS newsletter_from_name
    FROM public.conversations c
    JOIN latest le ON le.conversation_id = c.id
    LEFT JOIN public.mailboxes mb ON mb.id = COALESCE(p_mailbox_id, c.mailbox_id, le.display_mailbox_id)
    LEFT JOIN public.organizations o ON o.id = c.organization_id
    LEFT JOIN public.contacts pc ON pc.id = c.primary_contact_id
    LEFT JOIN public.mailchimp_newsletters mn ON mn.id = le.mailchimp_newsletter_id
    WHERE c.status = 'active'
      AND c.email_count > 0
      AND (p_requires_response IS NULL OR c.requires_response = p_requires_response)
      AND (p_unread IS NULL OR (p_unread = TRUE AND le.display_is_seen = FALSE))
      AND (p_priority_min IS NULL OR COALESCE(le.priority_score, 0) >= p_priority_min)
      AND (p_show_internal OR COALESCE(le.is_internal, FALSE) = FALSE)
      AND (
        COALESCE(p_category_type, 'all') = 'all'
        OR COALESCE(le.email_category, '') LIKE p_category_type || '-%'
      )
      AND (
        p_category_subtype IS NULL
        OR COALESCE(le.email_category, '') LIKE '%-' || p_category_subtype
      )
      AND (
        COALESCE(array_length(p_intents, 1), 0) = 0
        OR le.intent = ANY(p_intents)
      )
      AND (
        COALESCE(array_length(p_sentiments, 1), 0) = 0
        OR le.sentiment = ANY(p_sentiments)
      )
      AND NOT EXISTS (
        SELECT 1 FROM tokens t
        WHERE NOT (
          (
            COALESCE(c.subject, '')      || ' ' ||
            COALESCE(c.summary, '')      || ' ' ||
            COALESCE(le.subject, '')     || ' ' ||
            COALESCE(le.from_email, '')  || ' ' ||
            COALESCE(le.from_name, '')   || ' ' ||
            COALESCE(le.body_clean, '')  || ' ' ||
            COALESCE(le.body_plain, '')
          ) ILIKE t.pat
          OR
          (
            COALESCE(pc.first_name, '') || ' ' ||
            COALESCE(pc.last_name, '')  || ' ' ||
            COALESCE(pc.email, '')
          ) ILIKE t.pat
          OR
          (
            COALESCE(o.name, '') || ' ' ||
            COALESCE(o.city, '') || ' ' ||
            COALESCE(o.state, '')
          ) ILIKE t.pat
        )
      )
  ),
  totals AS (
    SELECT COUNT(*) AS total_count FROM filtered
  ),
  page_rows AS (
    SELECT
      jsonb_build_object(
        'id', f.id,
        'thread_id', f.thread_id,
        'subject', f.subject,
        'email_count', f.email_count,
        'first_email_at', f.first_email_at,
        'last_email_at', f.last_email_at,
        'last_email_direction', f.last_email_direction,
        'status', f.status,
        'requires_response', f.requires_response,
        'summary', f.summary,
        'action_items', f.action_items,
        'mailbox', CASE
          WHEN f.mailbox_id_out IS NULL THEN NULL
          ELSE jsonb_build_object('id', f.mailbox_id_out, 'email', f.mailbox_email, 'name', f.mailbox_name)
        END,
        'organization', CASE
          WHEN f.organization_id_out IS NULL THEN NULL
          ELSE jsonb_build_object('id', f.organization_id_out, 'name', f.organization_name)
        END,
        'primary_contact', CASE
          WHEN f.contact_id_out IS NULL THEN NULL
          ELSE jsonb_build_object('id', f.contact_id_out, 'email', f.contact_email, 'first_name', f.contact_first_name, 'last_name', f.contact_last_name)
        END,
        'latest_email', jsonb_build_object(
          'id', f.display_copy_id,
          'email_message_id', f.latest_email_message_id,
          'display_copy_id', f.display_copy_id,
          'from_email', f.from_email,
          'from_name', f.from_name,
          'subject', f.latest_subject,
          'body_plain', NULL,
          'email_category', f.email_category,
          'intent', f.intent,
          'sentiment', f.sentiment,
          'priority_score', f.priority_score,
          'received_at', f.received_at,
          'direction', f.direction,
          'is_seen', f.is_seen,
          'message_kind', f.message_kind,
          'mailchimp_newsletter_id', f.mailchimp_newsletter_id,
          'mailchimp_match_method', f.mailchimp_match_method,
          'mailchimp_match_confidence', f.mailchimp_match_confidence,
          'is_internal', f.is_internal,
          'mailchimp_newsletter', CASE
            WHEN f.newsletter_id IS NULL THEN NULL
            ELSE jsonb_build_object('id', f.newsletter_id, 'subject', f.newsletter_subject, 'sent_at', f.newsletter_sent_at, 'from_name', f.newsletter_from_name)
          END
        )
      ) AS conversation
    FROM filtered f
    ORDER BY f.last_email_at DESC NULLS LAST, f.id
    LIMIT LEAST(GREATEST(p_limit, 1), 100)
    OFFSET GREATEST(p_offset, 0)
  )
  SELECT p.conversation, t.total_count
  FROM page_rows p
  CROSS JOIN totals t
  UNION ALL
  SELECT NULL::jsonb, t.total_count
  FROM totals t
  WHERE NOT EXISTS (SELECT 1 FROM page_rows);
$$;

COMMENT ON FUNCTION public.get_conversation_summaries(uuid, text, text, text[], text[], boolean, boolean, integer, text, boolean, integer, integer) IS
  'Returns canonical conversation summaries. Mailbox filters are applied through email_mailbox_copies; latest display email remains a mailbox-copy id.';

GRANT EXECUTE ON FUNCTION public.get_conversation_summaries(uuid, text, text, text[], text[], boolean, boolean, integer, text, boolean, integer, integer) TO authenticated;
