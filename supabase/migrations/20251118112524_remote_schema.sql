drop trigger if exists "emails_log_activity" on "public"."emails";

drop trigger if exists "emails_set_approved_by" on "public"."emails";

drop trigger if exists "emails_set_created_by" on "public"."emails";

drop view if exists "public"."profiles_with_email";


  create table "public"."action_items" (
    "id" uuid not null default gen_random_uuid(),
    "title" character varying(500) not null,
    "description" text,
    "contact_id" uuid not null,
    "email_id" uuid,
    "workflow_execution_id" uuid,
    "action_type" character varying(50),
    "priority" character varying(20) default 'medium'::character varying,
    "status" character varying(20) default 'open'::character varying,
    "due_date" timestamp with time zone,
    "assigned_to" uuid,
    "completed_at" timestamp with time zone,
    "completed_by" uuid,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone default now()
      );



  create table "public"."approval_queue" (
    "id" uuid not null default gen_random_uuid(),
    "workflow_execution_id" uuid not null,
    "action_index" integer not null,
    "action_tool" character varying(100) not null,
    "action_params_resolved" jsonb not null,
    "workflow_name" character varying(255) not null,
    "email_subject" character varying(500),
    "contact_email" character varying(255),
    "extraction_confidence" double precision,
    "reason" text,
    "status" character varying(50) default 'pending'::character varying,
    "decided_by" uuid,
    "decided_at" timestamp with time zone,
    "modified_params" jsonb,
    "rejection_reason" text,
    "created_at" timestamp with time zone default now()
      );



  create table "public"."campaign_enrollments" (
    "id" uuid not null default gen_random_uuid(),
    "campaign_sequence_id" uuid not null,
    "contact_id" uuid not null,
    "current_step" integer default 1,
    "next_send_date" timestamp with time zone,
    "status" character varying(50) default 'enrolled'::character varying,
    "steps_completed" jsonb default '[]'::jsonb,
    "total_opens" integer default 0,
    "total_clicks" integer default 0,
    "replied" boolean default false,
    "enrolled_at" timestamp with time zone default now(),
    "completed_at" timestamp with time zone
      );



  create table "public"."campaign_sequences" (
    "id" uuid not null default gen_random_uuid(),
    "name" character varying(255) not null,
    "description" text,
    "target_sql" text not null,
    "target_count" integer,
    "target_preview" jsonb,
    "steps" jsonb not null,
    "from_mailbox_id" uuid,
    "send_time_preference" character varying(50),
    "product_id" uuid,
    "scheduled_at" timestamp with time zone,
    "started_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "status" character varying(50) default 'draft'::character varying,
    "stats" jsonb default '{}'::jsonb,
    "created_by" uuid,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone default now()
      );



  create table "public"."email_templates" (
    "id" uuid not null default gen_random_uuid(),
    "name" character varying(255) not null,
    "description" text,
    "subject_template" text not null,
    "body_template" text not null,
    "llm_instructions" text,
    "required_variables" jsonb default '[]'::jsonb,
    "category" character varying(100),
    "tags" jsonb default '[]'::jsonb,
    "is_active" boolean default true,
    "created_by" uuid,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone default now()
      );



  create table "public"."system_config" (
    "key" character varying not null,
    "value" jsonb not null,
    "description" text,
    "updated_at" timestamp without time zone default now()
      );



  create table "public"."workflow_executions" (
    "id" uuid not null default gen_random_uuid(),
    "workflow_id" uuid not null,
    "email_id" uuid not null,
    "status" character varying(50) not null default 'pending'::character varying,
    "extracted_data" jsonb,
    "extraction_confidence" double precision,
    "actions_completed" jsonb default '[]'::jsonb,
    "actions_failed" jsonb default '[]'::jsonb,
    "pending_action_index" integer,
    "started_at" timestamp with time zone default now(),
    "completed_at" timestamp with time zone
      );



  create table "public"."workflows" (
    "id" uuid not null default gen_random_uuid(),
    "name" character varying(255) not null,
    "description" text,
    "trigger_condition" text not null,
    "priority" integer default 100,
    "extract_fields" jsonb not null default '[]'::jsonb,
    "actions" jsonb not null default '[]'::jsonb,
    "lead_score_rules" jsonb not null default '[]'::jsonb,
    "category_rules" jsonb default '{"enabled_pattern": "business-*", "disabled_categories": ["business-transactional"]}'::jsonb,
    "is_active" boolean default true,
    "created_by" uuid,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone default now()
      );


CREATE UNIQUE INDEX action_items_pkey ON public.action_items USING btree (id);

CREATE UNIQUE INDEX approval_queue_pkey ON public.approval_queue USING btree (id);

