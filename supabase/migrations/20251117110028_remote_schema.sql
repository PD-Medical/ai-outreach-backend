drop extension if exists "pg_net";

drop extension if exists "uuid-ossp";

create extension if not exists "pg_net" with schema "public";

create extension if not exists "uuid-ossp" with schema "public";

drop trigger if exists "update_action_items_updated_at" on "public"."action_items";

drop trigger if exists "update_campaign_sequences_updated_at" on "public"."campaign_sequences";

drop trigger if exists "trigger_campaigns_auth_tracking" on "public"."campaigns";

drop trigger if exists "trigger_contact_product_interests_auth_tracking" on "public"."contact_product_interests";

drop trigger if exists "trigger_contacts_auth_tracking" on "public"."contacts";

drop trigger if exists "trigger_conversations_auth_tracking" on "public"."conversations";

drop trigger if exists "update_email_templates_updated_at" on "public"."email_templates";

drop trigger if exists "trigger_emails_auth_tracking" on "public"."emails";

drop trigger if exists "trigger_organizations_auth_tracking" on "public"."organizations";

drop trigger if exists "update_system_config_updated_at" on "public"."system_config";

drop trigger if exists "update_workflows_updated_at" on "public"."workflows";

drop policy "Admins can manage profiles" on "public"."profiles";

drop policy "Admins can read all profiles" on "public"."profiles";

drop policy "Users can read their own profile" on "public"."profiles";

revoke delete on table "public"."action_items" from "anon";

revoke insert on table "public"."action_items" from "anon";

revoke references on table "public"."action_items" from "anon";

revoke select on table "public"."action_items" from "anon";

revoke trigger on table "public"."action_items" from "anon";

revoke truncate on table "public"."action_items" from "anon";

revoke update on table "public"."action_items" from "anon";

revoke delete on table "public"."action_items" from "authenticated";

revoke insert on table "public"."action_items" from "authenticated";

revoke references on table "public"."action_items" from "authenticated";

revoke select on table "public"."action_items" from "authenticated";

revoke trigger on table "public"."action_items" from "authenticated";

revoke truncate on table "public"."action_items" from "authenticated";

revoke update on table "public"."action_items" from "authenticated";

revoke delete on table "public"."action_items" from "service_role";

revoke insert on table "public"."action_items" from "service_role";

revoke references on table "public"."action_items" from "service_role";

revoke select on table "public"."action_items" from "service_role";

revoke trigger on table "public"."action_items" from "service_role";

revoke truncate on table "public"."action_items" from "service_role";

revoke update on table "public"."action_items" from "service_role";

revoke delete on table "public"."approval_queue" from "anon";

revoke insert on table "public"."approval_queue" from "anon";

revoke references on table "public"."approval_queue" from "anon";

revoke select on table "public"."approval_queue" from "anon";

revoke trigger on table "public"."approval_queue" from "anon";

revoke truncate on table "public"."approval_queue" from "anon";

revoke update on table "public"."approval_queue" from "anon";

revoke delete on table "public"."approval_queue" from "authenticated";

revoke insert on table "public"."approval_queue" from "authenticated";

revoke references on table "public"."approval_queue" from "authenticated";

revoke select on table "public"."approval_queue" from "authenticated";

revoke trigger on table "public"."approval_queue" from "authenticated";

revoke truncate on table "public"."approval_queue" from "authenticated";

revoke update on table "public"."approval_queue" from "authenticated";

revoke delete on table "public"."approval_queue" from "service_role";

revoke insert on table "public"."approval_queue" from "service_role";

revoke references on table "public"."approval_queue" from "service_role";

revoke select on table "public"."approval_queue" from "service_role";

revoke trigger on table "public"."approval_queue" from "service_role";

revoke truncate on table "public"."approval_queue" from "service_role";

revoke update on table "public"."approval_queue" from "service_role";

revoke delete on table "public"."campaign_enrollments" from "anon";

revoke insert on table "public"."campaign_enrollments" from "anon";

revoke references on table "public"."campaign_enrollments" from "anon";

revoke select on table "public"."campaign_enrollments" from "anon";

revoke trigger on table "public"."campaign_enrollments" from "anon";

revoke truncate on table "public"."campaign_enrollments" from "anon";

revoke update on table "public"."campaign_enrollments" from "anon";

revoke delete on table "public"."campaign_enrollments" from "authenticated";

revoke insert on table "public"."campaign_enrollments" from "authenticated";

revoke references on table "public"."campaign_enrollments" from "authenticated";

revoke select on table "public"."campaign_enrollments" from "authenticated";

