


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."event_type" AS ENUM (
    'sent',
    'delivered',
    'opened',
    'clicked',
    'bounced',
    'complained',
    'website_visit',
    'form_submit',
    'demo_request',
    'purchase'
);


ALTER TYPE "public"."event_type" OWNER TO "postgres";


CREATE TYPE "public"."role_type" AS ENUM (
    'admin',
    'sales',
    'accounts',
    'management'
);


ALTER TYPE "public"."role_type" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_update_user_role"("profile_id" "uuid", "new_role" "public"."role_type") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
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
$$;


ALTER FUNCTION "public"."admin_update_user_role"("profile_id" "uuid", "new_role" "public"."role_type") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."category_matches_workflow_rules"("p_category" character varying, "p_rules" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
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
$$;


ALTER FUNCTION "public"."category_matches_workflow_rules"("p_category" character varying, "p_rules" "jsonb") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."category_matches_workflow_rules"("p_category" character varying, "p_rules" "jsonb") IS 'Check if email category matches workflow category rules (with wildcard support)';



CREATE OR REPLACE FUNCTION "public"."check_cron_job_exists"("job_name" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  job_exists boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = job_name
  ) INTO job_exists;
  
  RETURN job_exists;
END;
$$;


ALTER FUNCTION "public"."check_cron_job_exists"("job_name" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."check_cron_job_exists"("job_name" "text") IS 'Check if a cron job exists by name';



CREATE OR REPLACE FUNCTION "public"."clear_user_permission_override"("target_user_id" "uuid", "permission_key" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$
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
$_$;


ALTER FUNCTION "public"."clear_user_permission_override"("target_user_id" "uuid", "permission_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_jwt_role"() RETURNS "text"
    LANGUAGE "plpgsql" STABLE
    AS $$
declare
  claims jsonb;
begin
  claims := current_setting('request.jwt.claims', true)::jsonb;
  if claims ? 'role' then
    return claims->>'role';
  end if;
  return null;
end;
$$;


ALTER FUNCTION "public"."current_jwt_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."exec_sql"("sql" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  EXECUTE sql;
END;
$$;


ALTER FUNCTION "public"."exec_sql"("sql" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."exec_sql"("sql" "text") IS 'Execute dynamic SQL (service role only) - used for scheduling/unscheduling cron jobs';



CREATE OR REPLACE FUNCTION "public"."get_campaign_enrollments_due"() RETURNS TABLE("enrollment_id" "uuid", "campaign_sequence_id" "uuid", "campaign_name" character varying, "contact_id" "uuid", "contact_email" character varying, "current_step" integer, "next_send_date" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE
    AS $$
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
$$;


ALTER FUNCTION "public"."get_campaign_enrollments_due"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_campaign_enrollments_due"() IS 'Get all active campaign enrollments ready to send';



CREATE OR REPLACE FUNCTION "public"."get_category_group"("p_category" character varying) RETURNS character varying
    LANGUAGE "plpgsql" STABLE
    AS $$
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
$$;


ALTER FUNCTION "public"."get_category_group"("p_category" character varying) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_category_group"("p_category" character varying) IS 'Get category group (business/spam/personal/other) for a given category';



CREATE OR REPLACE FUNCTION "public"."get_cron_job_runs"("job_name" "text", "limit_count" integer DEFAULT 10) RETURNS TABLE("runid" bigint, "job_pid" integer, "status" "text", "return_message" "text", "start_time" timestamp with time zone, "end_time" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
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
$$;


ALTER FUNCTION "public"."get_cron_job_runs"("job_name" "text", "limit_count" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_cron_job_runs"("job_name" "text", "limit_count" integer) IS 'Get recent execution history for a cron job';



CREATE OR REPLACE FUNCTION "public"."get_cron_job_status"("job_name" "text") RETURNS TABLE("jobid" bigint, "schedule" "text", "command" "text", "nodename" "text", "nodeport" integer, "database" "text", "username" "text", "active" boolean, "jobname" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
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
$$;


ALTER FUNCTION "public"."get_cron_job_status"("job_name" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_cron_job_status"("job_name" "text") IS 'Get details about a specific cron job';



CREATE OR REPLACE FUNCTION "public"."get_current_user_role"() RETURNS "text"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
BEGIN
  PERFORM set_config('search_path', 'public,pg_temp', true);
  
  RETURN (
    SELECT role::text
    FROM profiles 
    WHERE auth_user_id = auth.uid()
    LIMIT 1
  );
END;
$$;


ALTER FUNCTION "public"."get_current_user_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_db_settings"() RETURNS TABLE("supabase_url" "text", "service_role_key" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    current_setting('app.settings.supabase_url', true),
    current_setting('app.settings.service_role_key', true);
END;
$$;


ALTER FUNCTION "public"."get_db_settings"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_db_settings"() IS 'Get database configuration settings for cron job';



CREATE OR REPLACE FUNCTION "public"."get_profile_by_auth_user_id"("user_id" "uuid") RETURNS TABLE("id" "uuid", "auth_user_id" "uuid", "full_name" "text", "role" "public"."role_type", "created_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
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
$$;


ALTER FUNCTION "public"."get_profile_by_auth_user_id"("user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_effective_permissions"("target_user_id" "uuid") RETURNS TABLE("view_users" boolean, "manage_users" boolean, "view_contacts" boolean, "manage_contacts" boolean, "view_campaigns" boolean, "manage_campaigns" boolean, "approve_campaigns" boolean, "view_analytics" boolean, "manage_approvals" boolean, "view_workflows" boolean, "view_emails" boolean, "has_overrides" boolean)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
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
$$;


ALTER FUNCTION "public"."get_user_effective_permissions"("target_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_workflows_for_category"("p_category" character varying) RETURNS TABLE("workflow_id" "uuid", "workflow_name" character varying, "priority" integer)
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT w.id, w.name, w.priority
    FROM public.workflows w
    WHERE w.is_active = true
      AND public.category_matches_workflow_rules(p_category, w.category_rules)
    ORDER BY w.priority DESC;
END;
$$;


ALTER FUNCTION "public"."get_workflows_for_category"("p_category" character varying) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_workflows_for_category"("p_category" character varying) IS 'Get all active workflows that should trigger for given email category';



CREATE OR REPLACE FUNCTION "public"."handle_profiles_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_profiles_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_user_permissions_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  PERFORM set_config('search_path','public,pg_temp',true);
  NEW.updated_at = TIMEZONE('utc'::text, NOW());
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_user_permissions_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."has_permission"("permission_name" "text") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $_$
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
$_$;


ALTER FUNCTION "public"."has_permission"("permission_name" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."has_permission"("permission_name" "text") IS 'Check if current user has a specific permission. Checks user overrides first, then falls back to role permissions.';



CREATE OR REPLACE FUNCTION "public"."is_admin"() RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
BEGIN
  PERFORM set_config('search_path', 'public,pg_temp', true);
  
  RETURN COALESCE(
    (SELECT role = 'admin' FROM profiles WHERE auth_user_id = auth.uid() LIMIT 1),
    FALSE
  );
END;
$$;


ALTER FUNCTION "public"."is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_valid_email_category"("p_category" character varying) RETURNS boolean
    LANGUAGE "plpgsql" STABLE
    AS $$
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
$$;


ALTER FUNCTION "public"."is_valid_email_category"("p_category" character varying) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."is_valid_email_category"("p_category" character varying) IS 'Validate email category against system_config list';



CREATE OR REPLACE FUNCTION "public"."is_valid_email_intent"("p_intent" character varying) RETURNS boolean
    LANGUAGE "plpgsql" STABLE
    AS $$
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
$$;


ALTER FUNCTION "public"."is_valid_email_intent"("p_intent" character varying) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."is_valid_email_intent"("p_intent" character varying) IS 'Validate email intent against system_config list';



CREATE OR REPLACE FUNCTION "public"."is_valid_email_sentiment"("p_sentiment" character varying) RETURNS boolean
    LANGUAGE "plpgsql" STABLE
    AS $$
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
$$;


ALTER FUNCTION "public"."is_valid_email_sentiment"("p_sentiment" character varying) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."is_valid_email_sentiment"("p_sentiment" character varying) IS 'Validate email sentiment against system_config list';



CREATE OR REPLACE FUNCTION "public"."is_valid_permission"("p" "text") RETURNS boolean
    LANGUAGE "sql" IMMUTABLE
    AS $$
  SELECT p IN (
    'view_users', 'manage_users', 'view_contacts', 'manage_contacts',
    'view_campaigns', 'manage_campaigns', 'approve_campaigns',
    'view_analytics', 'manage_approvals', 'view_workflows', 'view_emails'
  )
$$;


ALTER FUNCTION "public"."is_valid_permission"("p" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_user_activity"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
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
$$;


ALTER FUNCTION "public"."log_user_activity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_manual_user_override"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
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
$$;


ALTER FUNCTION "public"."prevent_manual_user_override"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_role_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  if current_user <> 'service_role' and new.role <> old.role then
    raise exception 'Role changes require service role privileges';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."prevent_role_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."remove_user_permission_overrides"("target_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    PERFORM set_config('search_path', 'public,pg_temp', true);
    
    IF NOT public.has_permission('manage_users') THEN
        RAISE EXCEPTION 'Unauthorized: manage_users permission required';
    END IF;
    
    DELETE FROM public.user_permissions
    WHERE auth_user_id = target_user_id;
    
    RAISE NOTICE 'Removed all permission overrides for user %', target_user_id;
END;
$$;


ALTER FUNCTION "public"."remove_user_permission_overrides"("target_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_approved_by"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
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
$$;


ALTER FUNCTION "public"."set_approved_by"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_auth_user_tracking"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
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
$$;


ALTER FUNCTION "public"."set_auth_user_tracking"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_created_by"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- auth.uid() gets the actual logged-in user from JWT token
  -- No way to fake this!
  NEW.created_by = auth.uid();
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_created_by"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_user_permission_override"("target_user_id" "uuid", "permission_updates" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$
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
$_$;


ALTER FUNCTION "public"."set_user_permission_override"("target_user_id" "uuid", "permission_updates" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_role_permissions_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;


ALTER FUNCTION "public"."touch_role_permissions_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_contact_lead_score_from_interest"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    UPDATE public.contacts
    SET lead_score = LEAST(100, GREATEST(0, lead_score + COALESCE(NEW.lead_score_contribution, 0)))
    WHERE id = NEW.contact_id;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_contact_lead_score_from_interest"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_conversation_stats"("p_conversation_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_email_count INTEGER;
  v_first_email_at TIMESTAMPTZ;
  v_last_email_at TIMESTAMPTZ;
  v_last_direction TEXT;
BEGIN
  -- Get conversation statistics from emails
  SELECT 
    COUNT(*),
    MIN(received_at),
    MAX(received_at),
    (ARRAY_AGG(direction ORDER BY received_at DESC))[1]
  INTO 
    v_email_count,
    v_first_email_at,
    v_last_email_at,
    v_last_direction
  FROM public.emails
  WHERE conversation_id = p_conversation_id
    AND is_deleted = FALSE;

  -- Update conversation with calculated stats
  UPDATE public.conversations
  SET 
    email_count = COALESCE(v_email_count, 0),
    first_email_at = v_first_email_at,
    last_email_at = v_last_email_at,
    last_email_direction = v_last_direction,
    requires_response = (v_last_direction = 'incoming'),
    updated_at = NOW()
  WHERE id = p_conversation_id;
END;
$$;


ALTER FUNCTION "public"."update_conversation_stats"("p_conversation_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."update_conversation_stats"("p_conversation_id" "uuid") IS 'Updates conversation statistics (email_count, first/last email times, etc.) based on associated emails. Called after email insert/update/delete.';



CREATE OR REPLACE FUNCTION "public"."update_email_drafts_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_email_drafts_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_lead_classification"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
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
$$;


ALTER FUNCTION "public"."update_lead_classification"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."action_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" character varying(500) NOT NULL,
    "description" "text",
    "contact_id" "uuid" NOT NULL,
    "email_id" "uuid",
    "workflow_execution_id" "uuid",
    "action_type" character varying(50),
    "priority" character varying(20) DEFAULT 'medium'::character varying,
    "status" character varying(20) DEFAULT 'open'::character varying,
    "due_date" timestamp with time zone,
    "assigned_to" "uuid",
    "completed_at" timestamp with time zone,
    "completed_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "action_items_action_type_check" CHECK ((("action_type")::"text" = ANY ((ARRAY['follow_up'::character varying, 'call'::character varying, 'meeting'::character varying, 'review'::character varying, 'other'::character varying])::"text"[]))),
    CONSTRAINT "action_items_priority_check" CHECK ((("priority")::"text" = ANY ((ARRAY['low'::character varying, 'medium'::character varying, 'high'::character varying, 'urgent'::character varying])::"text"[]))),
    CONSTRAINT "action_items_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['open'::character varying, 'in_progress'::character varying, 'completed'::character varying, 'cancelled'::character varying])::"text"[])))
);


ALTER TABLE "public"."action_items" OWNER TO "postgres";


COMMENT ON TABLE "public"."action_items" IS 'Follow-up actions generated by workflows';



CREATE TABLE IF NOT EXISTS "public"."ai_enrichment_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "operation_type" character varying NOT NULL,
    "model_used" character varying NOT NULL,
    "items_processed" integer NOT NULL,
    "tokens_input" integer,
    "tokens_output" integer,
    "estimated_cost_usd" numeric(10,6),
    "processing_time_ms" integer,
    "success_count" integer,
    "error_count" integer,
    "average_confidence" numeric(3,2),
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."ai_enrichment_logs" OWNER TO "postgres";


COMMENT ON TABLE "public"."ai_enrichment_logs" IS 'Tracks AI enrichment operations for cost and performance monitoring';



CREATE TABLE IF NOT EXISTS "public"."approval_queue" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "workflow_execution_id" "uuid" NOT NULL,
    "action_index" integer NOT NULL,
    "action_tool" character varying(100) NOT NULL,
    "action_params_resolved" "jsonb" NOT NULL,
    "workflow_name" character varying(255) NOT NULL,
    "email_subject" character varying(500),
    "contact_email" character varying(255),
    "extraction_confidence" double precision,
    "reason" "text",
    "status" character varying(50) DEFAULT 'pending'::character varying,
    "decided_by" "uuid",
    "decided_at" timestamp with time zone,
    "modified_params" "jsonb",
    "rejection_reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "draft_id" "uuid",
    "langgraph_thread_id" character varying,
    CONSTRAINT "approval_queue_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['pending'::character varying, 'approved'::character varying, 'rejected'::character varying, 'modified'::character varying])::"text"[])))
);


ALTER TABLE "public"."approval_queue" OWNER TO "postgres";


COMMENT ON TABLE "public"."approval_queue" IS 'Human-in-the-loop approval queue for workflow actions';



CREATE TABLE IF NOT EXISTS "public"."campaign_contact_summary" (
    "campaign_id" "uuid" NOT NULL,
    "contact_id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "total_score" integer DEFAULT 0 NOT NULL,
    "opened" boolean DEFAULT false NOT NULL,
    "clicked" boolean DEFAULT false NOT NULL,
    "converted" boolean DEFAULT false NOT NULL,
    "first_event_at" timestamp with time zone,
    "last_event_at" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."campaign_contact_summary" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."campaign_enrollments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_sequence_id" "uuid" NOT NULL,
    "contact_id" "uuid" NOT NULL,
    "current_step" integer DEFAULT 1,
    "next_send_date" timestamp with time zone,
    "status" character varying(50) DEFAULT 'enrolled'::character varying,
    "steps_completed" "jsonb" DEFAULT '[]'::"jsonb",
    "total_opens" integer DEFAULT 0,
    "total_clicks" integer DEFAULT 0,
    "replied" boolean DEFAULT false,
    "enrolled_at" timestamp with time zone DEFAULT "now"(),
    "completed_at" timestamp with time zone,
    CONSTRAINT "campaign_enrollments_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['enrolled'::character varying, 'active'::character varying, 'completed'::character varying, 'unsubscribed'::character varying, 'bounced'::character varying, 'paused'::character varying])::"text"[])))
);


ALTER TABLE "public"."campaign_enrollments" OWNER TO "postgres";


COMMENT ON TABLE "public"."campaign_enrollments" IS 'Track contacts enrolled in campaign sequences';



COMMENT ON COLUMN "public"."campaign_enrollments"."next_send_date" IS 'When next email should be sent to this contact';



COMMENT ON COLUMN "public"."campaign_enrollments"."steps_completed" IS 'History of completed steps with engagement data';



CREATE TABLE IF NOT EXISTS "public"."campaign_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid",
    "contact_id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "event_type" "public"."event_type" NOT NULL,
    "event_timestamp" timestamp with time zone DEFAULT "now"() NOT NULL,
    "score" integer DEFAULT 0 NOT NULL,
    "source" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "external_id" "text",
    "inserted_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."campaign_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."campaign_sequences" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" character varying(255) NOT NULL,
    "description" "text",
    "target_sql" "text" NOT NULL,
    "target_count" integer,
    "target_preview" "jsonb",
    "steps" "jsonb" NOT NULL,
    "from_mailbox_id" "uuid",
    "send_time_preference" character varying(50),
    "product_id" "uuid",
    "scheduled_at" timestamp with time zone,
    "started_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "status" character varying(50) DEFAULT 'draft'::character varying,
    "stats" "jsonb" DEFAULT '{}'::"jsonb",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "campaign_sequences_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['draft'::character varying, 'scheduled'::character varying, 'running'::character varying, 'completed'::character varying, 'paused'::character varying, 'cancelled'::character varying])::"text"[])))
);


ALTER TABLE "public"."campaign_sequences" OWNER TO "postgres";


COMMENT ON TABLE "public"."campaign_sequences" IS 'Multi-step email campaign sequences (automation blueprint)';



COMMENT ON COLUMN "public"."campaign_sequences"."target_sql" IS 'AI-generated SQL query for selecting target contacts';



COMMENT ON COLUMN "public"."campaign_sequences"."steps" IS 'Array of campaign steps with templates, delays, and conditions';



COMMENT ON COLUMN "public"."campaign_sequences"."stats" IS 'Aggregated campaign statistics (sent, opened, clicked, replied)';



CREATE TABLE IF NOT EXISTS "public"."campaigns" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "subject" "text",
    "provider" "text",
    "external_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "scheduled_at" timestamp with time zone,
    "sent_at" timestamp with time zone,
    "product_id" "uuid",
    "auth_user_id" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."campaigns" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."contact_product_interests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contact_id" "uuid" NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "interest_level" character varying(50) DEFAULT 'medium'::character varying,
    "status" character varying(50) DEFAULT 'prospecting'::character varying,
    "source" character varying(50) DEFAULT 'excel_import'::character varying,
    "campaign_id" "uuid",
    "first_interaction_date" "date" DEFAULT CURRENT_DATE,
    "last_interaction_date" "date" DEFAULT CURRENT_DATE,
    "quoted_price" numeric(12,2),
    "quoted_quantity" integer,
    "quote_date" "date",
    "next_followup_date" "date",
    "expected_close_date" "date",
    "probability_percentage" numeric(5,2),
    "lead_score_contribution" integer DEFAULT 0,
    "notes" "text",
    "lost_reason" "text",
    "competitor_chosen" character varying(255),
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "auth_user_id" "uuid",
    CONSTRAINT "contact_product_interests_interest_level_check" CHECK ((("interest_level")::"text" = ANY ((ARRAY['low'::character varying, 'medium'::character varying, 'high'::character varying])::"text"[]))),
    CONSTRAINT "contact_product_interests_lead_score_contribution_check" CHECK ((("lead_score_contribution" >= 0) AND ("lead_score_contribution" <= 50))),
    CONSTRAINT "contact_product_interests_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['prospecting'::character varying, 'quoted'::character varying, 'negotiating'::character varying, 'won'::character varying, 'lost'::character varying])::"text"[])))
);


ALTER TABLE "public"."contact_product_interests" OWNER TO "postgres";


COMMENT ON TABLE "public"."contact_product_interests" IS 'Links existing contacts to products';



CREATE TABLE IF NOT EXISTS "public"."contacts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "email" character varying NOT NULL,
    "first_name" character varying,
    "last_name" character varying,
    "job_title" character varying,
    "phone" character varying,
    "organization_id" "uuid" NOT NULL,
    "status" character varying DEFAULT 'active'::character varying,
    "tags" "jsonb" DEFAULT '[]'::"jsonb",
    "custom_fields" "jsonb" DEFAULT '{}'::"jsonb",
    "last_contact_date" timestamp with time zone,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "enrichment_status" character varying DEFAULT 'pending'::character varying,
    "enrichment_last_attempted_at" timestamp with time zone,
    "role" character varying,
    "department" character varying,
    "lead_score" integer DEFAULT 0,
    "lead_classification" character varying DEFAULT 'cold'::character varying,
    "engagement_level" character varying DEFAULT 'new'::character varying,
    "auth_user_id" "uuid",
    CONSTRAINT "contacts_lead_score_check" CHECK ((("lead_score" >= 0) AND ("lead_score" <= 100))),
    CONSTRAINT "contacts_status_check" CHECK ((("status")::"text" = ANY (ARRAY[('active'::character varying)::"text", ('inactive'::character varying)::"text", ('unsubscribed'::character varying)::"text", ('bounced'::character varying)::"text"])))
);


ALTER TABLE "public"."contacts" OWNER TO "postgres";


COMMENT ON TABLE "public"."contacts" IS 'Individual customer contacts';



COMMENT ON COLUMN "public"."contacts"."enrichment_status" IS 'Status: pending, enriched, failed, partial';



COMMENT ON COLUMN "public"."contacts"."enrichment_last_attempted_at" IS 'Last enrichment attempt timestamp';



COMMENT ON COLUMN "public"."contacts"."role" IS 'Job title/role extracted from email signature';



COMMENT ON COLUMN "public"."contacts"."department" IS 'Department name extracted from signature';



COMMENT ON COLUMN "public"."contacts"."lead_score" IS 'Cumulative engagement score (0-100)';



COMMENT ON COLUMN "public"."contacts"."lead_classification" IS 'hot (80-100), warm (50-79), cold (0-49)';



COMMENT ON COLUMN "public"."contacts"."engagement_level" IS 'new, active, engaged, dormant, inactive';



CREATE TABLE IF NOT EXISTS "public"."conversations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "thread_id" character varying NOT NULL,
    "subject" character varying,
    "mailbox_id" "uuid" NOT NULL,
    "organization_id" "uuid",
    "primary_contact_id" "uuid",
    "email_count" integer DEFAULT 0,
    "first_email_at" timestamp with time zone,
    "last_email_at" timestamp with time zone,
    "last_email_direction" character varying,
    "status" character varying DEFAULT 'active'::character varying,
    "requires_response" boolean DEFAULT false,
    "tags" "jsonb" DEFAULT '[]'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "summary" "text",
    "action_items" "text"[],
    "last_summarized_at" timestamp with time zone,
    "email_count_at_last_summary" integer DEFAULT 0,
    "auth_user_id" "uuid",
    CONSTRAINT "conversations_last_email_direction_check" CHECK ((("last_email_direction")::"text" = ANY (ARRAY[('incoming'::character varying)::"text", ('outgoing'::character varying)::"text"]))),
    CONSTRAINT "conversations_status_check" CHECK ((("status")::"text" = ANY (ARRAY[('active'::character varying)::"text", ('closed'::character varying)::"text", ('archived'::character varying)::"text"])))
);


ALTER TABLE "public"."conversations" OWNER TO "postgres";


COMMENT ON TABLE "public"."conversations" IS 'Email threads/conversations with 1-to-1 mapping to thread_id';



COMMENT ON COLUMN "public"."conversations"."summary" IS 'AI-generated conversation summary (2-3 sentences)';



COMMENT ON COLUMN "public"."conversations"."action_items" IS 'Extracted next steps/tasks from conversation';



COMMENT ON COLUMN "public"."conversations"."last_summarized_at" IS 'When summary was last updated';



COMMENT ON COLUMN "public"."conversations"."email_count_at_last_summary" IS 'Email count when last summarized';



CREATE TABLE IF NOT EXISTS "public"."email_drafts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "source_email_id" "uuid",
    "thread_id" character varying,
    "conversation_id" "uuid",
    "contact_id" "uuid",
    "to_emails" "text"[] NOT NULL,
    "cc_emails" "text"[],
    "bcc_emails" "text"[],
    "from_mailbox_id" "uuid" NOT NULL,
    "subject" character varying NOT NULL,
    "body_html" "text",
    "body_plain" "text" NOT NULL,
    "template_id" "uuid",
    "product_ids" "uuid"[],
    "context_data" "jsonb" DEFAULT '{}'::"jsonb",
    "llm_model" character varying,
    "generation_confidence" numeric(3,2),
    "approval_status" character varying(20) DEFAULT 'pending'::character varying,
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "rejection_reason" "text",
    "langgraph_thread_id" character varying,
    "workflow_execution_id" "uuid",
    "campaign_enrollment_id" "uuid",
    "sent_email_id" "uuid",
    "sent_at" timestamp with time zone,
    "version" integer DEFAULT 1,
    "previous_draft_id" "uuid",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "email_drafts_approval_status_check" CHECK ((("approval_status")::"text" = ANY ((ARRAY['pending'::character varying, 'approved'::character varying, 'rejected'::character varying, 'auto_approved'::character varying, 'sent'::character varying])::"text"[]))),
    CONSTRAINT "email_drafts_generation_confidence_check" CHECK ((("generation_confidence" IS NULL) OR (("generation_confidence" >= (0)::numeric) AND ("generation_confidence" <= (1)::numeric))))
);


ALTER TABLE "public"."email_drafts" OWNER TO "postgres";


COMMENT ON TABLE "public"."email_drafts" IS 'Email drafts created by Email Agent for HITL approval workflow';



COMMENT ON COLUMN "public"."email_drafts"."context_data" IS 'JSON storing the context used for generation (thread summary, product info, etc)';



COMMENT ON COLUMN "public"."email_drafts"."langgraph_thread_id" IS 'LangGraph thread ID for resuming agent execution';



COMMENT ON COLUMN "public"."email_drafts"."version" IS 'Draft version number, increments when re-drafted after rejection';



COMMENT ON COLUMN "public"."email_drafts"."previous_draft_id" IS 'Link to previous version when re-drafting';



CREATE TABLE IF NOT EXISTS "public"."email_import_errors" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "mailbox_id" "uuid" NOT NULL,
    "imap_folder" character varying NOT NULL,
    "imap_uid" integer NOT NULL,
    "message_id" character varying,
    "error_message" "text" NOT NULL,
    "error_type" character varying NOT NULL,
    "retry_count" integer DEFAULT 0,
    "last_attempt_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"(),
    "resolved_at" timestamp with time zone,
    CONSTRAINT "email_import_errors_error_type_check" CHECK ((("error_type")::"text" = ANY (ARRAY[('parse_error'::character varying)::"text", ('db_constraint'::character varying)::"text", ('network_error'::character varying)::"text", ('imap_error'::character varying)::"text", ('validation_error'::character varying)::"text", ('timeout_error'::character varying)::"text", ('unknown_error'::character varying)::"text"])))
);


ALTER TABLE "public"."email_import_errors" OWNER TO "postgres";


COMMENT ON TABLE "public"."email_import_errors" IS 'Tracks failed email imports for retry logic';



COMMENT ON COLUMN "public"."email_import_errors"."mailbox_id" IS 'Reference to the mailbox where import failed';



COMMENT ON COLUMN "public"."email_import_errors"."imap_folder" IS 'IMAP folder where the email resides';



COMMENT ON COLUMN "public"."email_import_errors"."imap_uid" IS 'IMAP UID of the failed email';



COMMENT ON COLUMN "public"."email_import_errors"."message_id" IS 'Email Message-ID header (if available)';



COMMENT ON COLUMN "public"."email_import_errors"."error_message" IS 'Detailed error message from the failed import';



COMMENT ON COLUMN "public"."email_import_errors"."error_type" IS 'Categorized error type for filtering and reporting';



COMMENT ON COLUMN "public"."email_import_errors"."retry_count" IS 'Number of retry attempts made';



COMMENT ON COLUMN "public"."email_import_errors"."last_attempt_at" IS 'Timestamp of the last retry attempt';



COMMENT ON COLUMN "public"."email_import_errors"."resolved_at" IS 'Timestamp when the error was resolved (email successfully imported)';



CREATE TABLE IF NOT EXISTS "public"."email_templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" character varying(255) NOT NULL,
    "description" "text",
    "subject_template" "text" NOT NULL,
    "body_template" "text" NOT NULL,
    "llm_instructions" "text",
    "required_variables" "jsonb" DEFAULT '[]'::"jsonb",
    "category" character varying(100),
    "tags" "jsonb" DEFAULT '[]'::"jsonb",
    "is_active" boolean DEFAULT true,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."email_templates" OWNER TO "postgres";


COMMENT ON TABLE "public"."email_templates" IS 'Email templates for drafting automated responses';



CREATE TABLE IF NOT EXISTS "public"."emails" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "message_id" character varying NOT NULL,
    "thread_id" character varying NOT NULL,
    "conversation_id" "uuid",
    "in_reply_to" character varying,
    "email_references" "text",
    "subject" character varying,
    "from_email" character varying NOT NULL,
    "from_name" character varying,
    "to_emails" "text"[] NOT NULL,
    "cc_emails" "text"[],
    "bcc_emails" "text"[],
    "body_html" "text",
    "body_plain" "text",
    "mailbox_id" "uuid" NOT NULL,
    "contact_id" "uuid",
    "organization_id" "uuid",
    "direction" character varying NOT NULL,
    "is_seen" boolean DEFAULT false,
    "is_flagged" boolean DEFAULT false,
    "is_answered" boolean DEFAULT false,
    "is_draft" boolean DEFAULT false,
    "is_deleted" boolean DEFAULT false,
    "imap_folder" character varying NOT NULL,
    "imap_uid" integer,
    "headers" "jsonb" DEFAULT '{}'::"jsonb",
    "attachments" "jsonb" DEFAULT '[]'::"jsonb",
    "sent_at" timestamp with time zone,
    "received_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "needs_parsing" boolean DEFAULT false,
    "intent" character varying,
    "email_category" character varying,
    "sentiment" character varying,
    "priority_score" integer,
    "spam_score" numeric(3,2),
    "ai_processed_at" timestamp with time zone,
    "ai_model_version" character varying,
    "ai_confidence_score" numeric(3,2),
    "auth_user_id" "uuid",
    CONSTRAINT "emails_ai_confidence_check" CHECK ((("ai_confidence_score" IS NULL) OR (("ai_confidence_score" >= (0)::numeric) AND ("ai_confidence_score" <= (1)::numeric)))),
    CONSTRAINT "emails_direction_check" CHECK ((("direction")::"text" = ANY (ARRAY[('incoming'::character varying)::"text", ('outgoing'::character varying)::"text"]))),
    CONSTRAINT "emails_priority_score_check" CHECK ((("priority_score" IS NULL) OR (("priority_score" >= 0) AND ("priority_score" <= 100)))),
    CONSTRAINT "emails_spam_score_check" CHECK ((("spam_score" IS NULL) OR (("spam_score" >= (0)::numeric) AND ("spam_score" <= (1)::numeric))))
);


ALTER TABLE "public"."emails" OWNER TO "postgres";


COMMENT ON TABLE "public"."emails" IS 'Individual email messages with full IMAP metadata';



COMMENT ON COLUMN "public"."emails"."thread_id" IS 'Thread identifier created from Message-ID chain (format: thread-{md5hash})';



COMMENT ON COLUMN "public"."emails"."conversation_id" IS 'Foreign key to conversations table, nullable for import flexibility';



COMMENT ON COLUMN "public"."emails"."email_references" IS 'Full References header for threading';



COMMENT ON COLUMN "public"."emails"."needs_parsing" IS 'True if email body is stored raw and needs parsing (for large emails >100KB)';



COMMENT ON COLUMN "public"."emails"."intent" IS 'Primary email purpose: inquiry, order, quote_request, complaint, follow_up, meeting_request, feedback, other';



COMMENT ON COLUMN "public"."emails"."email_category" IS 'Business classification: critical_business, new_lead, existing_customer, spam, marketing, transactional, support';



COMMENT ON COLUMN "public"."emails"."sentiment" IS 'Emotional tone: positive, neutral, negative, urgent';



COMMENT ON COLUMN "public"."emails"."priority_score" IS 'AI-determined business importance (0-100)';



COMMENT ON COLUMN "public"."emails"."spam_score" IS 'Likelihood of spam (0.0-1.0)';



COMMENT ON COLUMN "public"."emails"."ai_processed_at" IS 'When AI enrichment completed';



COMMENT ON COLUMN "public"."emails"."ai_model_version" IS 'AI model used for enrichment';



COMMENT ON COLUMN "public"."emails"."ai_confidence_score" IS 'Confidence in AI classifications (0.0-1.0)';



CREATE TABLE IF NOT EXISTS "public"."mailboxes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "email" character varying NOT NULL,
    "name" character varying NOT NULL,
    "type" character varying,
    "imap_host" character varying DEFAULT 'mail.pdmedical.com.au'::character varying,
    "imap_port" integer DEFAULT 993,
    "imap_username" character varying,
    "is_active" boolean DEFAULT true,
    "last_synced_at" timestamp with time zone,
    "last_synced_uid" "jsonb" DEFAULT '{}'::"jsonb",
    "sync_status" "jsonb" DEFAULT '{}'::"jsonb",
    "sync_settings" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "mailboxes_type_check" CHECK ((("type")::"text" = ANY (ARRAY[('personal'::character varying)::"text", ('team'::character varying)::"text", ('department'::character varying)::"text"])))
);


ALTER TABLE "public"."mailboxes" OWNER TO "postgres";


COMMENT ON TABLE "public"."mailboxes" IS 'Owner email accounts for synchronization. IMAP passwords stored as Supabase secrets: IMAP_PASSWORD_{id}';



COMMENT ON COLUMN "public"."mailboxes"."last_synced_uid" IS 'JSON object tracking last synced UID per folder: {"INBOX": 1234, "Sent": 5678}';



COMMENT ON COLUMN "public"."mailboxes"."sync_status" IS 'JSON object for error tracking and sync state';



CREATE TABLE IF NOT EXISTS "public"."organization_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" character varying NOT NULL,
    "description" "text",
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."organization_types" OWNER TO "postgres";


COMMENT ON TABLE "public"."organization_types" IS 'Lookup table for organization types (Hospital, Clinic, Aged Care, etc.)';



CREATE TABLE IF NOT EXISTS "public"."organizations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" character varying NOT NULL,
    "domain" character varying NOT NULL,
    "phone" character varying,
    "address" "text",
    "industry" character varying,
    "website" character varying,
    "status" character varying DEFAULT 'active'::character varying,
    "tags" "jsonb" DEFAULT '[]'::"jsonb",
    "custom_fields" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "organization_type_id" "uuid",
    "region" character varying,
    "hospital_category" character varying,
    "city" character varying,
    "state" character varying,
    "key_hospital" character varying,
    "street_address" character varying,
    "suburb" character varying,
    "facility_type" character varying,
    "bed_count" integer,
    "top_150_ranking" integer,
    "general_info" "text",
    "products_sold" "text"[],
    "has_maternity" boolean DEFAULT false,
    "has_operating_theatre" boolean DEFAULT false,
    "typical_job_roles" "text"[],
    "contact_count" integer DEFAULT 0,
    "enriched_from_signatures_at" timestamp with time zone,
    "auth_user_id" "uuid"
);


ALTER TABLE "public"."organizations" OWNER TO "postgres";


COMMENT ON TABLE "public"."organizations" IS 'Customer organizations with healthcare-specific fields';



COMMENT ON COLUMN "public"."organizations"."region" IS 'Geographic region (if any)';



COMMENT ON COLUMN "public"."organizations"."hospital_category" IS 'Hospital category classification';



COMMENT ON COLUMN "public"."organizations"."city" IS 'City or county';



COMMENT ON COLUMN "public"."organizations"."state" IS 'State (NSW, VIC, QLD, etc.)';



COMMENT ON COLUMN "public"."organizations"."key_hospital" IS 'Key hospital rank';



COMMENT ON COLUMN "public"."organizations"."street_address" IS 'Street address';



COMMENT ON COLUMN "public"."organizations"."suburb" IS 'Suburb';



COMMENT ON COLUMN "public"."organizations"."facility_type" IS 'Facility type (Public, Private, Ramsay, Healthscope, etc.)';



COMMENT ON COLUMN "public"."organizations"."bed_count" IS 'Number of beds';



COMMENT ON COLUMN "public"."organizations"."top_150_ranking" IS 'Top 150 ranking position';



COMMENT ON COLUMN "public"."organizations"."general_info" IS 'General information (freeform text)';



COMMENT ON COLUMN "public"."organizations"."products_sold" IS 'Array of products sold to this organization';



COMMENT ON COLUMN "public"."organizations"."has_maternity" IS 'Has maternity services';



COMMENT ON COLUMN "public"."organizations"."has_operating_theatre" IS 'Has operating theatre';



COMMENT ON COLUMN "public"."organizations"."typical_job_roles" IS 'Common roles seen in this organization';



COMMENT ON COLUMN "public"."organizations"."contact_count" IS 'Number of contacts from this organization';



COMMENT ON COLUMN "public"."organizations"."enriched_from_signatures_at" IS 'When organization was last enriched from contact signatures';



CREATE TABLE IF NOT EXISTS "public"."parent_products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "parent_code" character varying(100) NOT NULL,
    "parent_name" character varying(255) NOT NULL,
    "parent_parent_id" "uuid",
    "category_id" "uuid",
    "category_name" character varying(100),
    "hierarchy_level" integer DEFAULT 1,
    "sales_priority" integer,
    "sales_priority_label" character varying(20),
    "sales_instructions" "text",
    "sales_timing_notes" "text",
    "description" "text",
    "display_order" integer,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "parent_products_hierarchy_level_check" CHECK (("hierarchy_level" = ANY (ARRAY[1, 2]))),
    CONSTRAINT "parent_products_sales_priority_check" CHECK ((("sales_priority" >= 1) AND ("sales_priority" <= 3)))
);


ALTER TABLE "public"."parent_products" OWNER TO "postgres";


COMMENT ON TABLE "public"."parent_products" IS '7 Super Parents + 20 Sub-Parents structure for product hierarchy';



CREATE TABLE IF NOT EXISTS "public"."product_categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "category_name" character varying(100) NOT NULL,
    "description" "text",
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."product_categories" OWNER TO "postgres";


COMMENT ON TABLE "public"."product_categories" IS 'Product categories from Excel';



CREATE TABLE IF NOT EXISTS "public"."products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "product_code" character varying(100) NOT NULL,
    "product_name" character varying(500),
    "category_id" "uuid",
    "category_name" character varying(100),
    "market_potential" "text",
    "background_history" "text",
    "key_contacts_reference" "text",
    "forecast_notes" "text",
    "sales_priority" integer,
    "sales_priority_label" character varying(20),
    "sales_instructions" "text",
    "sales_timing_notes" "text",
    "sales_status" character varying(50) DEFAULT 'active'::character varying,
    "unit_price" numeric(12,2),
    "hsv_price" numeric(12,2),
    "qty_per_box" integer,
    "moq" integer,
    "currency" character varying(3) DEFAULT 'AUD'::character varying,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "parent_product_id" "uuid",
    CONSTRAINT "products_sales_priority_check" CHECK ((("sales_priority" >= 1) AND ("sales_priority" <= 3)))
);


ALTER TABLE "public"."products" OWNER TO "postgres";


COMMENT ON TABLE "public"."products" IS 'Complete products table with info from both Excel sections (product info + pricing)';



COMMENT ON COLUMN "public"."products"."market_potential" IS 'From Section 1: Market potential description';



COMMENT ON COLUMN "public"."products"."background_history" IS 'From Section 1: Product background and history';



COMMENT ON COLUMN "public"."products"."key_contacts_reference" IS 'From Section 1: Raw text containing contact information';



COMMENT ON COLUMN "public"."products"."unit_price" IS 'From Section 2: Standard unit price in AUD';



COMMENT ON COLUMN "public"."products"."hsv_price" IS 'From Section 2: HSV (Hospital) price in AUD';



COMMENT ON COLUMN "public"."products"."qty_per_box" IS 'From Section 2: Quantity per box/package';



COMMENT ON COLUMN "public"."products"."moq" IS 'From Section 2: Minimum Order Quantity';



CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "auth_user_id" "uuid" NOT NULL,
    "full_name" "text" NOT NULL,
    "role" "public"."role_type" DEFAULT 'sales'::"public"."role_type" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "profile_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."profiles_with_email" AS
 SELECT "p"."profile_id",
    "p"."auth_user_id",
    "p"."full_name",
    "p"."role",
    "p"."created_at",
    "p"."updated_at",
    "u"."email"
   FROM ("public"."profiles" "p"
     JOIN "auth"."users" "u" ON (("u"."id" = "p"."auth_user_id")));


ALTER VIEW "public"."profiles_with_email" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."role_permissions" (
    "role" "public"."role_type" NOT NULL,
    "view_users" boolean DEFAULT false NOT NULL,
    "manage_users" boolean DEFAULT false NOT NULL,
    "view_contacts" boolean DEFAULT false NOT NULL,
    "manage_contacts" boolean DEFAULT false NOT NULL,
    "view_campaigns" boolean DEFAULT false NOT NULL,
    "manage_campaigns" boolean DEFAULT false NOT NULL,
    "approve_campaigns" boolean DEFAULT false NOT NULL,
    "view_analytics" boolean DEFAULT false NOT NULL,
    "manage_approvals" boolean DEFAULT false NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "view_workflows" boolean DEFAULT true NOT NULL,
    "view_emails" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."role_permissions" OWNER TO "postgres";


COMMENT ON COLUMN "public"."role_permissions"."view_workflows" IS 'Permission to view and access workflows page';



COMMENT ON COLUMN "public"."role_permissions"."view_emails" IS 'Permission to view and access emails page';



CREATE TABLE IF NOT EXISTS "public"."system_config" (
    "key" character varying NOT NULL,
    "value" "jsonb" NOT NULL,
    "description" "text",
    "updated_at" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."system_config" OWNER TO "postgres";


COMMENT ON TABLE "public"."system_config" IS 'Global system configuration for enrichment rules and validation';



CREATE TABLE IF NOT EXISTS "public"."user_permissions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "auth_user_id" "uuid" NOT NULL,
    "view_users" boolean,
    "manage_users" boolean,
    "view_contacts" boolean,
    "manage_contacts" boolean,
    "view_campaigns" boolean,
    "manage_campaigns" boolean,
    "approve_campaigns" boolean,
    "view_analytics" boolean,
    "manage_approvals" boolean,
    "view_workflows" boolean,
    "view_emails" boolean,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "created_by" "uuid"
);


ALTER TABLE "public"."user_permissions" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_permissions" IS 'Stores per-user permission overrides that take precedence over role-based defaults';



CREATE OR REPLACE VIEW "public"."v_campaign_enrollments_due" AS
 SELECT "ce"."id" AS "enrollment_id",
    "ce"."campaign_sequence_id",
    "cs"."name" AS "campaign_name",
    "cs"."steps",
    "ce"."contact_id",
    "c"."email" AS "contact_email",
    "c"."first_name",
    "c"."last_name",
    "ce"."current_step",
    "ce"."next_send_date",
    "ce"."steps_completed",
    "cs"."from_mailbox_id",
    "m"."email" AS "from_mailbox_email"
   FROM ((("public"."campaign_enrollments" "ce"
     JOIN "public"."campaign_sequences" "cs" ON (("ce"."campaign_sequence_id" = "cs"."id")))
     JOIN "public"."contacts" "c" ON (("ce"."contact_id" = "c"."id")))
     LEFT JOIN "public"."mailboxes" "m" ON (("cs"."from_mailbox_id" = "m"."id")))
  WHERE ((("ce"."status")::"text" = 'active'::"text") AND ("ce"."next_send_date" <= "now"()) AND (("cs"."status")::"text" = 'running'::"text"))
  ORDER BY "ce"."next_send_date";


ALTER VIEW "public"."v_campaign_enrollments_due" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_campaign_sequences_with_stats" AS
SELECT
    NULL::"uuid" AS "id",
    NULL::character varying(255) AS "name",
    NULL::"text" AS "description",
    NULL::character varying(50) AS "status",
    NULL::"uuid" AS "product_id",
    NULL::character varying(500) AS "product_name",
    NULL::"uuid" AS "from_mailbox_id",
    NULL::character varying AS "from_mailbox_email",
    NULL::integer AS "target_count",
    NULL::timestamp with time zone AS "scheduled_at",
    NULL::timestamp with time zone AS "started_at",
    NULL::timestamp with time zone AS "completed_at",
    NULL::"jsonb" AS "stats",
    NULL::bigint AS "total_enrollments",
    NULL::bigint AS "active_enrollments",
    NULL::bigint AS "completed_enrollments",
    NULL::bigint AS "replied_count",
    NULL::numeric AS "avg_opens_per_contact",
    NULL::numeric AS "avg_clicks_per_contact",
    NULL::timestamp with time zone AS "created_at",
    NULL::timestamp with time zone AS "updated_at";


ALTER VIEW "public"."v_campaign_sequences_with_stats" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_complete_hierarchy" AS
 SELECT "sp"."id" AS "super_parent_id",
    "sp"."parent_code" AS "super_parent_code",
    "sp"."parent_name" AS "super_parent_name",
    "subp"."id" AS "sub_parent_id",
    "subp"."parent_code" AS "sub_parent_code",
    "subp"."parent_name" AS "sub_parent_name",
    "subp"."sales_priority",
    "subp"."sales_priority_label",
    "p"."id" AS "product_id",
    "p"."product_code",
    "p"."product_name",
    "p"."unit_price",
    "p"."category_name"
   FROM (("public"."products" "p"
     LEFT JOIN "public"."parent_products" "subp" ON (("p"."parent_product_id" = "subp"."id")))
     LEFT JOIN "public"."parent_products" "sp" ON (("subp"."parent_parent_id" = "sp"."id")))
  WHERE ("p"."is_active" = true)
  ORDER BY "sp"."display_order", "subp"."display_order", "p"."product_code";


ALTER VIEW "public"."v_complete_hierarchy" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_contacts_with_interests" AS
 SELECT "c"."id" AS "contact_id",
    "c"."email",
    "c"."first_name",
    "c"."last_name",
    "c"."lead_score",
    "c"."lead_classification",
    "c"."engagement_level",
    "o"."name" AS "organization_name",
    "o"."domain" AS "organization_domain",
    "count"("cpi"."product_id") AS "products_interested_in",
    "string_agg"(("p"."product_name")::"text", ', '::"text" ORDER BY ("p"."product_name")::"text") AS "product_names",
    "string_agg"(("p"."product_code")::"text", ', '::"text" ORDER BY ("p"."product_code")::"text") AS "product_codes",
    "max"("cpi"."last_interaction_date") AS "last_product_interaction_date"
   FROM ((("public"."contacts" "c"
     LEFT JOIN "public"."organizations" "o" ON (("c"."organization_id" = "o"."id")))
     LEFT JOIN "public"."contact_product_interests" "cpi" ON (("c"."id" = "cpi"."contact_id")))
     LEFT JOIN "public"."products" "p" ON (("cpi"."product_id" = "p"."id")))
  GROUP BY "c"."id", "c"."email", "c"."first_name", "c"."last_name", "c"."lead_score", "c"."lead_classification", "c"."engagement_level", "o"."name", "o"."domain";


ALTER VIEW "public"."v_contacts_with_interests" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_enrichment_config" AS
 SELECT 'valid_categories'::"text" AS "config_type",
    ((("jsonb_array_length"(("system_config"."value" -> 'business'::"text")) + "jsonb_array_length"(("system_config"."value" -> 'spam'::"text"))) + "jsonb_array_length"(("system_config"."value" -> 'personal'::"text"))) + "jsonb_array_length"(("system_config"."value" -> 'other'::"text"))) AS "total_count",
    "system_config"."value" AS "config_value"
   FROM "public"."system_config"
  WHERE (("system_config"."key")::"text" = 'valid_email_categories'::"text")
UNION ALL
 SELECT 'valid_intents'::"text" AS "config_type",
    "jsonb_array_length"(("system_config"."value" -> 'intents'::"text")) AS "total_count",
    "system_config"."value" AS "config_value"
   FROM "public"."system_config"
  WHERE (("system_config"."key")::"text" = 'valid_email_intents'::"text")
UNION ALL
 SELECT 'valid_sentiments'::"text" AS "config_type",
    "jsonb_array_length"(("system_config"."value" -> 'sentiments'::"text")) AS "total_count",
    "system_config"."value" AS "config_value"
   FROM "public"."system_config"
  WHERE (("system_config"."key")::"text" = 'valid_email_sentiments'::"text")
UNION ALL
 SELECT 'workflow_category_rules'::"text" AS "config_type",
    ("jsonb_array_length"(("system_config"."value" -> 'enabled_categories'::"text")) + "jsonb_array_length"(("system_config"."value" -> 'disabled_categories'::"text"))) AS "total_count",
    "system_config"."value" AS "config_value"
   FROM "public"."system_config"
  WHERE (("system_config"."key")::"text" = 'workflow_category_rules'::"text");


ALTER VIEW "public"."v_enrichment_config" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_enrichment_stats" AS
 SELECT 'emails'::"text" AS "table_name",
    "count"(*) AS "total_records",
    "count"("emails"."email_category") AS "enriched_category",
    "count"("emails"."intent") AS "enriched_intent",
    "count"("emails"."sentiment") AS "enriched_sentiment",
    "count"("emails"."priority_score") AS "enriched_priority",
    "round"("avg"("emails"."ai_confidence_score"), 2) AS "avg_confidence",
    "count"("emails"."ai_processed_at") AS "ai_processed_count"
   FROM "public"."emails"
UNION ALL
 SELECT 'contacts'::"text" AS "table_name",
    "count"(*) AS "total_records",
    "count"("contacts"."role") AS "enriched_category",
    "count"("contacts"."department") AS "enriched_intent",
    "count"("contacts"."lead_score") AS "enriched_sentiment",
    NULL::bigint AS "enriched_priority",
    NULL::numeric AS "avg_confidence",
    "count"("contacts"."enrichment_last_attempted_at") AS "ai_processed_count"
   FROM "public"."contacts"
UNION ALL
 SELECT 'conversations'::"text" AS "table_name",
    "count"(*) AS "total_records",
    "count"("conversations"."summary") AS "enriched_category",
    "count"("conversations"."action_items") AS "enriched_intent",
    NULL::bigint AS "enriched_sentiment",
    NULL::bigint AS "enriched_priority",
    NULL::numeric AS "avg_confidence",
    "count"("conversations"."last_summarized_at") AS "ai_processed_count"
   FROM "public"."conversations";


ALTER VIEW "public"."v_enrichment_stats" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_products_by_category" AS
 SELECT COALESCE("p"."category_name", 'Uncategorized'::character varying) AS "category",
    "count"(*) AS "product_count",
    "count"(DISTINCT "cpi"."contact_id") AS "total_interested_contacts",
    "count"(
        CASE
            WHEN ("p"."sales_priority" = 1) THEN 1
            ELSE NULL::integer
        END) AS "priority_1_count",
    "count"(
        CASE
            WHEN ("p"."sales_priority" = 2) THEN 1
            ELSE NULL::integer
        END) AS "priority_2_count",
    "count"(
        CASE
            WHEN ("p"."sales_priority" = 3) THEN 1
            ELSE NULL::integer
        END) AS "priority_3_count",
    "avg"("p"."unit_price") AS "avg_unit_price",
    "min"("p"."unit_price") AS "min_unit_price",
    "max"("p"."unit_price") AS "max_unit_price"
   FROM ("public"."products" "p"
     LEFT JOIN "public"."contact_product_interests" "cpi" ON (("p"."id" = "cpi"."product_id")))
  WHERE ("p"."is_active" = true)
  GROUP BY COALESCE("p"."category_name", 'Uncategorized'::character varying)
  ORDER BY COALESCE("p"."category_name", 'Uncategorized'::character varying);


ALTER VIEW "public"."v_products_by_category" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_products_pricing" AS
 SELECT "product_code",
    "product_name",
    "category_name",
    "unit_price",
    "hsv_price",
    "qty_per_box",
    "moq",
    "currency",
        CASE
            WHEN (("hsv_price" IS NOT NULL) AND ("unit_price" IS NOT NULL)) THEN "round"(((("hsv_price" - "unit_price") / "unit_price") * (100)::numeric), 2)
            ELSE NULL::numeric
        END AS "price_increase_percentage"
   FROM "public"."products" "p"
  WHERE ("unit_price" IS NOT NULL)
  ORDER BY "unit_price" DESC;


ALTER VIEW "public"."v_products_pricing" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_products_with_stats" AS
 SELECT "p"."id",
    "p"."product_code",
    "p"."product_name",
    "p"."category_name",
    "p"."sales_priority",
    "p"."sales_priority_label",
    "p"."sales_instructions",
    "p"."sales_timing_notes",
    "p"."market_potential",
    "p"."unit_price",
    "p"."hsv_price",
    "p"."qty_per_box",
    "p"."moq",
    "p"."currency",
    "p"."is_active",
    "count"(DISTINCT "cpi"."contact_id") AS "interested_contacts_count",
    "count"(DISTINCT "cpi"."organization_id") AS "interested_organizations_count",
    "count"(DISTINCT
        CASE
            WHEN (("cpi"."status")::"text" = 'quoted'::"text") THEN "cpi"."id"
            ELSE NULL::"uuid"
        END) AS "active_quotes_count",
    "sum"(
        CASE
            WHEN (("cpi"."status")::"text" = 'quoted'::"text") THEN ("cpi"."quoted_price" * ("cpi"."quoted_quantity")::numeric)
            ELSE (0)::numeric
        END) AS "total_quoted_value",
    "string_agg"(DISTINCT ("c"."email")::"text", ', '::"text" ORDER BY ("c"."email")::"text") AS "contact_emails"
   FROM (("public"."products" "p"
     LEFT JOIN "public"."contact_product_interests" "cpi" ON (("p"."id" = "cpi"."product_id")))
     LEFT JOIN "public"."contacts" "c" ON (("cpi"."contact_id" = "c"."id")))
  GROUP BY "p"."id", "p"."product_code", "p"."product_name", "p"."category_name", "p"."sales_priority", "p"."sales_priority_label", "p"."sales_instructions", "p"."sales_timing_notes", "p"."market_potential", "p"."unit_price", "p"."hsv_price", "p"."qty_per_box", "p"."moq", "p"."currency", "p"."is_active";


ALTER VIEW "public"."v_products_with_stats" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_sales_priority_dashboard" AS
 SELECT "p"."product_code",
    "p"."product_name",
    "p"."category_name",
    "p"."sales_priority",
    "p"."sales_priority_label",
    "p"."sales_instructions",
    "p"."sales_timing_notes",
    "p"."market_potential",
    "p"."unit_price",
    "count"(DISTINCT "cpi"."contact_id") AS "interested_contacts",
    "count"(DISTINCT "cpi"."organization_id") AS "interested_organizations",
    "count"(DISTINCT
        CASE
            WHEN (("cpi"."status")::"text" = 'quoted'::"text") THEN "cpi"."id"
            ELSE NULL::"uuid"
        END) AS "active_quotes",
    "sum"(
        CASE
            WHEN (("cpi"."status")::"text" = 'quoted'::"text") THEN ("cpi"."quoted_price" * ("cpi"."quoted_quantity")::numeric)
            ELSE (0)::numeric
        END) AS "total_quoted_value",
    "min"("cpi"."next_followup_date") AS "next_followup_date"
   FROM ("public"."products" "p"
     LEFT JOIN "public"."contact_product_interests" "cpi" ON (("p"."id" = "cpi"."product_id")))
  WHERE (("p"."is_active" = true) AND (("p"."sales_status")::"text" = 'active'::"text") AND ("p"."sales_priority" IS NOT NULL))
  GROUP BY "p"."product_code", "p"."product_name", "p"."category_name", "p"."sales_priority", "p"."sales_priority_label", "p"."sales_instructions", "p"."sales_timing_notes", "p"."market_potential", "p"."unit_price"
  ORDER BY "p"."sales_priority", "p"."product_name";


ALTER VIEW "public"."v_sales_priority_dashboard" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_super_parents_summary" AS
 SELECT "sp"."id",
    "sp"."parent_code",
    "sp"."parent_name",
    "sp"."category_name",
    "sp"."display_order",
    "count"(DISTINCT "subp"."id") AS "sub_parent_count",
    "count"(DISTINCT "p"."id") AS "total_product_count"
   FROM (("public"."parent_products" "sp"
     LEFT JOIN "public"."parent_products" "subp" ON (("subp"."parent_parent_id" = "sp"."id")))
     LEFT JOIN "public"."products" "p" ON ((("p"."parent_product_id" = "subp"."id") OR (("subp"."id" IS NULL) AND ("p"."parent_product_id" = "sp"."id")))))
  WHERE ("sp"."hierarchy_level" = 1)
  GROUP BY "sp"."id", "sp"."parent_code", "sp"."parent_name", "sp"."category_name", "sp"."display_order"
  ORDER BY "sp"."display_order";


ALTER VIEW "public"."v_super_parents_summary" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."workflow_executions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "workflow_id" "uuid" NOT NULL,
    "email_id" "uuid" NOT NULL,
    "status" character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    "extracted_data" "jsonb",
    "extraction_confidence" double precision,
    "actions_completed" "jsonb" DEFAULT '[]'::"jsonb",
    "actions_failed" "jsonb" DEFAULT '[]'::"jsonb",
    "pending_action_index" integer,
    "started_at" timestamp with time zone DEFAULT "now"(),
    "completed_at" timestamp with time zone,
    CONSTRAINT "workflow_executions_extraction_confidence_check" CHECK ((("extraction_confidence" >= (0)::double precision) AND ("extraction_confidence" <= (1)::double precision))),
    CONSTRAINT "workflow_executions_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['pending'::character varying, 'extracting'::character varying, 'executing'::character varying, 'awaiting_approval'::character varying, 'completed'::character varying, 'failed'::character varying])::"text"[])))
);


ALTER TABLE "public"."workflow_executions" OWNER TO "postgres";


COMMENT ON TABLE "public"."workflow_executions" IS 'Audit trail of workflow executions';



CREATE TABLE IF NOT EXISTS "public"."workflows" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" character varying(255) NOT NULL,
    "description" "text",
    "trigger_condition" "text" NOT NULL,
    "priority" integer DEFAULT 100,
    "extract_fields" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "actions" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "lead_score_rules" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "category_rules" "jsonb" DEFAULT '{"enabled_pattern": "business-*", "disabled_categories": ["business-transactional"]}'::"jsonb",
    "is_active" boolean DEFAULT true,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."workflows" OWNER TO "postgres";


COMMENT ON TABLE "public"."workflows" IS 'User-configured workflows for automated email processing';



COMMENT ON COLUMN "public"."workflows"."category_rules" IS 'Category matching rules: enabled_pattern, disabled_categories, custom overrides';



ALTER TABLE ONLY "public"."action_items"
    ADD CONSTRAINT "action_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ai_enrichment_logs"
    ADD CONSTRAINT "ai_enrichment_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."approval_queue"
    ADD CONSTRAINT "approval_queue_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_contact_summary"
    ADD CONSTRAINT "campaign_contact_summary_pkey" PRIMARY KEY ("campaign_id", "contact_id");



ALTER TABLE ONLY "public"."campaign_enrollments"
    ADD CONSTRAINT "campaign_enrollments_campaign_sequence_id_contact_id_key" UNIQUE ("campaign_sequence_id", "contact_id");



ALTER TABLE ONLY "public"."campaign_enrollments"
    ADD CONSTRAINT "campaign_enrollments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_events"
    ADD CONSTRAINT "campaign_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_sequences"
    ADD CONSTRAINT "campaign_sequences_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaigns"
    ADD CONSTRAINT "campaigns_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."contact_product_interests"
    ADD CONSTRAINT "contact_product_interests_contact_id_product_id_key" UNIQUE ("contact_id", "product_id");



ALTER TABLE ONLY "public"."contact_product_interests"
    ADD CONSTRAINT "contact_product_interests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_thread_id_unique" UNIQUE ("thread_id");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "customer_organizations_domain_key" UNIQUE ("domain");



ALTER TABLE ONLY "public"."email_drafts"
    ADD CONSTRAINT "email_drafts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."email_import_errors"
    ADD CONSTRAINT "email_import_errors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."email_import_errors"
    ADD CONSTRAINT "email_import_errors_unique" UNIQUE ("mailbox_id", "imap_folder", "imap_uid");



COMMENT ON CONSTRAINT "email_import_errors_unique" ON "public"."email_import_errors" IS 'Ensures only one error record per email UID';



ALTER TABLE ONLY "public"."email_templates"
    ADD CONSTRAINT "email_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."emails"
    ADD CONSTRAINT "emails_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."emails"
    ADD CONSTRAINT "emails_unique_imap" UNIQUE ("mailbox_id", "imap_folder", "imap_uid");



ALTER TABLE ONLY "public"."emails"
    ADD CONSTRAINT "emails_unique_message_id" UNIQUE ("message_id");



ALTER TABLE ONLY "public"."mailboxes"
    ADD CONSTRAINT "mailboxes_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."mailboxes"
    ADD CONSTRAINT "mailboxes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organization_types"
    ADD CONSTRAINT "organization_types_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."organization_types"
    ADD CONSTRAINT "organization_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."parent_products"
    ADD CONSTRAINT "parent_products_parent_code_key" UNIQUE ("parent_code");



ALTER TABLE ONLY "public"."parent_products"
    ADD CONSTRAINT "parent_products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_categories"
    ADD CONSTRAINT "product_categories_category_name_key" UNIQUE ("category_name");



ALTER TABLE ONLY "public"."product_categories"
    ADD CONSTRAINT "product_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_product_code_key" UNIQUE ("product_code");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("profile_id");



ALTER TABLE ONLY "public"."role_permissions"
    ADD CONSTRAINT "role_permissions_pkey" PRIMARY KEY ("role");



ALTER TABLE ONLY "public"."system_config"
    ADD CONSTRAINT "system_config_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."user_permissions"
    ADD CONSTRAINT "user_permissions_auth_user_unique" UNIQUE ("auth_user_id");



ALTER TABLE ONLY "public"."user_permissions"
    ADD CONSTRAINT "user_permissions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."workflow_executions"
    ADD CONSTRAINT "workflow_executions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."workflows"
    ADD CONSTRAINT "workflows_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_action_items_assigned" ON "public"."action_items" USING "btree" ("assigned_to", "status");



CREATE INDEX "idx_action_items_contact" ON "public"."action_items" USING "btree" ("contact_id", "created_at" DESC);



CREATE INDEX "idx_action_items_status_due" ON "public"."action_items" USING "btree" ("status", "due_date") WHERE (("status")::"text" = ANY ((ARRAY['open'::character varying, 'in_progress'::character varying])::"text"[]));



CREATE INDEX "idx_action_items_workflow" ON "public"."action_items" USING "btree" ("workflow_execution_id");



CREATE INDEX "idx_ai_logs_date" ON "public"."ai_enrichment_logs" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_ai_logs_operation" ON "public"."ai_enrichment_logs" USING "btree" ("operation_type");



CREATE INDEX "idx_approval_queue_decided_by" ON "public"."approval_queue" USING "btree" ("decided_by", "decided_at" DESC);



CREATE INDEX "idx_approval_queue_draft" ON "public"."approval_queue" USING "btree" ("draft_id") WHERE ("draft_id" IS NOT NULL);



CREATE INDEX "idx_approval_queue_langgraph" ON "public"."approval_queue" USING "btree" ("langgraph_thread_id") WHERE ("langgraph_thread_id" IS NOT NULL);



CREATE INDEX "idx_approval_queue_pending" ON "public"."approval_queue" USING "btree" ("status", "created_at" DESC) WHERE (("status")::"text" = 'pending'::"text");



CREATE INDEX "idx_approval_queue_workflow_execution" ON "public"."approval_queue" USING "btree" ("workflow_execution_id");



CREATE INDEX "idx_campaign_contact_summary_campaign_score" ON "public"."campaign_contact_summary" USING "btree" ("campaign_id", "total_score" DESC);



CREATE INDEX "idx_campaign_contact_summary_clicked" ON "public"."campaign_contact_summary" USING "btree" ("campaign_id") WHERE ("clicked" = true);



CREATE INDEX "idx_campaign_contact_summary_opened" ON "public"."campaign_contact_summary" USING "btree" ("campaign_id") WHERE ("opened" = true);



CREATE INDEX "idx_campaign_enrollments_campaign" ON "public"."campaign_enrollments" USING "btree" ("campaign_sequence_id", "status");



CREATE INDEX "idx_campaign_enrollments_contact" ON "public"."campaign_enrollments" USING "btree" ("contact_id");



CREATE INDEX "idx_campaign_enrollments_next_send" ON "public"."campaign_enrollments" USING "btree" ("next_send_date") WHERE (("status")::"text" = 'active'::"text");



CREATE INDEX "idx_campaign_enrollments_status" ON "public"."campaign_enrollments" USING "btree" ("status");



CREATE INDEX "idx_campaign_events_campaign_type" ON "public"."campaign_events" USING "btree" ("campaign_id", "event_type");



CREATE INDEX "idx_campaign_events_contact_timestamp" ON "public"."campaign_events" USING "btree" ("contact_id", "event_timestamp" DESC);



CREATE INDEX "idx_campaign_events_event_timestamp" ON "public"."campaign_events" USING "btree" ("event_timestamp" DESC);



CREATE UNIQUE INDEX "idx_campaign_events_external_id" ON "public"."campaign_events" USING "btree" ("external_id") WHERE ("external_id" IS NOT NULL);



CREATE INDEX "idx_campaign_sequences_created_by" ON "public"."campaign_sequences" USING "btree" ("created_by");



CREATE INDEX "idx_campaign_sequences_mailbox" ON "public"."campaign_sequences" USING "btree" ("from_mailbox_id");



CREATE INDEX "idx_campaign_sequences_product" ON "public"."campaign_sequences" USING "btree" ("product_id") WHERE ("product_id" IS NOT NULL);



CREATE INDEX "idx_campaign_sequences_scheduled" ON "public"."campaign_sequences" USING "btree" ("scheduled_at") WHERE (("status")::"text" = 'scheduled'::"text");



CREATE INDEX "idx_campaign_sequences_status" ON "public"."campaign_sequences" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "idx_campaigns_auth_user_id" ON "public"."campaigns" USING "btree" ("auth_user_id");



CREATE INDEX "idx_campaigns_product_id" ON "public"."campaigns" USING "btree" ("product_id") WHERE ("product_id" IS NOT NULL);



CREATE INDEX "idx_campaigns_provider" ON "public"."campaigns" USING "btree" ("provider");



CREATE INDEX "idx_campaigns_sent_at" ON "public"."campaigns" USING "btree" ("sent_at" DESC);



CREATE INDEX "idx_contact_interests_campaign" ON "public"."contact_product_interests" USING "btree" ("campaign_id") WHERE ("campaign_id" IS NOT NULL);



CREATE INDEX "idx_contact_interests_contact" ON "public"."contact_product_interests" USING "btree" ("contact_id");



CREATE INDEX "idx_contact_interests_followup" ON "public"."contact_product_interests" USING "btree" ("next_followup_date") WHERE ("next_followup_date" IS NOT NULL);



CREATE INDEX "idx_contact_interests_level" ON "public"."contact_product_interests" USING "btree" ("interest_level");



CREATE INDEX "idx_contact_interests_org" ON "public"."contact_product_interests" USING "btree" ("organization_id");



CREATE INDEX "idx_contact_interests_product" ON "public"."contact_product_interests" USING "btree" ("product_id");



CREATE INDEX "idx_contact_interests_status" ON "public"."contact_product_interests" USING "btree" ("status");



CREATE INDEX "idx_contact_product_interests_auth_user_id" ON "public"."contact_product_interests" USING "btree" ("auth_user_id");



CREATE INDEX "idx_contacts_auth_user_id" ON "public"."contacts" USING "btree" ("auth_user_id");



CREATE INDEX "idx_contacts_classification" ON "public"."contacts" USING "btree" ("lead_classification");



CREATE INDEX "idx_contacts_email" ON "public"."contacts" USING "btree" ("email");



CREATE INDEX "idx_contacts_engagement" ON "public"."contacts" USING "btree" ("engagement_level");



CREATE INDEX "idx_contacts_enrichment_pending" ON "public"."contacts" USING "btree" ("enrichment_status") WHERE (("enrichment_status")::"text" = 'pending'::"text");



CREATE INDEX "idx_contacts_lead_score" ON "public"."contacts" USING "btree" ("lead_score" DESC);



CREATE UNIQUE INDEX "idx_contacts_name_org_unique" ON "public"."contacts" USING "btree" ("lower"(TRIM(BOTH FROM "first_name")), "lower"(TRIM(BOTH FROM "last_name")), "organization_id") WHERE (("first_name" IS NOT NULL) AND ("last_name" IS NOT NULL) AND ("organization_id" IS NOT NULL));



CREATE INDEX "idx_contacts_organization_id" ON "public"."contacts" USING "btree" ("organization_id");



CREATE INDEX "idx_contacts_placeholder_email" ON "public"."contacts" USING "btree" ((("custom_fields" ->> 'placeholder_email'::"text"))) WHERE (("custom_fields" ->> 'placeholder_email'::"text") = 'true'::"text");



CREATE INDEX "idx_conversations_auth_user_id" ON "public"."conversations" USING "btree" ("auth_user_id");



CREATE INDEX "idx_conversations_last_email_at" ON "public"."conversations" USING "btree" ("last_email_at" DESC);



CREATE INDEX "idx_conversations_mailbox_id" ON "public"."conversations" USING "btree" ("mailbox_id");



CREATE INDEX "idx_conversations_needs_summary" ON "public"."conversations" USING "btree" ("last_summarized_at", "email_count") WHERE ("email_count" > COALESCE("email_count_at_last_summary", 0));



CREATE INDEX "idx_conversations_organization_id" ON "public"."conversations" USING "btree" ("organization_id");



CREATE INDEX "idx_conversations_primary_contact_id" ON "public"."conversations" USING "btree" ("primary_contact_id");



CREATE INDEX "idx_conversations_status" ON "public"."conversations" USING "btree" ("status");



CREATE INDEX "idx_conversations_thread_id" ON "public"."conversations" USING "btree" ("thread_id");



CREATE INDEX "idx_email_drafts_approval_status" ON "public"."email_drafts" USING "btree" ("approval_status", "created_at" DESC);



CREATE INDEX "idx_email_drafts_campaign" ON "public"."email_drafts" USING "btree" ("campaign_enrollment_id") WHERE ("campaign_enrollment_id" IS NOT NULL);



CREATE INDEX "idx_email_drafts_contact" ON "public"."email_drafts" USING "btree" ("contact_id") WHERE ("contact_id" IS NOT NULL);



CREATE INDEX "idx_email_drafts_langgraph" ON "public"."email_drafts" USING "btree" ("langgraph_thread_id") WHERE ("langgraph_thread_id" IS NOT NULL);



CREATE INDEX "idx_email_drafts_pending" ON "public"."email_drafts" USING "btree" ("approval_status") WHERE (("approval_status")::"text" = 'pending'::"text");



CREATE INDEX "idx_email_drafts_thread" ON "public"."email_drafts" USING "btree" ("thread_id") WHERE ("thread_id" IS NOT NULL);



CREATE INDEX "idx_email_drafts_workflow" ON "public"."email_drafts" USING "btree" ("workflow_execution_id") WHERE ("workflow_execution_id" IS NOT NULL);



CREATE INDEX "idx_email_import_errors_created_at" ON "public"."email_import_errors" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_email_import_errors_mailbox_folder" ON "public"."email_import_errors" USING "btree" ("mailbox_id", "imap_folder");



CREATE INDEX "idx_email_import_errors_resolved" ON "public"."email_import_errors" USING "btree" ("resolved_at") WHERE ("resolved_at" IS NOT NULL);



CREATE INDEX "idx_email_import_errors_retry" ON "public"."email_import_errors" USING "btree" ("retry_count", "last_attempt_at") WHERE ("resolved_at" IS NULL);



CREATE INDEX "idx_email_templates_active" ON "public"."email_templates" USING "btree" ("is_active") WHERE ("is_active" = true);



CREATE INDEX "idx_email_templates_category" ON "public"."email_templates" USING "btree" ("category");



CREATE INDEX "idx_emails_ai_pending" ON "public"."emails" USING "btree" ("ai_processed_at") WHERE ("ai_processed_at" IS NULL);



CREATE INDEX "idx_emails_auth_user_id" ON "public"."emails" USING "btree" ("auth_user_id");



CREATE INDEX "idx_emails_category" ON "public"."emails" USING "btree" ("email_category") WHERE ("email_category" IS NOT NULL);



CREATE INDEX "idx_emails_contact_id" ON "public"."emails" USING "btree" ("contact_id");



CREATE INDEX "idx_emails_conversation_id" ON "public"."emails" USING "btree" ("conversation_id");



CREATE INDEX "idx_emails_direction" ON "public"."emails" USING "btree" ("direction");



CREATE INDEX "idx_emails_from_email" ON "public"."emails" USING "btree" ("from_email");



CREATE INDEX "idx_emails_imap_folder" ON "public"."emails" USING "btree" ("imap_folder");



CREATE INDEX "idx_emails_intent" ON "public"."emails" USING "btree" ("intent") WHERE ("intent" IS NOT NULL);



CREATE INDEX "idx_emails_mailbox_id" ON "public"."emails" USING "btree" ("mailbox_id");



CREATE INDEX "idx_emails_message_id" ON "public"."emails" USING "btree" ("message_id");



CREATE INDEX "idx_emails_needs_parsing" ON "public"."emails" USING "btree" ("needs_parsing") WHERE ("needs_parsing" = true);



CREATE INDEX "idx_emails_organization_id" ON "public"."emails" USING "btree" ("organization_id");



CREATE INDEX "idx_emails_priority" ON "public"."emails" USING "btree" ("priority_score" DESC) WHERE ("priority_score" > 70);



CREATE INDEX "idx_emails_received_at" ON "public"."emails" USING "btree" ("received_at" DESC);



CREATE INDEX "idx_emails_thread_id" ON "public"."emails" USING "btree" ("thread_id");



CREATE INDEX "idx_mailboxes_email" ON "public"."mailboxes" USING "btree" ("email");



CREATE INDEX "idx_mailboxes_is_active" ON "public"."mailboxes" USING "btree" ("is_active");



CREATE INDEX "idx_organizations_auth_user_id" ON "public"."organizations" USING "btree" ("auth_user_id");



CREATE INDEX "idx_organizations_city" ON "public"."organizations" USING "btree" ("city");



CREATE INDEX "idx_organizations_city_not_null" ON "public"."organizations" USING "btree" ("city") WHERE ("city" IS NOT NULL);



CREATE INDEX "idx_organizations_contact_count" ON "public"."organizations" USING "btree" ("contact_count" DESC);



CREATE INDEX "idx_organizations_domain" ON "public"."organizations" USING "btree" ("domain");



CREATE INDEX "idx_organizations_facility_type" ON "public"."organizations" USING "btree" ("facility_type");



CREATE INDEX "idx_organizations_organization_type_id" ON "public"."organizations" USING "btree" ("organization_type_id");



CREATE INDEX "idx_organizations_region_not_null" ON "public"."organizations" USING "btree" ("region") WHERE ("region" IS NOT NULL);



CREATE INDEX "idx_organizations_state" ON "public"."organizations" USING "btree" ("state");



CREATE INDEX "idx_organizations_state_not_null" ON "public"."organizations" USING "btree" ("state") WHERE ("state" IS NOT NULL);



CREATE INDEX "idx_parent_products_category" ON "public"."parent_products" USING "btree" ("category_id");



CREATE INDEX "idx_parent_products_code" ON "public"."parent_products" USING "btree" ("parent_code");



CREATE INDEX "idx_parent_products_level" ON "public"."parent_products" USING "btree" ("hierarchy_level");



CREATE INDEX "idx_parent_products_parent_parent" ON "public"."parent_products" USING "btree" ("parent_parent_id");



CREATE INDEX "idx_parent_products_priority" ON "public"."parent_products" USING "btree" ("sales_priority");



CREATE INDEX "idx_product_categories_active" ON "public"."product_categories" USING "btree" ("is_active");



CREATE INDEX "idx_products_active" ON "public"."products" USING "btree" ("is_active");



CREATE INDEX "idx_products_category" ON "public"."products" USING "btree" ("category_id");



CREATE INDEX "idx_products_category_name" ON "public"."products" USING "btree" ("category_name");



CREATE INDEX "idx_products_code" ON "public"."products" USING "btree" ("product_code");



CREATE INDEX "idx_products_name_search" ON "public"."products" USING "gin" ("to_tsvector"('"english"'::"regconfig", (COALESCE("product_name", ''::character varying))::"text"));



CREATE INDEX "idx_products_parent" ON "public"."products" USING "btree" ("parent_product_id");



CREATE INDEX "idx_products_priority" ON "public"."products" USING "btree" ("sales_priority") WHERE ("sales_priority" IS NOT NULL);



CREATE INDEX "idx_products_status" ON "public"."products" USING "btree" ("sales_status");



CREATE INDEX "idx_products_unit_price" ON "public"."products" USING "btree" ("unit_price") WHERE ("unit_price" IS NOT NULL);



CREATE INDEX "idx_profiles_auth_user_id" ON "public"."profiles" USING "btree" ("auth_user_id");



CREATE INDEX "idx_profiles_role" ON "public"."profiles" USING "btree" ("role");



CREATE INDEX "idx_role_permissions_role" ON "public"."role_permissions" USING "btree" ("role");



CREATE INDEX "idx_system_config_key" ON "public"."system_config" USING "btree" ("key");



CREATE INDEX "idx_user_permissions_auth_user_id" ON "public"."user_permissions" USING "btree" ("auth_user_id");



CREATE INDEX "idx_workflow_executions_email" ON "public"."workflow_executions" USING "btree" ("email_id");



CREATE INDEX "idx_workflow_executions_pending" ON "public"."workflow_executions" USING "btree" ("status") WHERE (("status")::"text" = 'awaiting_approval'::"text");



CREATE INDEX "idx_workflow_executions_status" ON "public"."workflow_executions" USING "btree" ("status", "started_at" DESC);



CREATE INDEX "idx_workflow_executions_workflow" ON "public"."workflow_executions" USING "btree" ("workflow_id", "started_at" DESC);



CREATE INDEX "idx_workflows_active" ON "public"."workflows" USING "btree" ("is_active") WHERE ("is_active" = true);



CREATE INDEX "idx_workflows_active_priority" ON "public"."workflows" USING "btree" ("is_active", "priority") WHERE ("is_active" = true);



CREATE INDEX "idx_workflows_created_by" ON "public"."workflows" USING "btree" ("created_by");



CREATE OR REPLACE VIEW "public"."v_campaign_sequences_with_stats" AS
 SELECT "cs"."id",
    "cs"."name",
    "cs"."description",
    "cs"."status",
    "cs"."product_id",
    "p"."product_name",
    "cs"."from_mailbox_id",
    "m"."email" AS "from_mailbox_email",
    "cs"."target_count",
    "cs"."scheduled_at",
    "cs"."started_at",
    "cs"."completed_at",
    "cs"."stats",
    "count"("ce"."id") AS "total_enrollments",
    "count"("ce"."id") FILTER (WHERE (("ce"."status")::"text" = 'active'::"text")) AS "active_enrollments",
    "count"("ce"."id") FILTER (WHERE (("ce"."status")::"text" = 'completed'::"text")) AS "completed_enrollments",
    "count"("ce"."id") FILTER (WHERE ("ce"."replied" = true)) AS "replied_count",
    "avg"("ce"."total_opens") AS "avg_opens_per_contact",
    "avg"("ce"."total_clicks") AS "avg_clicks_per_contact",
    "cs"."created_at",
    "cs"."updated_at"
   FROM ((("public"."campaign_sequences" "cs"
     LEFT JOIN "public"."campaign_enrollments" "ce" ON (("cs"."id" = "ce"."campaign_sequence_id")))
     LEFT JOIN "public"."products" "p" ON (("cs"."product_id" = "p"."id")))
     LEFT JOIN "public"."mailboxes" "m" ON (("cs"."from_mailbox_id" = "m"."id")))
  GROUP BY "cs"."id", "p"."product_name", "m"."email";



CREATE OR REPLACE TRIGGER "campaigns_log_activity" AFTER INSERT OR UPDATE ON "public"."campaigns" FOR EACH ROW EXECUTE FUNCTION "public"."log_user_activity"();



CREATE OR REPLACE TRIGGER "campaigns_set_approved_by" BEFORE UPDATE ON "public"."campaigns" FOR EACH ROW EXECUTE FUNCTION "public"."set_approved_by"();



CREATE OR REPLACE TRIGGER "campaigns_set_created_by" BEFORE INSERT ON "public"."campaigns" FOR EACH ROW EXECUTE FUNCTION "public"."set_created_by"();



CREATE OR REPLACE TRIGGER "prevent_role_change_trigger" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_role_change"();



CREATE OR REPLACE TRIGGER "profiles_set_timestamp" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."handle_profiles_updated_at"();



CREATE OR REPLACE TRIGGER "role_permissions_set_timestamp" BEFORE UPDATE ON "public"."role_permissions" FOR EACH ROW EXECUTE FUNCTION "public"."touch_role_permissions_updated_at"();



CREATE OR REPLACE TRIGGER "trigger_email_drafts_updated_at" BEFORE UPDATE ON "public"."email_drafts" FOR EACH ROW EXECUTE FUNCTION "public"."update_email_drafts_updated_at"();



CREATE OR REPLACE TRIGGER "trigger_update_lead_classification" BEFORE INSERT OR UPDATE OF "lead_score" ON "public"."contacts" FOR EACH ROW EXECUTE FUNCTION "public"."update_lead_classification"();



CREATE OR REPLACE TRIGGER "trigger_update_lead_score_from_interest" AFTER INSERT OR UPDATE OF "lead_score_contribution" ON "public"."contact_product_interests" FOR EACH ROW EXECUTE FUNCTION "public"."update_contact_lead_score_from_interest"();



CREATE OR REPLACE TRIGGER "update_action_items_updated_at" BEFORE UPDATE ON "public"."action_items" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_campaign_sequences_updated_at" BEFORE UPDATE ON "public"."campaign_sequences" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_categories_updated_at" BEFORE UPDATE ON "public"."product_categories" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_email_templates_updated_at" BEFORE UPDATE ON "public"."email_templates" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_interests_updated_at" BEFORE UPDATE ON "public"."contact_product_interests" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_products_updated_at" BEFORE UPDATE ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_system_config_updated_at" BEFORE UPDATE ON "public"."system_config" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_workflows_updated_at" BEFORE UPDATE ON "public"."workflows" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "user_permissions_set_timestamp" BEFORE UPDATE ON "public"."user_permissions" FOR EACH ROW EXECUTE FUNCTION "public"."handle_user_permissions_updated_at"();



ALTER TABLE ONLY "public"."action_items"
    ADD CONSTRAINT "action_items_assigned_to_fkey" FOREIGN KEY ("assigned_to") REFERENCES "public"."profiles"("profile_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."action_items"
    ADD CONSTRAINT "action_items_completed_by_fkey" FOREIGN KEY ("completed_by") REFERENCES "public"."profiles"("profile_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."action_items"
    ADD CONSTRAINT "action_items_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."action_items"
    ADD CONSTRAINT "action_items_email_id_fkey" FOREIGN KEY ("email_id") REFERENCES "public"."emails"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."action_items"
    ADD CONSTRAINT "action_items_workflow_execution_id_fkey" FOREIGN KEY ("workflow_execution_id") REFERENCES "public"."workflow_executions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."approval_queue"
    ADD CONSTRAINT "approval_queue_decided_by_fkey" FOREIGN KEY ("decided_by") REFERENCES "public"."profiles"("profile_id");



ALTER TABLE ONLY "public"."approval_queue"
    ADD CONSTRAINT "approval_queue_draft_id_fkey" FOREIGN KEY ("draft_id") REFERENCES "public"."email_drafts"("id");



ALTER TABLE ONLY "public"."approval_queue"
    ADD CONSTRAINT "approval_queue_workflow_execution_id_fkey" FOREIGN KEY ("workflow_execution_id") REFERENCES "public"."workflow_executions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_contact_summary"
    ADD CONSTRAINT "campaign_contact_summary_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_contact_summary"
    ADD CONSTRAINT "campaign_contact_summary_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_enrollments"
    ADD CONSTRAINT "campaign_enrollments_campaign_sequence_id_fkey" FOREIGN KEY ("campaign_sequence_id") REFERENCES "public"."campaign_sequences"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_enrollments"
    ADD CONSTRAINT "campaign_enrollments_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_events"
    ADD CONSTRAINT "campaign_events_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_events"
    ADD CONSTRAINT "campaign_events_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_sequences"
    ADD CONSTRAINT "campaign_sequences_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("profile_id");



ALTER TABLE ONLY "public"."campaign_sequences"
    ADD CONSTRAINT "campaign_sequences_from_mailbox_id_fkey" FOREIGN KEY ("from_mailbox_id") REFERENCES "public"."mailboxes"("id");



ALTER TABLE ONLY "public"."campaign_sequences"
    ADD CONSTRAINT "campaign_sequences_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaigns"
    ADD CONSTRAINT "campaigns_auth_user_id_fkey" FOREIGN KEY ("auth_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaigns"
    ADD CONSTRAINT "campaigns_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."contact_product_interests"
    ADD CONSTRAINT "contact_product_interests_auth_user_id_fkey" FOREIGN KEY ("auth_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contact_product_interests"
    ADD CONSTRAINT "contact_product_interests_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."contact_product_interests"
    ADD CONSTRAINT "contact_product_interests_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contact_product_interests"
    ADD CONSTRAINT "contact_product_interests_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contact_product_interests"
    ADD CONSTRAINT "contact_product_interests_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_auth_user_id_fkey" FOREIGN KEY ("auth_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_auth_user_id_fkey" FOREIGN KEY ("auth_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_mailbox_id_fkey" FOREIGN KEY ("mailbox_id") REFERENCES "public"."mailboxes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_primary_contact_id_fkey" FOREIGN KEY ("primary_contact_id") REFERENCES "public"."contacts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."email_drafts"
    ADD CONSTRAINT "email_drafts_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."profiles"("profile_id");



ALTER TABLE ONLY "public"."email_drafts"
    ADD CONSTRAINT "email_drafts_campaign_enrollment_id_fkey" FOREIGN KEY ("campaign_enrollment_id") REFERENCES "public"."campaign_enrollments"("id");



ALTER TABLE ONLY "public"."email_drafts"
    ADD CONSTRAINT "email_drafts_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id");



ALTER TABLE ONLY "public"."email_drafts"
    ADD CONSTRAINT "email_drafts_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "public"."conversations"("id");



ALTER TABLE ONLY "public"."email_drafts"
    ADD CONSTRAINT "email_drafts_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("profile_id");



ALTER TABLE ONLY "public"."email_drafts"
    ADD CONSTRAINT "email_drafts_from_mailbox_id_fkey" FOREIGN KEY ("from_mailbox_id") REFERENCES "public"."mailboxes"("id");



ALTER TABLE ONLY "public"."email_drafts"
    ADD CONSTRAINT "email_drafts_previous_draft_id_fkey" FOREIGN KEY ("previous_draft_id") REFERENCES "public"."email_drafts"("id");



ALTER TABLE ONLY "public"."email_drafts"
    ADD CONSTRAINT "email_drafts_sent_email_id_fkey" FOREIGN KEY ("sent_email_id") REFERENCES "public"."emails"("id");



ALTER TABLE ONLY "public"."email_drafts"
    ADD CONSTRAINT "email_drafts_source_email_id_fkey" FOREIGN KEY ("source_email_id") REFERENCES "public"."emails"("id");



ALTER TABLE ONLY "public"."email_drafts"
    ADD CONSTRAINT "email_drafts_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "public"."email_templates"("id");



ALTER TABLE ONLY "public"."email_drafts"
    ADD CONSTRAINT "email_drafts_workflow_execution_id_fkey" FOREIGN KEY ("workflow_execution_id") REFERENCES "public"."workflow_executions"("id");



ALTER TABLE ONLY "public"."email_import_errors"
    ADD CONSTRAINT "email_import_errors_mailbox_id_fkey" FOREIGN KEY ("mailbox_id") REFERENCES "public"."mailboxes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."email_templates"
    ADD CONSTRAINT "email_templates_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("profile_id");



ALTER TABLE ONLY "public"."emails"
    ADD CONSTRAINT "emails_auth_user_id_fkey" FOREIGN KEY ("auth_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."emails"
    ADD CONSTRAINT "emails_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."emails"
    ADD CONSTRAINT "emails_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "public"."conversations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."emails"
    ADD CONSTRAINT "emails_mailbox_id_fkey" FOREIGN KEY ("mailbox_id") REFERENCES "public"."mailboxes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."emails"
    ADD CONSTRAINT "emails_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_auth_user_id_fkey" FOREIGN KEY ("auth_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_organization_type_id_fkey" FOREIGN KEY ("organization_type_id") REFERENCES "public"."organization_types"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."parent_products"
    ADD CONSTRAINT "parent_products_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."product_categories"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."parent_products"
    ADD CONSTRAINT "parent_products_parent_parent_id_fkey" FOREIGN KEY ("parent_parent_id") REFERENCES "public"."parent_products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."product_categories"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_parent_product_id_fkey" FOREIGN KEY ("parent_product_id") REFERENCES "public"."parent_products"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_auth_user_id_fkey" FOREIGN KEY ("auth_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_permissions"
    ADD CONSTRAINT "user_permissions_auth_user_id_fkey" FOREIGN KEY ("auth_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_permissions"
    ADD CONSTRAINT "user_permissions_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."workflow_executions"
    ADD CONSTRAINT "workflow_executions_email_id_fkey" FOREIGN KEY ("email_id") REFERENCES "public"."emails"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."workflow_executions"
    ADD CONSTRAINT "workflow_executions_workflow_id_fkey" FOREIGN KEY ("workflow_id") REFERENCES "public"."workflows"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."workflows"
    ADD CONSTRAINT "workflows_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("profile_id");



CREATE POLICY "Admins can manage profiles" ON "public"."profiles" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."profiles" "me"
  WHERE (("me"."auth_user_id" = "auth"."uid"()) AND ("me"."role" = 'admin'::"public"."role_type"))))) WITH CHECK (true);



CREATE POLICY "Admins can manage user permissions" ON "public"."user_permissions" USING ("public"."has_permission"('manage_users'::"text"));



CREATE POLICY "Admins can read all profiles" ON "public"."profiles" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."profiles" "me"
  WHERE (("me"."auth_user_id" = "auth"."uid"()) AND ("me"."role" = 'admin'::"public"."role_type")))));



CREATE POLICY "Admins can update profiles" ON "public"."profiles" FOR UPDATE USING ("public"."has_permission"('manage_users'::"text"));



CREATE POLICY "Admins can view all profiles" ON "public"."profiles" FOR SELECT USING ("public"."has_permission"('view_users'::"text"));



CREATE POLICY "Allow insert workflows" ON "public"."workflows" FOR INSERT WITH CHECK (true);



CREATE POLICY "Allow read workflows" ON "public"."workflows" FOR SELECT USING (true);



CREATE POLICY "Profiles: admin read" ON "public"."profiles" FOR SELECT USING (("public"."current_jwt_role"() = 'admin'::"text"));



CREATE POLICY "Profiles: admin update" ON "public"."profiles" FOR UPDATE USING (("public"."current_jwt_role"() = 'admin'::"text")) WITH CHECK (("public"."current_jwt_role"() = 'admin'::"text"));



CREATE POLICY "Profiles: self insert" ON "public"."profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "auth_user_id"));



CREATE POLICY "Profiles: self read" ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "auth_user_id"));



CREATE POLICY "Profiles: self update" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "auth_user_id")) WITH CHECK (("auth"."uid"() = "auth_user_id"));



CREATE POLICY "Profiles: service insert" ON "public"."profiles" FOR INSERT WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "Role permissions: admin update" ON "public"."role_permissions" FOR UPDATE USING (("public"."current_jwt_role"() = 'admin'::"text")) WITH CHECK (("public"."current_jwt_role"() = 'admin'::"text"));



CREATE POLICY "Role permissions: read" ON "public"."role_permissions" FOR SELECT USING (true);



CREATE POLICY "Role permissions: service insert" ON "public"."role_permissions" FOR INSERT WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "Service role creates profiles" ON "public"."profiles" FOR INSERT WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "Users can create email drafts" ON "public"."email_drafts" FOR INSERT WITH CHECK (true);



CREATE POLICY "Users can read their own profile" ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "auth_user_id"));



CREATE POLICY "Users can update email drafts" ON "public"."email_drafts" FOR UPDATE USING (true);



CREATE POLICY "Users can update own profile" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("auth_user_id" = "auth"."uid"())) WITH CHECK (("auth_user_id" = "auth"."uid"()));



CREATE POLICY "Users can view email drafts" ON "public"."email_drafts" FOR SELECT USING (true);



CREATE POLICY "Users can view own permission overrides" ON "public"."user_permissions" FOR SELECT USING (("auth_user_id" = "auth"."uid"()));



CREATE POLICY "Users can view own profile" ON "public"."profiles" FOR SELECT TO "authenticated" USING (("auth_user_id" = "auth"."uid"()));



ALTER TABLE "public"."campaigns" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "campaigns_delete_policy" ON "public"."campaigns" FOR DELETE USING ("public"."has_permission"('manage_campaigns'::"text"));



CREATE POLICY "campaigns_insert_policy" ON "public"."campaigns" FOR INSERT WITH CHECK ("public"."has_permission"('manage_campaigns'::"text"));



CREATE POLICY "campaigns_select_policy" ON "public"."campaigns" FOR SELECT USING ("public"."has_permission"('view_campaigns'::"text"));



CREATE POLICY "campaigns_update_policy" ON "public"."campaigns" FOR UPDATE USING (("public"."has_permission"('manage_campaigns'::"text") OR "public"."has_permission"('approve_campaigns'::"text")));



ALTER TABLE "public"."contact_product_interests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "contact_product_interests_delete_policy" ON "public"."contact_product_interests" FOR DELETE USING ("public"."has_permission"('manage_contacts'::"text"));



CREATE POLICY "contact_product_interests_insert_policy" ON "public"."contact_product_interests" FOR INSERT WITH CHECK ("public"."has_permission"('manage_contacts'::"text"));



CREATE POLICY "contact_product_interests_select_policy" ON "public"."contact_product_interests" FOR SELECT USING ("public"."has_permission"('view_contacts'::"text"));



CREATE POLICY "contact_product_interests_update_policy" ON "public"."contact_product_interests" FOR UPDATE USING ("public"."has_permission"('manage_contacts'::"text"));



ALTER TABLE "public"."contacts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "contacts_delete_policy" ON "public"."contacts" FOR DELETE USING ("public"."has_permission"('manage_contacts'::"text"));



CREATE POLICY "contacts_insert_policy" ON "public"."contacts" FOR INSERT WITH CHECK ("public"."has_permission"('manage_contacts'::"text"));



CREATE POLICY "contacts_select_policy" ON "public"."contacts" FOR SELECT USING ("public"."has_permission"('view_contacts'::"text"));



CREATE POLICY "contacts_update_policy" ON "public"."contacts" FOR UPDATE USING ("public"."has_permission"('manage_contacts'::"text"));



ALTER TABLE "public"."conversations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "conversations_delete_policy" ON "public"."conversations" FOR DELETE USING ("public"."is_admin"());



CREATE POLICY "conversations_insert_policy" ON "public"."conversations" FOR INSERT WITH CHECK (true);



CREATE POLICY "conversations_select_policy" ON "public"."conversations" FOR SELECT USING ("public"."has_permission"('view_emails'::"text"));



CREATE POLICY "conversations_update_policy" ON "public"."conversations" FOR UPDATE USING (true);



ALTER TABLE "public"."email_drafts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."emails" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "emails_delete_policy" ON "public"."emails" FOR DELETE USING ("public"."is_admin"());



CREATE POLICY "emails_insert_policy" ON "public"."emails" FOR INSERT WITH CHECK (true);



CREATE POLICY "emails_select_policy" ON "public"."emails" FOR SELECT USING ("public"."has_permission"('view_emails'::"text"));



CREATE POLICY "emails_update_policy" ON "public"."emails" FOR UPDATE USING (true);



ALTER TABLE "public"."mailboxes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."organizations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "organizations_delete_policy" ON "public"."organizations" FOR DELETE USING ("public"."has_permission"('manage_contacts'::"text"));



CREATE POLICY "organizations_insert_policy" ON "public"."organizations" FOR INSERT WITH CHECK ("public"."has_permission"('manage_contacts'::"text"));



CREATE POLICY "organizations_select_policy" ON "public"."organizations" FOR SELECT USING ("public"."has_permission"('view_contacts'::"text"));



CREATE POLICY "organizations_update_policy" ON "public"."organizations" FOR UPDATE USING ("public"."has_permission"('manage_contacts'::"text"));



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "public_read_contacts" ON "public"."contacts" FOR SELECT USING (true);



CREATE POLICY "public_read_conversations" ON "public"."conversations" FOR SELECT USING (true);



CREATE POLICY "public_read_emails" ON "public"."emails" FOR SELECT USING (true);



CREATE POLICY "public_read_mailboxes" ON "public"."mailboxes" FOR SELECT USING (true);



ALTER TABLE "public"."role_permissions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_permissions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."workflow_executions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."workflows" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_update_user_role"("profile_id" "uuid", "new_role" "public"."role_type") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_update_user_role"("profile_id" "uuid", "new_role" "public"."role_type") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_update_user_role"("profile_id" "uuid", "new_role" "public"."role_type") TO "service_role";



GRANT ALL ON FUNCTION "public"."category_matches_workflow_rules"("p_category" character varying, "p_rules" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."category_matches_workflow_rules"("p_category" character varying, "p_rules" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."category_matches_workflow_rules"("p_category" character varying, "p_rules" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_cron_job_exists"("job_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."check_cron_job_exists"("job_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_cron_job_exists"("job_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."clear_user_permission_override"("target_user_id" "uuid", "permission_key" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."clear_user_permission_override"("target_user_id" "uuid", "permission_key" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."clear_user_permission_override"("target_user_id" "uuid", "permission_key" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."clear_user_permission_override"("target_user_id" "uuid", "permission_key" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."current_jwt_role"() TO "anon";
GRANT ALL ON FUNCTION "public"."current_jwt_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_jwt_role"() TO "service_role";



GRANT ALL ON FUNCTION "public"."exec_sql"("sql" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."exec_sql"("sql" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."exec_sql"("sql" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_campaign_enrollments_due"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_campaign_enrollments_due"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_campaign_enrollments_due"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_category_group"("p_category" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."get_category_group"("p_category" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_category_group"("p_category" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_cron_job_runs"("job_name" "text", "limit_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_cron_job_runs"("job_name" "text", "limit_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_cron_job_runs"("job_name" "text", "limit_count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_cron_job_status"("job_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_cron_job_status"("job_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_cron_job_status"("job_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_current_user_role"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_current_user_role"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_current_user_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_current_user_role"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_db_settings"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_db_settings"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_db_settings"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_profile_by_auth_user_id"("user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_profile_by_auth_user_id"("user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_profile_by_auth_user_id"("user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_user_effective_permissions"("target_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_user_effective_permissions"("target_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_effective_permissions"("target_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_effective_permissions"("target_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_workflows_for_category"("p_category" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."get_workflows_for_category"("p_category" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_workflows_for_category"("p_category" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_profiles_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_profiles_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_profiles_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."handle_user_permissions_updated_at"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_user_permissions_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_user_permissions_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_user_permissions_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."has_permission"("permission_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."has_permission"("permission_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."has_permission"("permission_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_permission"("permission_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_admin"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_valid_email_category"("p_category" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."is_valid_email_category"("p_category" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_valid_email_category"("p_category" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_valid_email_intent"("p_intent" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."is_valid_email_intent"("p_intent" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_valid_email_intent"("p_intent" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_valid_email_sentiment"("p_sentiment" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."is_valid_email_sentiment"("p_sentiment" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_valid_email_sentiment"("p_sentiment" character varying) TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_valid_permission"("p" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_valid_permission"("p" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_valid_permission"("p" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_valid_permission"("p" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."log_user_activity"() TO "anon";
GRANT ALL ON FUNCTION "public"."log_user_activity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_user_activity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_manual_user_override"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_manual_user_override"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_manual_user_override"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_role_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_role_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_role_change"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."remove_user_permission_overrides"("target_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."remove_user_permission_overrides"("target_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."remove_user_permission_overrides"("target_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."remove_user_permission_overrides"("target_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_approved_by"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_approved_by"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_approved_by"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_auth_user_tracking"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_auth_user_tracking"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_auth_user_tracking"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_auth_user_tracking"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_created_by"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_created_by"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_created_by"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_user_permission_override"("target_user_id" "uuid", "permission_updates" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_user_permission_override"("target_user_id" "uuid", "permission_updates" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."set_user_permission_override"("target_user_id" "uuid", "permission_updates" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_user_permission_override"("target_user_id" "uuid", "permission_updates" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."touch_role_permissions_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."touch_role_permissions_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_role_permissions_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_contact_lead_score_from_interest"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_contact_lead_score_from_interest"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_contact_lead_score_from_interest"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_conversation_stats"("p_conversation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."update_conversation_stats"("p_conversation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_conversation_stats"("p_conversation_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_email_drafts_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_email_drafts_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_email_drafts_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_lead_classification"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_lead_classification"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_lead_classification"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";



GRANT ALL ON TABLE "public"."action_items" TO "anon";
GRANT ALL ON TABLE "public"."action_items" TO "authenticated";
GRANT ALL ON TABLE "public"."action_items" TO "service_role";



GRANT ALL ON TABLE "public"."ai_enrichment_logs" TO "anon";
GRANT ALL ON TABLE "public"."ai_enrichment_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_enrichment_logs" TO "service_role";



GRANT ALL ON TABLE "public"."approval_queue" TO "anon";
GRANT ALL ON TABLE "public"."approval_queue" TO "authenticated";
GRANT ALL ON TABLE "public"."approval_queue" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_contact_summary" TO "anon";
GRANT ALL ON TABLE "public"."campaign_contact_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."campaign_contact_summary" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_enrollments" TO "anon";
GRANT ALL ON TABLE "public"."campaign_enrollments" TO "authenticated";
GRANT ALL ON TABLE "public"."campaign_enrollments" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_events" TO "anon";
GRANT ALL ON TABLE "public"."campaign_events" TO "authenticated";
GRANT ALL ON TABLE "public"."campaign_events" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_sequences" TO "anon";
GRANT ALL ON TABLE "public"."campaign_sequences" TO "authenticated";
GRANT ALL ON TABLE "public"."campaign_sequences" TO "service_role";



GRANT ALL ON TABLE "public"."campaigns" TO "anon";
GRANT ALL ON TABLE "public"."campaigns" TO "authenticated";
GRANT ALL ON TABLE "public"."campaigns" TO "service_role";



GRANT ALL ON TABLE "public"."contact_product_interests" TO "anon";
GRANT ALL ON TABLE "public"."contact_product_interests" TO "authenticated";
GRANT ALL ON TABLE "public"."contact_product_interests" TO "service_role";



GRANT ALL ON TABLE "public"."contacts" TO "anon";
GRANT ALL ON TABLE "public"."contacts" TO "authenticated";
GRANT ALL ON TABLE "public"."contacts" TO "service_role";



GRANT ALL ON TABLE "public"."conversations" TO "anon";
GRANT ALL ON TABLE "public"."conversations" TO "authenticated";
GRANT ALL ON TABLE "public"."conversations" TO "service_role";



GRANT ALL ON TABLE "public"."email_drafts" TO "anon";
GRANT ALL ON TABLE "public"."email_drafts" TO "authenticated";
GRANT ALL ON TABLE "public"."email_drafts" TO "service_role";



GRANT ALL ON TABLE "public"."email_import_errors" TO "anon";
GRANT ALL ON TABLE "public"."email_import_errors" TO "authenticated";
GRANT ALL ON TABLE "public"."email_import_errors" TO "service_role";



GRANT ALL ON TABLE "public"."email_templates" TO "anon";
GRANT ALL ON TABLE "public"."email_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."email_templates" TO "service_role";



GRANT ALL ON TABLE "public"."emails" TO "anon";
GRANT ALL ON TABLE "public"."emails" TO "authenticated";
GRANT ALL ON TABLE "public"."emails" TO "service_role";



GRANT ALL ON TABLE "public"."mailboxes" TO "anon";
GRANT ALL ON TABLE "public"."mailboxes" TO "authenticated";
GRANT ALL ON TABLE "public"."mailboxes" TO "service_role";



GRANT ALL ON TABLE "public"."organization_types" TO "anon";
GRANT ALL ON TABLE "public"."organization_types" TO "authenticated";
GRANT ALL ON TABLE "public"."organization_types" TO "service_role";



GRANT ALL ON TABLE "public"."organizations" TO "anon";
GRANT ALL ON TABLE "public"."organizations" TO "authenticated";
GRANT ALL ON TABLE "public"."organizations" TO "service_role";



GRANT ALL ON TABLE "public"."parent_products" TO "anon";
GRANT ALL ON TABLE "public"."parent_products" TO "authenticated";
GRANT ALL ON TABLE "public"."parent_products" TO "service_role";



GRANT ALL ON TABLE "public"."product_categories" TO "anon";
GRANT ALL ON TABLE "public"."product_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."product_categories" TO "service_role";



GRANT ALL ON TABLE "public"."products" TO "anon";
GRANT ALL ON TABLE "public"."products" TO "authenticated";
GRANT ALL ON TABLE "public"."products" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."profiles_with_email" TO "anon";
GRANT ALL ON TABLE "public"."profiles_with_email" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles_with_email" TO "service_role";



GRANT ALL ON TABLE "public"."role_permissions" TO "anon";
GRANT ALL ON TABLE "public"."role_permissions" TO "authenticated";
GRANT ALL ON TABLE "public"."role_permissions" TO "service_role";



GRANT ALL ON TABLE "public"."system_config" TO "anon";
GRANT ALL ON TABLE "public"."system_config" TO "authenticated";
GRANT ALL ON TABLE "public"."system_config" TO "service_role";



GRANT ALL ON TABLE "public"."user_permissions" TO "anon";
GRANT ALL ON TABLE "public"."user_permissions" TO "authenticated";
GRANT ALL ON TABLE "public"."user_permissions" TO "service_role";



GRANT ALL ON TABLE "public"."v_campaign_enrollments_due" TO "anon";
GRANT ALL ON TABLE "public"."v_campaign_enrollments_due" TO "authenticated";
GRANT ALL ON TABLE "public"."v_campaign_enrollments_due" TO "service_role";



GRANT ALL ON TABLE "public"."v_campaign_sequences_with_stats" TO "anon";
GRANT ALL ON TABLE "public"."v_campaign_sequences_with_stats" TO "authenticated";
GRANT ALL ON TABLE "public"."v_campaign_sequences_with_stats" TO "service_role";



GRANT ALL ON TABLE "public"."v_complete_hierarchy" TO "anon";
GRANT ALL ON TABLE "public"."v_complete_hierarchy" TO "authenticated";
GRANT ALL ON TABLE "public"."v_complete_hierarchy" TO "service_role";



GRANT ALL ON TABLE "public"."v_contacts_with_interests" TO "anon";
GRANT ALL ON TABLE "public"."v_contacts_with_interests" TO "authenticated";
GRANT ALL ON TABLE "public"."v_contacts_with_interests" TO "service_role";



GRANT ALL ON TABLE "public"."v_enrichment_config" TO "anon";
GRANT ALL ON TABLE "public"."v_enrichment_config" TO "authenticated";
GRANT ALL ON TABLE "public"."v_enrichment_config" TO "service_role";



GRANT ALL ON TABLE "public"."v_enrichment_stats" TO "anon";
GRANT ALL ON TABLE "public"."v_enrichment_stats" TO "authenticated";
GRANT ALL ON TABLE "public"."v_enrichment_stats" TO "service_role";



GRANT ALL ON TABLE "public"."v_products_by_category" TO "anon";
GRANT ALL ON TABLE "public"."v_products_by_category" TO "authenticated";
GRANT ALL ON TABLE "public"."v_products_by_category" TO "service_role";



GRANT ALL ON TABLE "public"."v_products_pricing" TO "anon";
GRANT ALL ON TABLE "public"."v_products_pricing" TO "authenticated";
GRANT ALL ON TABLE "public"."v_products_pricing" TO "service_role";



GRANT ALL ON TABLE "public"."v_products_with_stats" TO "anon";
GRANT ALL ON TABLE "public"."v_products_with_stats" TO "authenticated";
GRANT ALL ON TABLE "public"."v_products_with_stats" TO "service_role";



GRANT ALL ON TABLE "public"."v_sales_priority_dashboard" TO "anon";
GRANT ALL ON TABLE "public"."v_sales_priority_dashboard" TO "authenticated";
GRANT ALL ON TABLE "public"."v_sales_priority_dashboard" TO "service_role";



GRANT ALL ON TABLE "public"."v_super_parents_summary" TO "anon";
GRANT ALL ON TABLE "public"."v_super_parents_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."v_super_parents_summary" TO "service_role";



GRANT ALL ON TABLE "public"."workflow_executions" TO "anon";
GRANT ALL ON TABLE "public"."workflow_executions" TO "authenticated";
GRANT ALL ON TABLE "public"."workflow_executions" TO "service_role";



GRANT ALL ON TABLE "public"."workflows" TO "anon";
GRANT ALL ON TABLE "public"."workflows" TO "authenticated";
GRANT ALL ON TABLE "public"."workflows" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