CREATE UNIQUE INDEX campaign_enrollments_campaign_sequence_id_contact_id_key ON public.campaign_enrollments USING btree (campaign_sequence_id, contact_id);

CREATE UNIQUE INDEX campaign_enrollments_pkey ON public.campaign_enrollments USING btree (id);

CREATE UNIQUE INDEX campaign_sequences_pkey ON public.campaign_sequences USING btree (id);

CREATE UNIQUE INDEX email_templates_pkey ON public.email_templates USING btree (id);

CREATE INDEX idx_action_items_assigned ON public.action_items USING btree (assigned_to, status);

CREATE INDEX idx_action_items_contact ON public.action_items USING btree (contact_id, created_at DESC);

CREATE INDEX idx_action_items_status_due ON public.action_items USING btree (status, due_date) WHERE ((status)::text = ANY ((ARRAY['open'::character varying, 'in_progress'::character varying])::text[]));

CREATE INDEX idx_action_items_workflow ON public.action_items USING btree (workflow_execution_id);

CREATE INDEX idx_approval_queue_decided_by ON public.approval_queue USING btree (decided_by, decided_at DESC);

CREATE INDEX idx_approval_queue_pending ON public.approval_queue USING btree (status, created_at DESC) WHERE ((status)::text = 'pending'::text);

CREATE INDEX idx_approval_queue_workflow_execution ON public.approval_queue USING btree (workflow_execution_id);

CREATE INDEX idx_campaign_enrollments_campaign ON public.campaign_enrollments USING btree (campaign_sequence_id, status);

CREATE INDEX idx_campaign_enrollments_contact ON public.campaign_enrollments USING btree (contact_id);

CREATE INDEX idx_campaign_enrollments_next_send ON public.campaign_enrollments USING btree (next_send_date) WHERE ((status)::text = 'active'::text);

CREATE INDEX idx_campaign_enrollments_status ON public.campaign_enrollments USING btree (status);

CREATE INDEX idx_campaign_sequences_created_by ON public.campaign_sequences USING btree (created_by);

CREATE INDEX idx_campaign_sequences_mailbox ON public.campaign_sequences USING btree (from_mailbox_id);

CREATE INDEX idx_campaign_sequences_product ON public.campaign_sequences USING btree (product_id) WHERE (product_id IS NOT NULL);

CREATE INDEX idx_campaign_sequences_scheduled ON public.campaign_sequences USING btree (scheduled_at) WHERE ((status)::text = 'scheduled'::text);

CREATE INDEX idx_campaign_sequences_status ON public.campaign_sequences USING btree (status, created_at DESC);

CREATE INDEX idx_email_templates_active ON public.email_templates USING btree (is_active) WHERE (is_active = true);

CREATE INDEX idx_email_templates_category ON public.email_templates USING btree (category);

CREATE INDEX idx_system_config_key ON public.system_config USING btree (key);

CREATE INDEX idx_workflow_executions_email ON public.workflow_executions USING btree (email_id);

CREATE INDEX idx_workflow_executions_pending ON public.workflow_executions USING btree (status) WHERE ((status)::text = 'awaiting_approval'::text);

CREATE INDEX idx_workflow_executions_status ON public.workflow_executions USING btree (status, started_at DESC);

CREATE INDEX idx_workflow_executions_workflow ON public.workflow_executions USING btree (workflow_id, started_at DESC);

CREATE INDEX idx_workflows_active ON public.workflows USING btree (is_active) WHERE (is_active = true);

CREATE INDEX idx_workflows_active_priority ON public.workflows USING btree (is_active, priority) WHERE (is_active = true);

CREATE INDEX idx_workflows_created_by ON public.workflows USING btree (created_by);

CREATE UNIQUE INDEX system_config_pkey ON public.system_config USING btree (key);

CREATE UNIQUE INDEX workflow_executions_pkey ON public.workflow_executions USING btree (id);

CREATE UNIQUE INDEX workflows_pkey ON public.workflows USING btree (id);

alter table "public"."action_items" add constraint "action_items_pkey" PRIMARY KEY using index "action_items_pkey";

alter table "public"."approval_queue" add constraint "approval_queue_pkey" PRIMARY KEY using index "approval_queue_pkey";

alter table "public"."campaign_enrollments" add constraint "campaign_enrollments_pkey" PRIMARY KEY using index "campaign_enrollments_pkey";

alter table "public"."campaign_sequences" add constraint "campaign_sequences_pkey" PRIMARY KEY using index "campaign_sequences_pkey";

alter table "public"."email_templates" add constraint "email_templates_pkey" PRIMARY KEY using index "email_templates_pkey";

alter table "public"."system_config" add constraint "system_config_pkey" PRIMARY KEY using index "system_config_pkey";

alter table "public"."workflow_executions" add constraint "workflow_executions_pkey" PRIMARY KEY using index "workflow_executions_pkey";