revoke trigger on table "public"."campaign_enrollments" from "authenticated";

revoke truncate on table "public"."campaign_enrollments" from "authenticated";

revoke update on table "public"."campaign_enrollments" from "authenticated";

revoke delete on table "public"."campaign_enrollments" from "service_role";

revoke insert on table "public"."campaign_enrollments" from "service_role";

revoke references on table "public"."campaign_enrollments" from "service_role";

revoke select on table "public"."campaign_enrollments" from "service_role";

revoke trigger on table "public"."campaign_enrollments" from "service_role";

revoke truncate on table "public"."campaign_enrollments" from "service_role";

revoke update on table "public"."campaign_enrollments" from "service_role";

revoke delete on table "public"."campaign_sequences" from "anon";

revoke insert on table "public"."campaign_sequences" from "anon";

revoke references on table "public"."campaign_sequences" from "anon";

revoke select on table "public"."campaign_sequences" from "anon";

revoke trigger on table "public"."campaign_sequences" from "anon";

revoke truncate on table "public"."campaign_sequences" from "anon";

revoke update on table "public"."campaign_sequences" from "anon";

revoke delete on table "public"."campaign_sequences" from "authenticated";

revoke insert on table "public"."campaign_sequences" from "authenticated";

revoke references on table "public"."campaign_sequences" from "authenticated";

revoke select on table "public"."campaign_sequences" from "authenticated";

revoke trigger on table "public"."campaign_sequences" from "authenticated";

revoke truncate on table "public"."campaign_sequences" from "authenticated";

revoke update on table "public"."campaign_sequences" from "authenticated";

revoke delete on table "public"."campaign_sequences" from "service_role";

revoke insert on table "public"."campaign_sequences" from "service_role";

revoke references on table "public"."campaign_sequences" from "service_role";

revoke select on table "public"."campaign_sequences" from "service_role";

revoke trigger on table "public"."campaign_sequences" from "service_role";

revoke truncate on table "public"."campaign_sequences" from "service_role";

revoke update on table "public"."campaign_sequences" from "service_role";

revoke delete on table "public"."email_templates" from "anon";

revoke insert on table "public"."email_templates" from "anon";

revoke references on table "public"."email_templates" from "anon";

revoke select on table "public"."email_templates" from "anon";

revoke trigger on table "public"."email_templates" from "anon";

revoke truncate on table "public"."email_templates" from "anon";

revoke update on table "public"."email_templates" from "anon";

revoke delete on table "public"."email_templates" from "authenticated";

revoke insert on table "public"."email_templates" from "authenticated";

revoke references on table "public"."email_templates" from "authenticated";

revoke select on table "public"."email_templates" from "authenticated";

revoke trigger on table "public"."email_templates" from "authenticated";

revoke truncate on table "public"."email_templates" from "authenticated";

revoke update on table "public"."email_templates" from "authenticated";

revoke delete on table "public"."email_templates" from "service_role";

revoke insert on table "public"."email_templates" from "service_role";

revoke references on table "public"."email_templates" from "service_role";

revoke select on table "public"."email_templates" from "service_role";

revoke trigger on table "public"."email_templates" from "service_role";

revoke truncate on table "public"."email_templates" from "service_role";

revoke update on table "public"."email_templates" from "service_role";

revoke delete on table "public"."system_config" from "anon";

revoke insert on table "public"."system_config" from "anon";

revoke references on table "public"."system_config" from "anon";

revoke select on table "public"."system_config" from "anon";

revoke trigger on table "public"."system_config" from "anon";

revoke truncate on table "public"."system_config" from "anon";

revoke update on table "public"."system_config" from "anon";

revoke delete on table "public"."system_config" from "authenticated";

revoke insert on table "public"."system_config" from "authenticated";

revoke references on table "public"."system_config" from "authenticated";

revoke select on table "public"."system_config" from "authenticated";

revoke trigger on table "public"."system_config" from "authenticated";

revoke truncate on table "public"."system_config" from "authenticated";

revoke update on table "public"."system_config" from "authenticated";

revoke delete on table "public"."system_config" from "service_role";

revoke insert on table "public"."system_config" from "service_role";

revoke references on table "public"."system_config" from "service_role";

revoke select on table "public"."system_config" from "service_role";

revoke trigger on table "public"."system_config" from "service_role";

revoke truncate on table "public"."system_config" from "service_role";

revoke update on table "public"."system_config" from "service_role";

revoke delete on table "public"."workflow_executions" from "anon";

revoke insert on table "public"."workflow_executions" from "anon";

revoke references on table "public"."workflow_executions" from "anon";

revoke select on table "public"."workflow_executions" from "anon";

revoke trigger on table "public"."workflow_executions" from "anon";

revoke truncate on table "public"."workflow_executions" from "anon";

revoke update on table "public"."workflow_executions" from "anon";

revoke delete on table "public"."workflow_executions" from "authenticated";

revoke insert on table "public"."workflow_executions" from "authenticated";

revoke references on table "public"."workflow_executions" from "authenticated";

revoke select on table "public"."workflow_executions" from "authenticated";

revoke trigger on table "public"."workflow_executions" from "authenticated";

revoke truncate on table "public"."workflow_executions" from "authenticated";

revoke update on table "public"."workflow_executions" from "authenticated";

revoke delete on table "public"."workflow_executions" from "service_role";

revoke insert on table "public"."workflow_executions" from "service_role";

revoke references on table "public"."workflow_executions" from "service_role";

revoke select on table "public"."workflow_executions" from "service_role";

revoke trigger on table "public"."workflow_executions" from "service_role";

revoke truncate on table "public"."workflow_executions" from "service_role";

revoke update on table "public"."workflow_executions" from "service_role";

revoke delete on table "public"."workflows" from "anon";

revoke insert on table "public"."workflows" from "anon";

revoke references on table "public"."workflows" from "anon";

revoke select on table "public"."workflows" from "anon";

revoke trigger on table "public"."workflows" from "anon";

revoke truncate on table "public"."workflows" from "anon";

revoke update on table "public"."workflows" from "anon";

revoke delete on table "public"."workflows" from "authenticated";

revoke insert on table "public"."workflows" from "authenticated";

revoke references on table "public"."workflows" from "authenticated";

revoke select on table "public"."workflows" from "authenticated";

revoke trigger on table "public"."workflows" from "authenticated";

revoke truncate on table "public"."workflows" from "authenticated";

revoke update on table "public"."workflows" from "authenticated";

revoke delete on table "public"."workflows" from "service_role";

revoke insert on table "public"."workflows" from "service_role";

revoke references on table "public"."workflows" from "service_role";

revoke select on table "public"."workflows" from "service_role";

revoke trigger on table "public"."workflows" from "service_role";

revoke truncate on table "public"."workflows" from "service_role";

revoke update on table "public"."workflows" from "service_role";

alter table "public"."action_items" drop constraint "action_items_action_type_check";

alter table "public"."action_items" drop constraint "action_items_assigned_to_fkey";

alter table "public"."action_items" drop constraint "action_items_completed_by_fkey";

alter table "public"."action_items" drop constraint "action_items_contact_id_fkey";

alter table "public"."action_items" drop constraint "action_items_email_id_fkey";

alter table "public"."action_items" drop constraint "action_items_priority_check";

alter table "public"."action_items" drop constraint "action_items_status_check";

alter table "public"."action_items" drop constraint "action_items_workflow_execution_id_fkey";

alter table "public"."approval_queue" drop constraint "approval_queue_decided_by_fkey";

alter table "public"."approval_queue" drop constraint "approval_queue_status_check";

alter table "public"."approval_queue" drop constraint "approval_queue_workflow_execution_id_fkey";

alter table "public"."campaign_enrollments" drop constraint "campaign_enrollments_campaign_sequence_id_contact_id_key";

alter table "public"."campaign_enrollments" drop constraint "campaign_enrollments_campaign_sequence_id_fkey";

alter table "public"."campaign_enrollments" drop constraint "campaign_enrollments_contact_id_fkey";

alter table "public"."campaign_enrollments" drop constraint "campaign_enrollments_status_check";

alter table "public"."campaign_sequences" drop constraint "campaign_sequences_created_by_fkey";

alter table "public"."campaign_sequences" drop constraint "campaign_sequences_from_mailbox_id_fkey";

alter table "public"."campaign_sequences" drop constraint "campaign_sequences_product_id_fkey";

alter table "public"."campaign_sequences" drop constraint "campaign_sequences_status_check";

alter table "public"."email_templates" drop constraint "email_templates_created_by_fkey";

alter table "public"."profiles" drop constraint "profiles_id_fkey";

alter table "public"."workflow_executions" drop constraint "workflow_executions_email_id_fkey";

alter table "public"."workflow_executions" drop constraint "workflow_executions_extraction_confidence_check";

alter table "public"."workflow_executions" drop constraint "workflow_executions_status_check";

alter table "public"."workflow_executions" drop constraint "workflow_executions_workflow_id_fkey";