alter table "public"."workflows" add constraint "workflows_pkey" PRIMARY KEY using index "workflows_pkey";

alter table "public"."action_items" add constraint "action_items_action_type_check" CHECK (((action_type)::text = ANY ((ARRAY['follow_up'::character varying, 'call'::character varying, 'meeting'::character varying, 'review'::character varying, 'other'::character varying])::text[]))) not valid;

alter table "public"."action_items" validate constraint "action_items_action_type_check";

alter table "public"."action_items" add constraint "action_items_assigned_to_fkey" FOREIGN KEY (assigned_to) REFERENCES public.profiles(profile_id) ON DELETE SET NULL not valid;

alter table "public"."action_items" validate constraint "action_items_assigned_to_fkey";

alter table "public"."action_items" add constraint "action_items_completed_by_fkey" FOREIGN KEY (completed_by) REFERENCES public.profiles(profile_id) ON DELETE SET NULL not valid;

alter table "public"."action_items" validate constraint "action_items_completed_by_fkey";

alter table "public"."action_items" add constraint "action_items_contact_id_fkey" FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE not valid;

alter table "public"."action_items" validate constraint "action_items_contact_id_fkey";

alter table "public"."action_items" add constraint "action_items_email_id_fkey" FOREIGN KEY (email_id) REFERENCES public.emails(id) ON DELETE SET NULL not valid;

alter table "public"."action_items" validate constraint "action_items_email_id_fkey";

alter table "public"."action_items" add constraint "action_items_priority_check" CHECK (((priority)::text = ANY ((ARRAY['low'::character varying, 'medium'::character varying, 'high'::character varying, 'urgent'::character varying])::text[]))) not valid;

alter table "public"."action_items" validate constraint "action_items_priority_check";

alter table "public"."action_items" add constraint "action_items_status_check" CHECK (((status)::text = ANY ((ARRAY['open'::character varying, 'in_progress'::character varying, 'completed'::character varying, 'cancelled'::character varying])::text[]))) not valid;

alter table "public"."action_items" validate constraint "action_items_status_check";

alter table "public"."action_items" add constraint "action_items_workflow_execution_id_fkey" FOREIGN KEY (workflow_execution_id) REFERENCES public.workflow_executions(id) ON DELETE SET NULL not valid;

alter table "public"."action_items" validate constraint "action_items_workflow_execution_id_fkey";

alter table "public"."approval_queue" add constraint "approval_queue_decided_by_fkey" FOREIGN KEY (decided_by) REFERENCES public.profiles(profile_id) not valid;

alter table "public"."approval_queue" validate constraint "approval_queue_decided_by_fkey";

alter table "public"."approval_queue" add constraint "approval_queue_status_check" CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'approved'::character varying, 'rejected'::character varying, 'modified'::character varying])::text[]))) not valid;

alter table "public"."approval_queue" validate constraint "approval_queue_status_check";

alter table "public"."approval_queue" add constraint "approval_queue_workflow_execution_id_fkey" FOREIGN KEY (workflow_execution_id) REFERENCES public.workflow_executions(id) ON DELETE CASCADE not valid;

alter table "public"."approval_queue" validate constraint "approval_queue_workflow_execution_id_fkey";

alter table "public"."campaign_enrollments" add constraint "campaign_enrollments_campaign_sequence_id_contact_id_key" UNIQUE using index "campaign_enrollments_campaign_sequence_id_contact_id_key";

alter table "public"."campaign_enrollments" add constraint "campaign_enrollments_campaign_sequence_id_fkey" FOREIGN KEY (campaign_sequence_id) REFERENCES public.campaign_sequences(id) ON DELETE CASCADE not valid;

alter table "public"."campaign_enrollments" validate constraint "campaign_enrollments_campaign_sequence_id_fkey";

alter table "public"."campaign_enrollments" add constraint "campaign_enrollments_contact_id_fkey" FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE not valid;

alter table "public"."campaign_enrollments" validate constraint "campaign_enrollments_contact_id_fkey";

alter table "public"."campaign_enrollments" add constraint "campaign_enrollments_status_check" CHECK (((status)::text = ANY ((ARRAY['enrolled'::character varying, 'active'::character varying, 'completed'::character varying, 'unsubscribed'::character varying, 'bounced'::character varying, 'paused'::character varying])::text[]))) not valid;

alter table "public"."campaign_enrollments" validate constraint "campaign_enrollments_status_check";

alter table "public"."campaign_sequences" add constraint "campaign_sequences_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.profiles(profile_id) not valid;

alter table "public"."campaign_sequences" validate constraint "campaign_sequences_created_by_fkey";