alter table "public"."workflows" drop constraint "workflows_created_by_fkey";

drop function if exists "public"."category_matches_workflow_rules"(p_category character varying, p_rules jsonb);

drop function if exists "public"."get_campaign_enrollments_due"();

drop function if exists "public"."get_category_group"(p_category character varying);

drop function if exists "public"."get_workflows_for_category"(p_category character varying);

drop function if exists "public"."is_valid_email_category"(p_category character varying);

drop function if exists "public"."is_valid_email_intent"(p_intent character varying);

drop function if exists "public"."is_valid_email_sentiment"(p_sentiment character varying);

drop view if exists "public"."v_campaign_enrollments_due";

drop view if exists "public"."v_campaign_sequences_with_stats";

drop view if exists "public"."v_enrichment_config";

drop view if exists "public"."v_enrichment_stats";

drop view if exists "public"."profiles_with_email";

alter table "public"."action_items" drop constraint "action_items_pkey";

alter table "public"."approval_queue" drop constraint "approval_queue_pkey";

alter table "public"."campaign_enrollments" drop constraint "campaign_enrollments_pkey";

alter table "public"."campaign_sequences" drop constraint "campaign_sequences_pkey";

alter table "public"."email_templates" drop constraint "email_templates_pkey";

alter table "public"."system_config" drop constraint "system_config_pkey";

alter table "public"."workflow_executions" drop constraint "workflow_executions_pkey";

alter table "public"."workflows" drop constraint "workflows_pkey";

alter table "public"."profiles" drop constraint "profiles_pkey";

drop index if exists "public"."action_items_pkey";

drop index if exists "public"."approval_queue_pkey";

drop index if exists "public"."campaign_enrollments_campaign_sequence_id_contact_id_key";

drop index if exists "public"."campaign_enrollments_pkey";

drop index if exists "public"."campaign_sequences_pkey";

drop index if exists "public"."email_templates_pkey";

drop index if exists "public"."idx_action_items_assigned";

drop index if exists "public"."idx_action_items_contact";

drop index if exists "public"."idx_action_items_status_due";

drop index if exists "public"."idx_action_items_workflow";

drop index if exists "public"."idx_approval_queue_decided_by";

drop index if exists "public"."idx_approval_queue_pending";

drop index if exists "public"."idx_approval_queue_workflow_execution";

drop index if exists "public"."idx_campaign_enrollments_campaign";

drop index if exists "public"."idx_campaign_enrollments_contact";

drop index if exists "public"."idx_campaign_enrollments_next_send";

drop index if exists "public"."idx_campaign_enrollments_status";

drop index if exists "public"."idx_campaign_sequences_created_by";

drop index if exists "public"."idx_campaign_sequences_mailbox";

drop index if exists "public"."idx_campaign_sequences_product";

drop index if exists "public"."idx_campaign_sequences_scheduled";

drop index if exists "public"."idx_campaign_sequences_status";

drop index if exists "public"."idx_email_templates_active";

drop index if exists "public"."idx_email_templates_category";

drop index if exists "public"."idx_system_config_key";

drop index if exists "public"."idx_workflow_executions_email";

drop index if exists "public"."idx_workflow_executions_pending";

drop index if exists "public"."idx_workflow_executions_status";

drop index if exists "public"."idx_workflow_executions_workflow";

drop index if exists "public"."idx_workflows_active";

drop index if exists "public"."idx_workflows_active_priority";

drop index if exists "public"."idx_workflows_created_by";

drop index if exists "public"."system_config_pkey";

drop index if exists "public"."workflow_executions_pkey";

drop index if exists "public"."workflows_pkey";

drop index if exists "public"."profiles_pkey";

drop table "public"."action_items";

drop table "public"."approval_queue";

drop table "public"."campaign_enrollments";

drop table "public"."campaign_sequences";

drop table "public"."email_templates";

drop table "public"."system_config";

drop table "public"."workflow_executions";

drop table "public"."workflows";

alter table "public"."mailboxes" enable row level security;

alter table "public"."profiles" drop column "id";

alter table "public"."profiles" add column "profile_id" uuid not null default gen_random_uuid();

alter table "public"."profiles" alter column "auth_user_id" set not null;

alter table "public"."profiles" alter column "full_name" set not null;

alter table "public"."role_permissions" add column "view_emails" boolean not null default true;

alter table "public"."role_permissions" add column "view_workflows" boolean not null default true;

CREATE UNIQUE INDEX idx_contacts_name_org_unique ON public.contacts USING btree (lower(TRIM(BOTH FROM first_name)), lower(TRIM(BOTH FROM last_name)), organization_id) WHERE ((first_name IS NOT NULL) AND (last_name IS NOT NULL) AND (organization_id IS NOT NULL));

CREATE INDEX idx_contacts_placeholder_email ON public.contacts USING btree (((custom_fields ->> 'placeholder_email'::text))) WHERE ((custom_fields ->> 'placeholder_email'::text) = 'true'::text);

CREATE INDEX idx_organizations_city_not_null ON public.organizations USING btree (city) WHERE (city IS NOT NULL);

CREATE INDEX idx_organizations_region_not_null ON public.organizations USING btree (region) WHERE (region IS NOT NULL);

CREATE INDEX idx_organizations_state_not_null ON public.organizations USING btree (state) WHERE (state IS NOT NULL);

CREATE INDEX idx_profiles_role ON public.profiles USING btree (role);

CREATE INDEX idx_role_permissions_role ON public.role_permissions USING btree (role);

CREATE UNIQUE INDEX profiles_pkey ON public.profiles USING btree (profile_id);

alter table "public"."profiles" add constraint "profiles_pkey" PRIMARY KEY using index "profiles_pkey";

alter table "public"."campaigns" add constraint "campaigns_product_id_fkey" FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL not valid;

alter table "public"."campaigns" validate constraint "campaigns_product_id_fkey";