alter table "public"."campaign_sequences" add constraint "campaign_sequences_from_mailbox_id_fkey" FOREIGN KEY (from_mailbox_id) REFERENCES public.mailboxes(id) not valid;

alter table "public"."campaign_sequences" validate constraint "campaign_sequences_from_mailbox_id_fkey";

alter table "public"."campaign_sequences" add constraint "campaign_sequences_product_id_fkey" FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL not valid;

alter table "public"."campaign_sequences" validate constraint "campaign_sequences_product_id_fkey";

alter table "public"."campaign_sequences" add constraint "campaign_sequences_status_check" CHECK (((status)::text = ANY ((ARRAY['draft'::character varying, 'scheduled'::character varying, 'running'::character varying, 'completed'::character varying, 'paused'::character varying, 'cancelled'::character varying])::text[]))) not valid;

alter table "public"."campaign_sequences" validate constraint "campaign_sequences_status_check";

alter table "public"."email_templates" add constraint "email_templates_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.profiles(profile_id) not valid;

alter table "public"."email_templates" validate constraint "email_templates_created_by_fkey";

alter table "public"."workflow_executions" add constraint "workflow_executions_email_id_fkey" FOREIGN KEY (email_id) REFERENCES public.emails(id) ON DELETE CASCADE not valid;

alter table "public"."workflow_executions" validate constraint "workflow_executions_email_id_fkey";

alter table "public"."workflow_executions" add constraint "workflow_executions_extraction_confidence_check" CHECK (((extraction_confidence >= (0)::double precision) AND (extraction_confidence <= (1)::double precision))) not valid;

alter table "public"."workflow_executions" validate constraint "workflow_executions_extraction_confidence_check";

alter table "public"."workflow_executions" add constraint "workflow_executions_status_check" CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'extracting'::character varying, 'executing'::character varying, 'awaiting_approval'::character varying, 'completed'::character varying, 'failed'::character varying])::text[]))) not valid;

alter table "public"."workflow_executions" validate constraint "workflow_executions_status_check";

alter table "public"."workflow_executions" add constraint "workflow_executions_workflow_id_fkey" FOREIGN KEY (workflow_id) REFERENCES public.workflows(id) ON DELETE CASCADE not valid;

alter table "public"."workflow_executions" validate constraint "workflow_executions_workflow_id_fkey";

alter table "public"."workflows" add constraint "workflows_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.profiles(profile_id) not valid;

alter table "public"."workflows" validate constraint "workflows_created_by_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.category_matches_workflow_rules(p_category character varying, p_rules jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    enabled_pattern VARCHAR;
    disabled_categories JSONB;
    disabled_cat VARCHAR;
BEGIN
    -- Get rules
    enabled_pattern := p_rules->>'enabled_pattern';
    disabled_categories := p_rules->'disabled_categories';

    -- Check if explicitly disabled
    IF disabled_categories IS NOT NULL THEN
        FOR disabled_cat IN SELECT jsonb_array_elements_text(disabled_categories) LOOP
            -- Check wildcard match (e.g., 'spam-*')
            IF disabled_cat LIKE '%*' THEN
                IF p_category LIKE REPLACE(disabled_cat, '*', '%') THEN
                    RETURN FALSE;
                END IF;
            -- Check exact match
            ELSIF p_category = disabled_cat THEN
                RETURN FALSE;
            END IF;
        END LOOP;
    END IF;

    -- Check if matches enabled pattern
    IF enabled_pattern LIKE '%*' THEN
        RETURN p_category LIKE REPLACE(enabled_pattern, '*', '%');
    ELSE
        RETURN p_category = enabled_pattern;
    END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_campaign_enrollments_due()
 RETURNS TABLE(enrollment_id uuid, campaign_sequence_id uuid, campaign_name character varying, contact_id uuid, contact_email character varying, current_step integer, next_send_date timestamp with time zone)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        ce.id,
        ce.campaign_sequence_id,
        cs.name,
        ce.contact_id,
        c.email,
        ce.current_step,
        ce.next_send_date
    FROM public.campaign_enrollments ce
    JOIN public.campaign_sequences cs ON ce.campaign_sequence_id = cs.id
    JOIN public.contacts c ON ce.contact_id = c.id
    WHERE ce.status = 'active'
      AND ce.next_send_date <= NOW()
      AND cs.status = 'running';
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_category_group(p_category character varying)
 RETURNS character varying
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    valid_categories JSONB;
    category_group TEXT;
    categories JSONB;
BEGIN
    SELECT value INTO valid_categories
    FROM public.system_config
    WHERE key = 'valid_email_categories';

    IF valid_categories IS NULL THEN
        RETURN 'other';
    END IF;

    FOR category_group IN SELECT jsonb_object_keys(valid_categories)
    LOOP
        categories := valid_categories->category_group;
        IF categories ? p_category THEN
            RETURN category_group;
        END IF;
    END LOOP;

    RETURN 'other';
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_workflows_for_category(p_category character varying)
 RETURNS TABLE(workflow_id uuid, workflow_name character varying, priority integer)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY
    SELECT w.id, w.name, w.priority
    FROM public.workflows w
    WHERE w.is_active = true
      AND public.category_matches_workflow_rules(p_category, w.category_rules)
    ORDER BY w.priority DESC;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.is_valid_email_category(p_category character varying)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    valid_categories JSONB;
    category_group TEXT;
    categories JSONB;
BEGIN
    -- Get valid categories from system_config
    SELECT value INTO valid_categories
    FROM public.system_config
    WHERE key = 'valid_email_categories';

    IF valid_categories IS NULL THEN
        RETURN TRUE; -- If no validation config, allow all
    END IF;

    -- Check each category group
    FOR category_group IN SELECT jsonb_object_keys(valid_categories)
    LOOP
        categories := valid_categories->category_group;
        IF categories ? p_category THEN
            RETURN TRUE;
        END IF;
    END LOOP;

    RETURN FALSE;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.is_valid_email_intent(p_intent character varying)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    valid_intents JSONB;
BEGIN
    SELECT value->'intents' INTO valid_intents
    FROM public.system_config
    WHERE key = 'valid_email_intents';

    IF valid_intents IS NULL THEN
        RETURN TRUE;
    END IF;

    RETURN valid_intents ? p_intent;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.is_valid_email_sentiment(p_sentiment character varying)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    valid_sentiments JSONB;
BEGIN
    SELECT value->'sentiments' INTO valid_sentiments
    FROM public.system_config
    WHERE key = 'valid_email_sentiments';

    IF valid_sentiments IS NULL THEN
        RETURN TRUE;
    END IF;

    RETURN valid_sentiments ? p_sentiment;
END;
$function$
;

create or replace view "public"."v_campaign_enrollments_due" as  SELECT ce.id AS enrollment_id,
    ce.campaign_sequence_id,
    cs.name AS campaign_name,
    cs.steps,
    ce.contact_id,
    c.email AS contact_email,
    c.first_name,
    c.last_name,
    ce.current_step,
    ce.next_send_date,
    ce.steps_completed,
    cs.from_mailbox_id,
    m.email AS from_mailbox_email
   FROM (((public.campaign_enrollments ce
     JOIN public.campaign_sequences cs ON ((ce.campaign_sequence_id = cs.id)))
     JOIN public.contacts c ON ((ce.contact_id = c.id)))
     LEFT JOIN public.mailboxes m ON ((cs.from_mailbox_id = m.id)))
  WHERE (((ce.status)::text = 'active'::text) AND (ce.next_send_date <= now()) AND ((cs.status)::text = 'running'::text))
  ORDER BY ce.next_send_date;


create or replace view "public"."v_campaign_sequences_with_stats" as  SELECT cs.id,
    cs.name,
    cs.description,
    cs.status,
    cs.product_id,
    p.product_name,
    cs.from_mailbox_id,
    m.email AS from_mailbox_email,
    cs.target_count,
    cs.scheduled_at,
    cs.started_at,
    cs.completed_at,
    cs.stats,
    count(ce.id) AS total_enrollments,
    count(ce.id) FILTER (WHERE ((ce.status)::text = 'active'::text)) AS active_enrollments,
    count(ce.id) FILTER (WHERE ((ce.status)::text = 'completed'::text)) AS completed_enrollments,
    count(ce.id) FILTER (WHERE (ce.replied = true)) AS replied_count,
    avg(ce.total_opens) AS avg_opens_per_contact,
    avg(ce.total_clicks) AS avg_clicks_per_contact,
    cs.created_at,
    cs.updated_at
   FROM (((public.campaign_sequences cs
     LEFT JOIN public.campaign_enrollments ce ON ((cs.id = ce.campaign_sequence_id)))
     LEFT JOIN public.products p ON ((cs.product_id = p.id)))
     LEFT JOIN public.mailboxes m ON ((cs.from_mailbox_id = m.id)))
  GROUP BY cs.id, p.product_name, m.email;


create or replace view "public"."v_enrichment_config" as  SELECT 'valid_categories'::text AS config_type,
    (((jsonb_array_length((system_config.value -> 'business'::text)) + jsonb_array_length((system_config.value -> 'spam'::text))) + jsonb_array_length((system_config.value -> 'personal'::text))) + jsonb_array_length((system_config.value -> 'other'::text))) AS total_count,
    system_config.value AS config_value
   FROM public.system_config
  WHERE ((system_config.key)::text = 'valid_email_categories'::text)