alter table "public"."profiles" add constraint "profiles_auth_user_id_fkey" FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."profiles" validate constraint "profiles_auth_user_id_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.admin_update_user_role(profile_id uuid, new_role public.role_type)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- Check if admin
  IF NOT has_permission('manage_users') THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  -- Update role
  UPDATE profiles
  SET role = new_role, updated_at = NOW()
  WHERE id = profile_id;

  RETURN json_build_object('success', true);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_profile_by_auth_user_id(user_id uuid)
 RETURNS TABLE(id uuid, auth_user_id uuid, full_name text, role public.role_type, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
BEGIN
  -- Try auth_user_id first, fallback to id
  BEGIN
    RETURN QUERY
    SELECT 
      p.id,
      p.auth_user_id,
      p.full_name,
      p.role,
      p.created_at,
      p.updated_at
    FROM profiles p
    WHERE p.auth_user_id = user_id;
  EXCEPTION
    WHEN undefined_column THEN
      -- Fallback: use id if auth_user_id doesn't exist
      RETURN QUERY
      SELECT 
        p.id,
        p.id as auth_user_id, -- Use id as auth_user_id
        p.full_name,
        p.role,
        p.created_at,
        p.updated_at
      FROM profiles p
      WHERE p.id = user_id;
  END;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_user_permissions_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  PERFORM set_config('search_path','public,pg_temp',true);
  NEW.updated_at = TIMEZONE('utc'::text, NOW());
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.log_user_activity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  org_id UUID;
BEGIN
  -- Get organization_id from the record (if available)
  -- This will work for tables that have organization_id column
  BEGIN
    IF TG_TABLE_NAME = 'campaigns' THEN
      org_id := NEW.organization_id;
    ELSIF TG_TABLE_NAME = 'emails' THEN
      org_id := NEW.organization_id;
    ELSIF TG_TABLE_NAME = 'workflows' THEN
      org_id := NEW.organization_id;
    ELSIF TG_TABLE_NAME = 'contacts' THEN
      org_id := NEW.organization_id;
    ELSE
      org_id := NULL;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      org_id := NULL;
  END;
  
  -- Log the action to activities table (if it exists)
  -- Note: This will only work if activities table exists
  BEGIN
    INSERT INTO activities (
      user_id,           -- auth.uid() - actual user
      organization_id,
      action_type,
      entity_type,
      entity_id,
      metadata,
      timestamp
    ) VALUES (
      auth.uid(),        -- Always the actual user
      org_id,
      CASE
        WHEN TG_OP = 'INSERT' THEN 'created'
        WHEN TG_OP = 'UPDATE' THEN 'updated'
        WHEN TG_OP = 'DELETE' THEN 'deleted'
      END,
      TG_TABLE_NAME,     -- 'campaigns', 'emails', etc.
      COALESCE(NEW.id, OLD.id),
      jsonb_build_object(
        'old_status', OLD.status,
        'new_status', NEW.status,
        'approved_by', NEW.approved_by,
        'created_by', NEW.created_by
      ),
      NOW()
    );
  EXCEPTION
    WHEN undefined_table THEN
      -- activities table doesn't exist yet, skip logging
      NULL;
    WHEN OTHERS THEN
      -- Log error but don't fail the transaction
      RAISE WARNING 'Failed to log activity: %', SQLERRM;
  END;
  
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.prevent_manual_user_override()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- For INSERT: Force created_by to current user
  IF TG_OP = 'INSERT' THEN
    NEW.created_by = auth.uid();
  END IF;
  
  -- For UPDATE: Only allow approved_by to be set by the trigger
  IF TG_OP = 'UPDATE' AND NEW.status = 'approved' AND (OLD.status IS NULL OR OLD.status != 'approved') THEN
    NEW.approved_by = auth.uid();
  END IF;
  
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.set_created_by()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- auth.uid() gets the actual logged-in user from JWT token
  -- No way to fake this!
  NEW.created_by = auth.uid();
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_cron_job_exists(job_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  job_exists boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = job_name
  ) INTO job_exists;
  
  RETURN job_exists;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.clear_user_permission_override(target_user_id uuid, permission_key text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    PERFORM set_config('search_path', 'public,pg_temp', true);
    
    IF NOT public.has_permission('manage_users') THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;
    
    IF NOT public.is_valid_permission(permission_key) THEN
        RAISE EXCEPTION 'Invalid permission key: %', permission_key;
    END IF;
    
    EXECUTE format(
        'UPDATE public.user_permissions 
         SET %I = NULL, updated_at = NOW() 
         WHERE auth_user_id = $1',
        permission_key
    ) USING target_user_id;
    
    -- If no overrides remain, delete the row
    DELETE FROM public.user_permissions
    WHERE auth_user_id = target_user_id
    AND view_users IS NULL
    AND manage_users IS NULL
    AND view_contacts IS NULL
    AND manage_contacts IS NULL
    AND view_campaigns IS NULL
    AND manage_campaigns IS NULL
    AND approve_campaigns IS NULL
    AND view_analytics IS NULL
    AND manage_approvals IS NULL
    AND view_workflows IS NULL
    AND view_emails IS NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.current_jwt_role()
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  claims jsonb;
begin
  claims := current_setting('request.jwt.claims', true)::jsonb;
  if claims ? 'role' then
    return claims->>'role';
  end if;
  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.exec_sql(sql text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  EXECUTE sql;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_cron_job_runs(job_name text, limit_count integer DEFAULT 10)
 RETURNS TABLE(runid bigint, job_pid integer, status text, return_message text, start_time timestamp with time zone, end_time timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    r.runid,
    r.job_pid,
    r.status,
    r.return_message,
    r.start_time,
    r.end_time
  FROM cron.job_run_details r
  WHERE r.jobname = get_cron_job_runs.job_name
  ORDER BY r.start_time DESC
  LIMIT limit_count;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_cron_job_status(job_name text)
 RETURNS TABLE(jobid bigint, schedule text, command text, nodename text, nodeport integer, database text, username text, active boolean, jobname text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    j.jobid,
    j.schedule,
    j.command,
    j.nodename,
    j.nodeport,
    j.database,
    j.username,
    j.active,
    j.jobname
  FROM cron.job j
  WHERE j.jobname = get_cron_job_status.job_name;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_db_settings()
 RETURNS TABLE(supabase_url text, service_role_key text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    current_setting('app.settings.supabase_url', true),
    current_setting('app.settings.service_role_key', true);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_user_effective_permissions(target_user_id uuid)
 RETURNS TABLE(view_users boolean, manage_users boolean, view_contacts boolean, manage_contacts boolean, view_campaigns boolean, manage_campaigns boolean, approve_campaigns boolean, view_analytics boolean, manage_approvals boolean, view_workflows boolean, view_emails boolean, has_overrides boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
    user_role public.role_type;
    role_perms RECORD;
    user_overrides RECORD;
BEGIN
    PERFORM set_config('search_path', 'public,pg_temp', true);
    
    -- Check caller has permission or is viewing their own
    IF NOT (
        public.has_permission('manage_users') 
        OR auth.uid() = target_user_id
    ) THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;
    
    -- Get user's role
    SELECT p.role INTO user_role
    FROM public.profiles p
    WHERE p.auth_user_id = target_user_id
    LIMIT 1;
    
    -- If user doesn't exist, return all false
    IF user_role IS NULL THEN
        RETURN QUERY SELECT 
            false, false, false, false, false, 
            false, false, false, false, false, 
            false, false;
        RETURN;
    END IF;
    
    -- Get role permissions
    SELECT * INTO role_perms
    FROM public.role_permissions rp
    WHERE rp.role = user_role
    LIMIT 1;
    
    -- Get user overrides (if any)
    SELECT * INTO user_overrides
    FROM public.user_permissions up
    WHERE up.auth_user_id = target_user_id
    LIMIT 1;
    
    -- Return merged permissions
    RETURN QUERY SELECT
        COALESCE(user_overrides.view_users, role_perms.view_users),
        COALESCE(user_overrides.manage_users, role_perms.manage_users),
        COALESCE(user_overrides.view_contacts, role_perms.view_contacts),
        COALESCE(user_overrides.manage_contacts, role_perms.manage_contacts),
        COALESCE(user_overrides.view_campaigns, role_perms.view_campaigns),
        COALESCE(user_overrides.manage_campaigns, role_perms.manage_campaigns),
        COALESCE(user_overrides.approve_campaigns, role_perms.approve_campaigns),
        COALESCE(user_overrides.view_analytics, role_perms.view_analytics),
        COALESCE(user_overrides.manage_approvals, role_perms.manage_approvals),
        COALESCE(user_overrides.view_workflows, role_perms.view_workflows),
        COALESCE(user_overrides.view_emails, role_perms.view_emails),
        (user_overrides.id IS NOT NULL);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.has_permission(permission_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
    user_role public.role_type;
    role_perm BOOLEAN;
    user_override BOOLEAN;
BEGIN
    -- Set search_path for security
    PERFORM set_config('search_path', 'public,pg_temp', true);
    
    -- Validate permission name
    IF NOT public.is_valid_permission(permission_name) THEN
        RAISE WARNING 'Invalid permission name: %', permission_name;
        RETURN FALSE;
    END IF;
    
    -- Get user's role
    SELECT p.role INTO user_role
    FROM public.profiles p
    WHERE p.auth_user_id = auth.uid()
    LIMIT 1;
    
    IF user_role IS NULL THEN
        RETURN FALSE;
    END IF;
    
    -- LAYER 1: Check for user-specific override first
    EXECUTE format(
        'SELECT %I FROM public.user_permissions WHERE auth_user_id = $1',
        permission_name
    ) INTO user_override USING auth.uid();
    
    -- If override exists (even if false), return it immediately
    IF user_override IS NOT NULL THEN
        RETURN user_override;
    END IF;
    
    -- LAYER 2: Fall back to role permission
    EXECUTE format(
        'SELECT %I FROM public.role_permissions WHERE role = $1',
        permission_name
    ) INTO role_perm USING user_role;
    
    RETURN COALESCE(role_perm, FALSE);
END;
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


CREATE OR REPLACE FUNCTION public.set_approved_by()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  PERFORM set_config('search_path', 'public,pg_temp', true);
  
  -- Only run if the table has status and approved_by columns
  BEGIN
    IF TG_OP = 'UPDATE' THEN
      -- Try to access the columns - if they don't exist, skip
      IF NEW.status = 'approved' 
         AND (OLD.status IS NULL OR OLD.status != 'approved') 
         AND NEW.approved_by IS NULL THEN
        NEW.approved_by = auth.uid();
        NEW.approved_at = NOW();
      END IF;
    END IF;
  EXCEPTION
    WHEN undefined_column THEN
      -- Silently skip if columns don't exist
      NULL;
  END;
  
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.set_auth_user_tracking()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- ensure stable search path for SECURITY DEFINER
  PERFORM set_config('search_path','public,pg_temp',true);

  -- On insert: set owner and created_at if present
  IF TG_OP = 'INSERT' THEN
    IF NEW.auth_user_id IS NULL THEN
      NEW.auth_user_id = auth.uid();
    END IF;

    BEGIN
      IF NEW.created_at IS NULL THEN
        NEW.created_at = NOW();
      END IF;
    EXCEPTION WHEN undefined_column THEN
      -- table doesn't have created_at; ignore
      NULL;
    END;
  END IF;

  -- On update: set updated_at if present
  IF TG_OP = 'UPDATE' THEN
    BEGIN
      NEW.updated_at = NOW();
    EXCEPTION WHEN undefined_column THEN
      -- table doesn't have updated_at; ignore
      NULL;
    END;
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.set_user_permission_override(target_user_id uuid, permission_updates jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    k TEXT;
    v TEXT;
BEGIN
    PERFORM set_config('search_path', 'public,pg_temp', true);
    
    IF NOT public.has_permission('manage_users') THEN
        RAISE EXCEPTION 'Unauthorized: manage_users permission required';
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE auth_user_id = target_user_id
    ) THEN
        RAISE EXCEPTION 'User not found: %', target_user_id;
    END IF;
    
    -- Create user_permissions row if doesn't exist
    INSERT INTO public.user_permissions (auth_user_id, created_by)
    VALUES (target_user_id, auth.uid())
    ON CONFLICT (auth_user_id) DO NOTHING;
    
    -- Update each permission from JSONB
    FOR k, v IN SELECT key, value FROM jsonb_each_text(permission_updates)
    LOOP
        IF NOT public.is_valid_permission(k) THEN
            RAISE WARNING 'Skipping invalid permission key: %', k;
            CONTINUE;
        END IF;
        
        EXECUTE format(
            'UPDATE public.user_permissions 
             SET %I = $1::boolean, updated_at = NOW() 
             WHERE auth_user_id = $2',
            k
        ) USING v, target_user_id;
    END LOOP;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$function$
;


  create policy "public_read_contacts"
  on "public"."contacts"
  as permissive
  for select
  to public
using (true);



  create policy "public_read_conversations"
  on "public"."conversations"
  as permissive
  for select
  to public
using (true);



  create policy "public_read_emails"
  on "public"."emails"
  as permissive
  for select
  to public
using (true);



  create policy "public_read_mailboxes"
  on "public"."mailboxes"
  as permissive
  for select
  to public
using (true);



  create policy "Profiles: admin read"
  on "public"."profiles"
  as permissive
  for select
  to public
using ((public.current_jwt_role() = 'admin'::text));



  create policy "Profiles: admin update"
  on "public"."profiles"
  as permissive
  for update
  to public
using ((public.current_jwt_role() = 'admin'::text))
with check ((public.current_jwt_role() = 'admin'::text));



  create policy "Profiles: self insert"
  on "public"."profiles"
  as permissive
  for insert
  to public
with check ((auth.uid() = auth_user_id));



  create policy "Profiles: self read"
  on "public"."profiles"
  as permissive
  for select
  to public
using ((auth.uid() = auth_user_id));



  create policy "Profiles: self update"
  on "public"."profiles"
  as permissive
  for update
  to public
using ((auth.uid() = auth_user_id))
with check ((auth.uid() = auth_user_id));



  create policy "Profiles: service insert"
  on "public"."profiles"
  as permissive
  for insert
  to public
with check ((auth.role() = 'service_role'::text));



  create policy "Users can update own profile"
  on "public"."profiles"
  as permissive
  for update
  to authenticated
using ((auth_user_id = auth.uid()))
with check ((auth_user_id = auth.uid()));



  create policy "Users can view own profile"
  on "public"."profiles"
  as permissive
  for select
  to authenticated
using ((auth_user_id = auth.uid()));



  create policy "Admins can manage profiles"
  on "public"."profiles"
  as permissive
  for update
  to public
using ((EXISTS ( SELECT 1
   FROM public.profiles me
  WHERE ((me.auth_user_id = auth.uid()) AND (me.role = 'admin'::public.role_type)))))
with check (true);



  create policy "Admins can read all profiles"
  on "public"."profiles"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.profiles me
  WHERE ((me.auth_user_id = auth.uid()) AND (me.role = 'admin'::public.role_type)))));



  create policy "Users can read their own profile"
  on "public"."profiles"
  as permissive
  for select
  to public
using ((auth.uid() = auth_user_id));


CREATE TRIGGER campaigns_log_activity AFTER INSERT OR UPDATE ON public.campaigns FOR EACH ROW EXECUTE FUNCTION public.log_user_activity();

CREATE TRIGGER campaigns_set_approved_by BEFORE UPDATE ON public.campaigns FOR EACH ROW EXECUTE FUNCTION public.set_approved_by();

CREATE TRIGGER campaigns_set_created_by BEFORE INSERT ON public.campaigns FOR EACH ROW EXECUTE FUNCTION public.set_created_by();

CREATE TRIGGER emails_log_activity AFTER INSERT OR UPDATE ON public.emails FOR EACH ROW EXECUTE FUNCTION public.log_user_activity();

CREATE TRIGGER emails_set_approved_by BEFORE UPDATE ON public.emails FOR EACH ROW EXECUTE FUNCTION public.set_approved_by();

CREATE TRIGGER emails_set_created_by BEFORE INSERT ON public.emails FOR EACH ROW EXECUTE FUNCTION public.set_created_by();

CREATE TRIGGER user_permissions_set_timestamp BEFORE UPDATE ON public.user_permissions FOR EACH ROW EXECUTE FUNCTION public.handle_user_permissions_updated_at();