UNION ALL
 SELECT 'valid_intents'::text AS config_type,
    jsonb_array_length((system_config.value -> 'intents'::text)) AS total_count,
    system_config.value AS config_value
   FROM public.system_config
  WHERE ((system_config.key)::text = 'valid_email_intents'::text)
UNION ALL
 SELECT 'valid_sentiments'::text AS config_type,
    jsonb_array_length((system_config.value -> 'sentiments'::text)) AS total_count,
    system_config.value AS config_value
   FROM public.system_config
  WHERE ((system_config.key)::text = 'valid_email_sentiments'::text)
UNION ALL
 SELECT 'workflow_category_rules'::text AS config_type,
    (jsonb_array_length((system_config.value -> 'enabled_categories'::text)) + jsonb_array_length((system_config.value -> 'disabled_categories'::text))) AS total_count,
    system_config.value AS config_value
   FROM public.system_config
  WHERE ((system_config.key)::text = 'workflow_category_rules'::text);


create or replace view "public"."v_enrichment_stats" as  SELECT 'emails'::text AS table_name,
    count(*) AS total_records,
    count(emails.email_category) AS enriched_category,
    count(emails.intent) AS enriched_intent,
    count(emails.sentiment) AS enriched_sentiment,
    count(emails.priority_score) AS enriched_priority,
    round(avg(emails.ai_confidence_score), 2) AS avg_confidence,
    count(emails.ai_processed_at) AS ai_processed_count
   FROM public.emails
UNION ALL
 SELECT 'contacts'::text AS table_name,
    count(*) AS total_records,
    count(contacts.role) AS enriched_category,
    count(contacts.department) AS enriched_intent,
    count(contacts.lead_score) AS enriched_sentiment,
    NULL::bigint AS enriched_priority,
    NULL::numeric AS avg_confidence,
    count(contacts.enrichment_last_attempted_at) AS ai_processed_count
   FROM public.contacts
UNION ALL
 SELECT 'conversations'::text AS table_name,
    count(*) AS total_records,
    count(conversations.summary) AS enriched_category,
    count(conversations.action_items) AS enriched_intent,
    NULL::bigint AS enriched_sentiment,
    NULL::bigint AS enriched_priority,
    NULL::numeric AS avg_confidence,
    count(conversations.last_summarized_at) AS ai_processed_count
   FROM public.conversations;


CREATE OR REPLACE FUNCTION public.get_current_user_role()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
BEGIN
  PERFORM set_config('search_path', 'public,pg_temp', true);
  
  RETURN (
    SELECT role::text
    FROM profiles 
    WHERE auth_user_id = auth.uid()
    LIMIT 1
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
BEGIN
  PERFORM set_config('search_path', 'public,pg_temp', true);
  
  RETURN COALESCE(
    (SELECT role = 'admin' FROM profiles WHERE auth_user_id = auth.uid() LIMIT 1),
    FALSE
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.is_valid_permission(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT p IN (
    'view_users', 'manage_users', 'view_contacts', 'manage_contacts',
    'view_campaigns', 'manage_campaigns', 'approve_campaigns',
    'view_analytics', 'manage_approvals', 'view_workflows', 'view_emails'
  )
$function$
;

create or replace view "public"."profiles_with_email" as  SELECT p.profile_id,
    p.auth_user_id,
    p.full_name,
    p.role,
    p.created_at,
    p.updated_at,
    u.email
   FROM (public.profiles p
     JOIN auth.users u ON ((u.id = p.auth_user_id)));


CREATE OR REPLACE FUNCTION public.remove_user_permission_overrides(target_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    PERFORM set_config('search_path', 'public,pg_temp', true);
    
    IF NOT public.has_permission('manage_users') THEN
        RAISE EXCEPTION 'Unauthorized: manage_users permission required';
    END IF;
    
    DELETE FROM public.user_permissions
    WHERE auth_user_id = target_user_id;
    
    RAISE NOTICE 'Removed all permission overrides for user %', target_user_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.touch_role_permissions_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.update_lead_classification()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.lead_score >= 80 THEN
    NEW.lead_classification := 'hot';
  ELSIF NEW.lead_score >= 50 THEN
    NEW.lead_classification := 'warm';
  ELSE
    NEW.lead_classification := 'cold';
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$
;

grant delete on table "public"."action_items" to "anon";

grant insert on table "public"."action_items" to "anon";

grant references on table "public"."action_items" to "anon";

grant select on table "public"."action_items" to "anon";

grant trigger on table "public"."action_items" to "anon";

grant truncate on table "public"."action_items" to "anon";

grant update on table "public"."action_items" to "anon";

grant delete on table "public"."action_items" to "authenticated";

grant insert on table "public"."action_items" to "authenticated";

grant references on table "public"."action_items" to "authenticated";

grant select on table "public"."action_items" to "authenticated";

grant trigger on table "public"."action_items" to "authenticated";

grant truncate on table "public"."action_items" to "authenticated";

grant update on table "public"."action_items" to "authenticated";

grant delete on table "public"."action_items" to "service_role";

grant insert on table "public"."action_items" to "service_role";

grant references on table "public"."action_items" to "service_role";

grant select on table "public"."action_items" to "service_role";

grant trigger on table "public"."action_items" to "service_role";

grant truncate on table "public"."action_items" to "service_role";

grant update on table "public"."action_items" to "service_role";

grant delete on table "public"."approval_queue" to "anon";

grant insert on table "public"."approval_queue" to "anon";

grant references on table "public"."approval_queue" to "anon";

grant select on table "public"."approval_queue" to "anon";

grant trigger on table "public"."approval_queue" to "anon";

grant truncate on table "public"."approval_queue" to "anon";

grant update on table "public"."approval_queue" to "anon";

grant delete on table "public"."approval_queue" to "authenticated";

grant insert on table "public"."approval_queue" to "authenticated";

grant references on table "public"."approval_queue" to "authenticated";

grant select on table "public"."approval_queue" to "authenticated";

grant trigger on table "public"."approval_queue" to "authenticated";

grant truncate on table "public"."approval_queue" to "authenticated";

grant update on table "public"."approval_queue" to "authenticated";

grant delete on table "public"."approval_queue" to "service_role";

grant insert on table "public"."approval_queue" to "service_role";

grant references on table "public"."approval_queue" to "service_role";

grant select on table "public"."approval_queue" to "service_role";

grant trigger on table "public"."approval_queue" to "service_role";

grant truncate on table "public"."approval_queue" to "service_role";

grant update on table "public"."approval_queue" to "service_role";

grant delete on table "public"."campaign_enrollments" to "anon";

grant insert on table "public"."campaign_enrollments" to "anon";

grant references on table "public"."campaign_enrollments" to "anon";

grant select on table "public"."campaign_enrollments" to "anon";

grant trigger on table "public"."campaign_enrollments" to "anon";

grant truncate on table "public"."campaign_enrollments" to "anon";

grant update on table "public"."campaign_enrollments" to "anon";

grant delete on table "public"."campaign_enrollments" to "authenticated";

grant insert on table "public"."campaign_enrollments" to "authenticated";

grant references on table "public"."campaign_enrollments" to "authenticated";

grant select on table "public"."campaign_enrollments" to "authenticated";

grant trigger on table "public"."campaign_enrollments" to "authenticated";

grant truncate on table "public"."campaign_enrollments" to "authenticated";

grant update on table "public"."campaign_enrollments" to "authenticated";

grant delete on table "public"."campaign_enrollments" to "service_role";

grant insert on table "public"."campaign_enrollments" to "service_role";

grant references on table "public"."campaign_enrollments" to "service_role";

grant select on table "public"."campaign_enrollments" to "service_role";

grant trigger on table "public"."campaign_enrollments" to "service_role";

grant truncate on table "public"."campaign_enrollments" to "service_role";

grant update on table "public"."campaign_enrollments" to "service_role";

grant delete on table "public"."campaign_sequences" to "anon";

grant insert on table "public"."campaign_sequences" to "anon";

grant references on table "public"."campaign_sequences" to "anon";

grant select on table "public"."campaign_sequences" to "anon";

grant trigger on table "public"."campaign_sequences" to "anon";

grant truncate on table "public"."campaign_sequences" to "anon";

grant update on table "public"."campaign_sequences" to "anon";

grant delete on table "public"."campaign_sequences" to "authenticated";

grant insert on table "public"."campaign_sequences" to "authenticated";

grant references on table "public"."campaign_sequences" to "authenticated";

grant select on table "public"."campaign_sequences" to "authenticated";

grant trigger on table "public"."campaign_sequences" to "authenticated";

grant truncate on table "public"."campaign_sequences" to "authenticated";

grant update on table "public"."campaign_sequences" to "authenticated";

grant delete on table "public"."campaign_sequences" to "service_role";

grant insert on table "public"."campaign_sequences" to "service_role";

grant references on table "public"."campaign_sequences" to "service_role";

grant select on table "public"."campaign_sequences" to "service_role";

grant trigger on table "public"."campaign_sequences" to "service_role";

grant truncate on table "public"."campaign_sequences" to "service_role";

grant update on table "public"."campaign_sequences" to "service_role";

grant delete on table "public"."email_templates" to "anon";

grant insert on table "public"."email_templates" to "anon";

grant references on table "public"."email_templates" to "anon";

grant select on table "public"."email_templates" to "anon";

grant trigger on table "public"."email_templates" to "anon";

grant truncate on table "public"."email_templates" to "anon";

grant update on table "public"."email_templates" to "anon";

grant delete on table "public"."email_templates" to "authenticated";

grant insert on table "public"."email_templates" to "authenticated";

grant references on table "public"."email_templates" to "authenticated";

grant select on table "public"."email_templates" to "authenticated";

grant trigger on table "public"."email_templates" to "authenticated";

grant truncate on table "public"."email_templates" to "authenticated";

grant update on table "public"."email_templates" to "authenticated";

grant delete on table "public"."email_templates" to "service_role";

grant insert on table "public"."email_templates" to "service_role";

grant references on table "public"."email_templates" to "service_role";

grant select on table "public"."email_templates" to "service_role";

grant trigger on table "public"."email_templates" to "service_role";

grant truncate on table "public"."email_templates" to "service_role";

grant update on table "public"."email_templates" to "service_role";

grant delete on table "public"."system_config" to "anon";

grant insert on table "public"."system_config" to "anon";

grant references on table "public"."system_config" to "anon";

grant select on table "public"."system_config" to "anon";

grant trigger on table "public"."system_config" to "anon";

grant truncate on table "public"."system_config" to "anon";

grant update on table "public"."system_config" to "anon";

grant delete on table "public"."system_config" to "authenticated";

grant insert on table "public"."system_config" to "authenticated";

grant references on table "public"."system_config" to "authenticated";

grant select on table "public"."system_config" to "authenticated";

grant trigger on table "public"."system_config" to "authenticated";

grant truncate on table "public"."system_config" to "authenticated";

grant update on table "public"."system_config" to "authenticated";

grant delete on table "public"."system_config" to "service_role";

grant insert on table "public"."system_config" to "service_role";

grant references on table "public"."system_config" to "service_role";

grant select on table "public"."system_config" to "service_role";

grant trigger on table "public"."system_config" to "service_role";

grant truncate on table "public"."system_config" to "service_role";

grant update on table "public"."system_config" to "service_role";

grant delete on table "public"."workflow_executions" to "anon";

grant insert on table "public"."workflow_executions" to "anon";

grant references on table "public"."workflow_executions" to "anon";

grant select on table "public"."workflow_executions" to "anon";

grant trigger on table "public"."workflow_executions" to "anon";

grant truncate on table "public"."workflow_executions" to "anon";

grant update on table "public"."workflow_executions" to "anon";

grant delete on table "public"."workflow_executions" to "authenticated";

grant insert on table "public"."workflow_executions" to "authenticated";

grant references on table "public"."workflow_executions" to "authenticated";

grant select on table "public"."workflow_executions" to "authenticated";

grant trigger on table "public"."workflow_executions" to "authenticated";

grant truncate on table "public"."workflow_executions" to "authenticated";

grant update on table "public"."workflow_executions" to "authenticated";

grant delete on table "public"."workflow_executions" to "service_role";

grant insert on table "public"."workflow_executions" to "service_role";

grant references on table "public"."workflow_executions" to "service_role";

grant select on table "public"."workflow_executions" to "service_role";

grant trigger on table "public"."workflow_executions" to "service_role";

grant truncate on table "public"."workflow_executions" to "service_role";

grant update on table "public"."workflow_executions" to "service_role";

grant delete on table "public"."workflows" to "anon";

grant insert on table "public"."workflows" to "anon";

grant references on table "public"."workflows" to "anon";

grant select on table "public"."workflows" to "anon";

grant trigger on table "public"."workflows" to "anon";

grant truncate on table "public"."workflows" to "anon";

grant update on table "public"."workflows" to "anon";

grant delete on table "public"."workflows" to "authenticated";

grant insert on table "public"."workflows" to "authenticated";

grant references on table "public"."workflows" to "authenticated";

grant select on table "public"."workflows" to "authenticated";

grant trigger on table "public"."workflows" to "authenticated";

grant truncate on table "public"."workflows" to "authenticated";

grant update on table "public"."workflows" to "authenticated";

grant delete on table "public"."workflows" to "service_role";

grant insert on table "public"."workflows" to "service_role";

grant references on table "public"."workflows" to "service_role";

grant select on table "public"."workflows" to "service_role";

grant trigger on table "public"."workflows" to "service_role";

grant truncate on table "public"."workflows" to "service_role";

grant update on table "public"."workflows" to "service_role";

CREATE TRIGGER update_action_items_updated_at BEFORE UPDATE ON public.action_items FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_campaign_sequences_updated_at BEFORE UPDATE ON public.campaign_sequences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_email_templates_updated_at BEFORE UPDATE ON public.email_templates FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_system_config_updated_at BEFORE UPDATE ON public.system_config FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_workflows_updated_at BEFORE UPDATE ON public.workflows FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


