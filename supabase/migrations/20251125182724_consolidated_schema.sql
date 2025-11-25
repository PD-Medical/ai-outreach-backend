-- ============================================================================
-- CONSOLIDATED SCHEMA MIGRATION
-- ============================================================================
-- Generated: 2025-11-25
-- 
-- This migration consolidates all previous migrations into a single file.
-- Tables: 25 | Views: 6
-- 
-- Seed data is in supabase/seed.sql (loaded by supabase db reset)
-- ============================================================================

--
-- PostgreSQL database dump
--

\restrict 1GKsagdZzdzFdDlSHmXeUa31FoKKTuwVjoWk31bGYul4VwcyK9ZvF8j9tDQdhdE


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: event_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.event_type AS ENUM (
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


--
-- Name: role_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.role_type AS ENUM (
    'admin',
    'sales',
    'accounts',
    'management'
);


--
-- Name: add_timestamp_trigger(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_timestamp_trigger(target_table text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    has_column BOOLEAN;
BEGIN
    -- Validate table exists
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = target_table
    ) THEN
        RAISE EXCEPTION 'Table % does not exist in public schema', target_table;
    END IF;

    -- Check if table has updated_at column
    SELECT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = target_table
          AND column_name = 'updated_at'
          AND data_type LIKE 'timestamp%'
    ) INTO has_column;

    IF NOT has_column THEN
        RAISE EXCEPTION 'Table % does not have an updated_at column', target_table;
    END IF;

    -- Drop existing trigger if exists
    EXECUTE format('DROP TRIGGER IF EXISTS set_updated_at ON public.%I', target_table);

    -- Create the trigger
    EXECUTE format(
        'CREATE TRIGGER set_updated_at
         BEFORE UPDATE ON public.%I
         FOR EACH ROW
         EXECUTE FUNCTION update_updated_at_column()',
        target_table
    );

    RAISE NOTICE ' Added timestamp trigger to table: %', target_table;
END;
$$;


--
-- Name: admin_update_user_role(uuid, public.role_type); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_update_user_role(p_profile_id uuid, new_role public.role_type) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    IF NOT has_permission('manage_users') THEN
        RETURN json_build_object('success', false, 'error', 'Unauthorized');
    END IF;
    UPDATE profiles
    SET role = new_role, updated_at = NOW()
    WHERE profile_id = p_profile_id;
    RETURN json_build_object('success', true);
END;
$$;


--
-- Name: auto_add_timestamp_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auto_add_timestamp_trigger() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
    obj RECORD;
    has_updated_at BOOLEAN;
    schema_name TEXT;
    table_name TEXT;
BEGIN
    -- Loop through all DDL command results
    FOR obj IN SELECT * FROM pg_event_trigger_ddl_commands()
    LOOP
        -- Only process tables in public schema
        IF obj.object_type = 'table' AND obj.schema_name = 'public' THEN

            schema_name := obj.schema_name;
            table_name := (regexp_match(obj.object_identity, '([^.]+)$'))[1];

            -- Check if this table has updated_at column
            SELECT EXISTS (
                SELECT 1
                FROM information_schema.columns
                WHERE table_schema = schema_name
                  AND columns.table_name = auto_add_timestamp_trigger.table_name
                  AND column_name = 'updated_at'
                  AND data_type LIKE 'timestamp%'
            ) INTO has_updated_at;

            -- If table has updated_at, create the trigger
            IF has_updated_at THEN
                -- Drop if exists (for ALTER TABLE case)
                EXECUTE format(
                    'DROP TRIGGER IF EXISTS set_updated_at ON %I.%I',
                    schema_name,
                    table_name
                );

                -- Create the trigger
                EXECUTE format(
                    'CREATE TRIGGER set_updated_at
                     BEFORE UPDATE ON %I.%I
                     FOR EACH ROW
                     EXECUTE FUNCTION update_updated_at_column()',
                    schema_name,
                    table_name
                );

                RAISE NOTICE ' Auto-created timestamp trigger for: %.%', schema_name, table_name;
            END IF;
        END IF;
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN
        -- Log error but don't fail the DDL command
        RAISE WARNING 'Failed to auto-create timestamp trigger: %', SQLERRM;
END;
$_$;


--
-- Name: category_matches_workflow_rules(character varying, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.category_matches_workflow_rules(p_category character varying, p_rules jsonb) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
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


--
-- Name: check_cron_job_exists(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_cron_job_exists(job_name text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
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


--
-- Name: check_mailbox_password_status(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_mailbox_password_status(p_mailbox_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'vault'
    AS $$
DECLARE
    v_secret_name text;
    v_has_password boolean;
    v_mailbox record;
BEGIN
    IF auth.role() IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Authentication required');
    END IF;

    v_secret_name := 'mailbox_password_' || p_mailbox_id::text;

    -- Check if secret exists in Vault
    SELECT EXISTS (SELECT 1 FROM vault.secrets WHERE name = v_secret_name) INTO v_has_password;

    -- Get mailbox info
    SELECT id, email, sync_settings->>'password_updated_at' as password_updated_at
    INTO v_mailbox
    FROM mailboxes
    WHERE id = p_mailbox_id;

    IF v_mailbox.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Mailbox not found');
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'mailbox_id', p_mailbox_id,
        'email', v_mailbox.email,
        'has_password', v_has_password,
        'password_updated_at', v_mailbox.password_updated_at
    );
END;
$$;


--
-- Name: clear_user_permission_override(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.clear_user_permission_override(target_user_id uuid, permission_key text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
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


--
-- Name: current_jwt_role(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_jwt_role() RETURNS text
    LANGUAGE plpgsql STABLE
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


--
-- Name: delete_mailbox_password(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_mailbox_password(p_mailbox_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'vault'
    AS $$
DECLARE
    v_secret_name text;
BEGIN
    -- Check if caller has admin role or is service role
    IF NOT (
        auth.role() = 'service_role' OR
        EXISTS (
            SELECT 1 FROM profiles
            WHERE auth_user_id = auth.uid()
            AND role = 'admin'
        )
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Admin access required');
    END IF;

    v_secret_name := 'mailbox_password_' || p_mailbox_id::text;

    -- Delete from Vault
    DELETE FROM vault.secrets WHERE name = v_secret_name;

    -- Update mailbox
    UPDATE mailboxes
    SET sync_settings = COALESCE(sync_settings, '{}'::jsonb) ||
        jsonb_build_object('password_configured', false),
        updated_at = now()
    WHERE id = p_mailbox_id;

    RETURN jsonb_build_object('success', true, 'mailbox_id', p_mailbox_id);
END;
$$;


--
-- Name: exec_sql(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exec_sql(sql text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
  EXECUTE sql;
END;
$$;


--
-- Name: get_campaign_enrollments_due(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_campaign_enrollments_due() RETURNS TABLE(enrollment_id uuid, campaign_sequence_id uuid, campaign_name character varying, contact_id uuid, contact_email character varying, current_step integer, next_send_date timestamp with time zone)
    LANGUAGE plpgsql STABLE
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


--
-- Name: get_campaign_stats(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_campaign_stats(p_campaign_id uuid) RETURNS TABLE(metric text, campaign_emails integer, workflow_emails integer, total integer, workflow_percentage numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        'Emails Sent'::TEXT,
        (SUM(emails_sent - workflow_emails_sent))::INTEGER,
        (SUM(workflow_emails_sent))::INTEGER,
        (SUM(emails_sent))::INTEGER,
        ROUND(100.0 * SUM(workflow_emails_sent) / NULLIF(SUM(emails_sent), 0), 2)
    FROM campaign_contact_summary
    WHERE campaign_id = p_campaign_id
    
    UNION ALL
    
    SELECT 
        'Emails Opened'::TEXT,
        (SUM(emails_opened - workflow_emails_opened))::INTEGER,
        (SUM(workflow_emails_opened))::INTEGER,
        (SUM(emails_opened))::INTEGER,
        ROUND(100.0 * SUM(workflow_emails_opened) / NULLIF(SUM(emails_opened), 0), 2)
    FROM campaign_contact_summary
    WHERE campaign_id = p_campaign_id
    
    UNION ALL
    
    SELECT 
        'Emails Clicked'::TEXT,
        (SUM(emails_clicked - workflow_emails_clicked))::INTEGER,
        (SUM(workflow_emails_clicked))::INTEGER,
        (SUM(emails_clicked))::INTEGER,
        ROUND(100.0 * SUM(workflow_emails_clicked) / NULLIF(SUM(emails_clicked), 0), 2)
    FROM campaign_contact_summary
    WHERE campaign_id = p_campaign_id;
END;
$$;


--
-- Name: get_category_group(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_category_group(p_category character varying) RETURNS character varying
    LANGUAGE plpgsql STABLE
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


--
-- Name: get_cron_job_runs(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_cron_job_runs(job_name text, limit_count integer DEFAULT 10) RETURNS TABLE(runid bigint, job_pid integer, status text, return_message text, start_time timestamp with time zone, end_time timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
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


--
-- Name: get_cron_job_status(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_cron_job_status(job_name text) RETURNS TABLE(jobid bigint, schedule text, command text, nodename text, nodeport integer, database text, username text, active boolean, jobname text)
    LANGUAGE plpgsql SECURITY DEFINER
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


--
-- Name: get_current_user_role(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_current_user_role() RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
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


--
-- Name: get_db_settings(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_db_settings() RETURNS TABLE(supabase_url text, service_role_key text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    current_setting('app.settings.supabase_url', true),
    current_setting('app.settings.service_role_key', true);
END;
$$;


--
-- Name: get_mailbox_credentials(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_mailbox_credentials(p_mailbox_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_mailbox record;
    v_password text;
BEGIN
    IF auth.role() != 'service_role' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Service role required');
    END IF;

    SELECT * INTO v_mailbox FROM mailboxes WHERE id = p_mailbox_id;

    IF v_mailbox.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Mailbox not found');
    END IF;

    v_password := public.get_mailbox_password(p_mailbox_id);

    RETURN jsonb_build_object(
        'success', true,
        'mailbox_id', v_mailbox.id,
        'email', v_mailbox.email,
        'imap_host', v_mailbox.imap_host,
        'imap_port', v_mailbox.imap_port,
        'imap_username', COALESCE(v_mailbox.imap_username, v_mailbox.email),
        'password', v_password
    );
END;
$$;


--
-- Name: get_mailbox_password(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_mailbox_password(p_mailbox_id uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'vault'
    AS $$
DECLARE
    v_secret_name text;
    v_password text;
BEGIN
    -- Only service role can retrieve passwords
    IF auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized: Service role required';
    END IF;

    v_secret_name := 'mailbox_password_' || p_mailbox_id::text;

    -- Get decrypted password from Vault
    SELECT decrypted_secret INTO v_password
    FROM vault.decrypted_secrets
    WHERE name = v_secret_name;

    RETURN v_password;
END;
$$;


--
-- Name: get_profile_by_auth_user_id(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_profile_by_auth_user_id(user_id uuid) RETURNS TABLE(id uuid, auth_user_id uuid, full_name text, role public.role_type, created_at timestamp with time zone, updated_at timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.profile_id as id,
        p.auth_user_id,
        p.full_name,
        p.role,
        p.created_at,
        p.updated_at
    FROM profiles p
    WHERE p.auth_user_id = user_id;
END;
$$;


--
-- Name: get_user_effective_permissions(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_user_effective_permissions(target_user_id uuid) RETURNS TABLE(view_users boolean, manage_users boolean, view_contacts boolean, manage_contacts boolean, view_campaigns boolean, manage_campaigns boolean, approve_campaigns boolean, view_analytics boolean, manage_approvals boolean, view_workflows boolean, view_emails boolean, has_overrides boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
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


--
-- Name: get_workflows_for_category(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_workflows_for_category(p_category character varying) RETURNS TABLE(workflow_id uuid, workflow_name character varying, priority integer)
    LANGUAGE plpgsql STABLE
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


--
-- Name: handle_email_drafts_approval(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_email_drafts_approval() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Only react when approval_status actually changes to an approved state
  IF TG_OP = 'UPDATE'
     AND NEW.approval_status IS DISTINCT FROM OLD.approval_status
     AND NEW.approval_status IN ('approved', 'auto_approved') THEN

    -- Set approved_at if not already set
    IF NEW.approved_at IS NULL THEN
      NEW.approved_at := now();
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: handle_mailbox_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_mailbox_delete() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'vault'
    AS $$
BEGIN
    -- Delete the associated vault secret
    DELETE FROM vault.secrets
    WHERE name = 'mailbox_password_' || OLD.id::text;
    RETURN OLD;
END;
$$;


--
-- Name: handle_profiles_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_profiles_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;


--
-- Name: handle_user_permissions_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_user_permissions_updated_at() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
  PERFORM set_config('search_path','public,pg_temp',true);
  NEW.updated_at = TIMEZONE('utc'::text, NOW());
  RETURN NEW;
END;
$$;


--
-- Name: has_permission(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.has_permission(permission_name text) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
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


--
-- Name: is_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_admin() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
BEGIN
  PERFORM set_config('search_path', 'public,pg_temp', true);
  
  RETURN COALESCE(
    (SELECT role = 'admin' FROM profiles WHERE auth_user_id = auth.uid() LIMIT 1),
    FALSE
  );
END;
$$;


--
-- Name: is_valid_email_category(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_valid_email_category(p_category character varying) RETURNS boolean
    LANGUAGE plpgsql STABLE
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


--
-- Name: is_valid_email_intent(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_valid_email_intent(p_intent character varying) RETURNS boolean
    LANGUAGE plpgsql STABLE
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


--
-- Name: is_valid_email_sentiment(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_valid_email_sentiment(p_sentiment character varying) RETURNS boolean
    LANGUAGE plpgsql STABLE
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


--
-- Name: is_valid_permission(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_valid_permission(p text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT p IN (
    'view_users', 'manage_users', 'view_contacts', 'manage_contacts',
    'view_campaigns', 'manage_campaigns', 'approve_campaigns',
    'view_analytics', 'manage_approvals', 'view_workflows', 'view_emails'
  )
$$;


--
-- Name: log_user_activity(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_user_activity() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
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


--
-- Name: prevent_manual_user_override(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_manual_user_override() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
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


--
-- Name: prevent_role_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_role_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if current_user <> 'service_role' and new.role <> old.role then
    raise exception 'Role changes require service role privileges';
  end if;
  return new;
end;
$$;


--
-- Name: remove_user_permission_overrides(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.remove_user_permission_overrides(target_user_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
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


--
-- Name: set_approved_by(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_approved_by() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
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


--
-- Name: set_auth_user_tracking(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_auth_user_tracking() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
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


--
-- Name: set_created_by(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_created_by() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
  -- auth.uid() gets the actual logged-in user from JWT token
  -- No way to fake this!
  NEW.created_by = auth.uid();
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


--
-- Name: set_user_permission_override(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_user_permission_override(target_user_id uuid, permission_updates jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
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


--
-- Name: store_mailbox_password(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.store_mailbox_password(p_mailbox_id uuid, p_password text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'vault'
    AS $$
DECLARE
    v_secret_name text;
    v_existing_id uuid;
BEGIN
    -- Check if caller has admin role or is service role
    IF NOT (
        auth.role() = 'service_role' OR
        EXISTS (
            SELECT 1 FROM profiles
            WHERE auth_user_id = auth.uid()
            AND role = 'admin'
        )
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Admin access required');
    END IF;

    -- Verify mailbox exists
    IF NOT EXISTS (SELECT 1 FROM mailboxes WHERE id = p_mailbox_id) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Mailbox not found');
    END IF;

    v_secret_name := 'mailbox_password_' || p_mailbox_id::text;

    -- Check if secret already exists
    SELECT id INTO v_existing_id FROM vault.secrets WHERE name = v_secret_name;

    IF v_existing_id IS NOT NULL THEN
        -- Update existing secret
        PERFORM vault.update_secret(
            v_existing_id,
            p_password,
            v_secret_name,
            'IMAP password for mailbox ' || p_mailbox_id::text
        );
    ELSE
        -- Create new secret
        PERFORM vault.create_secret(
            p_password,
            v_secret_name,
            'IMAP password for mailbox ' || p_mailbox_id::text
        );
    END IF;

    -- Update mailbox to indicate password is configured
    UPDATE mailboxes
    SET sync_settings = COALESCE(sync_settings, '{}'::jsonb) ||
        jsonb_build_object('password_configured', true, 'password_updated_at', now()::text),
        updated_at = now()
    WHERE id = p_mailbox_id;

    RETURN jsonb_build_object(
        'success', true,
        'mailbox_id', p_mailbox_id
    );
END;
$$;


--
-- Name: touch_role_permissions_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.touch_role_permissions_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;


--
-- Name: trigger_workflow_matching(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trigger_workflow_matching() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  lambda_url TEXT;
BEGIN
  -- Skip if category hasn't changed (for UPDATEs) - prevents duplicate triggers
  IF TG_OP = 'UPDATE' AND OLD.email_category IS NOT DISTINCT FROM NEW.email_category THEN
    RETURN NEW;
  END IF;

  -- Skip if workflow matching has already been triggered for this email
  IF NEW.workflow_matched_at IS NOT NULL THEN
    RAISE NOTICE 'Workflow matching already triggered for email %, skipping', NEW.id;
    RETURN NEW;
  END IF;

  -- Get Lambda URL from system_config table
  SELECT value #>> '{}' INTO lambda_url
  FROM system_config
  WHERE key = 'workflow_matcher_url';

  -- Skip if no URL configured
  IF lambda_url IS NULL OR lambda_url = '' THEN
    RAISE NOTICE 'Workflow matcher URL not configured, skipping for email %', NEW.id;
    RETURN NEW;
  END IF;

  -- Only trigger for business emails
  IF NEW.direction = 'outgoing' THEN
    RAISE NOTICE 'Skipping workflow matcher for outgoing email %', NEW.id;
    RETURN NEW;
  END IF;

  IF NEW.email_category IS NULL OR NOT NEW.email_category LIKE 'business-%' THEN
    RAISE NOTICE 'Skipping workflow matcher for non-business email % (category: %)', NEW.id, NEW.email_category;
    RETURN NEW;
  END IF;

  IF NEW.email_category = 'business-transactional' THEN
    RAISE NOTICE 'Skipping workflow matcher for transactional email %', NEW.id;
    RETURN NEW;
  END IF;

  -- Mark that workflow matching has been triggered (prevents duplicate triggers)
  NEW.workflow_matched_at := NOW();

  -- Trigger Lambda asynchronously using pg_net
  BEGIN
    PERFORM net.http_post(
      url := lambda_url,
      headers := '{"Content-Type": "application/json"}'::jsonb,
      body := json_build_object('email_id', NEW.id)::jsonb,
      timeout_milliseconds := 30000
    );

    RAISE NOTICE 'Triggered workflow matcher for email %', NEW.id;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Failed to trigger workflow matcher for %: %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;


--
-- Name: update_contact_lead_score_from_interest(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_contact_lead_score_from_interest() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE public.contacts
    SET lead_score = LEAST(100, GREATEST(0, lead_score + COALESCE(NEW.lead_score_contribution, 0)))
    WHERE id = NEW.contact_id;
    RETURN NEW;
END;
$$;


--
-- Name: update_conversation_stats(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_conversation_stats(p_conversation_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
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


--
-- Name: update_email_drafts_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_email_drafts_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


--
-- Name: update_lead_classification(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_lead_classification() RETURNS trigger
    LANGUAGE plpgsql
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


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: upsert_mailbox(uuid, text, text, text, text, integer, text, text, boolean, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.upsert_mailbox(p_id uuid DEFAULT NULL::uuid, p_email text DEFAULT NULL::text, p_name text DEFAULT NULL::text, p_type text DEFAULT 'personal'::text, p_imap_host text DEFAULT 'mail.pdmedical.com.au'::text, p_imap_port integer DEFAULT 993, p_imap_username text DEFAULT NULL::text, p_password text DEFAULT NULL::text, p_is_active boolean DEFAULT true, p_persona_description text DEFAULT NULL::text, p_signature_html text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_mailbox_id uuid;
    v_is_new boolean := false;
    v_result jsonb;
BEGIN
    -- Check admin permission
    IF NOT (
        auth.role() = 'service_role' OR
        EXISTS (
            SELECT 1 FROM profiles
            WHERE auth_user_id = auth.uid()
            AND role = 'admin'
        )
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Admin access required');
    END IF;

    -- Validate required fields for new mailbox
    IF p_id IS NULL AND (p_email IS NULL OR p_name IS NULL) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Email and name are required for new mailbox');
    END IF;

    -- Check for duplicate email
    IF p_email IS NOT NULL AND EXISTS (
        SELECT 1 FROM mailboxes WHERE email = p_email AND (p_id IS NULL OR id != p_id)
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'A mailbox with this email already exists');
    END IF;

    IF p_id IS NOT NULL THEN
        -- Update existing
        UPDATE mailboxes SET
            email = COALESCE(p_email, email),
            name = COALESCE(p_name, name),
            type = COALESCE(p_type, type),
            imap_host = COALESCE(p_imap_host, imap_host),
            imap_port = COALESCE(p_imap_port, imap_port),
            imap_username = COALESCE(p_imap_username, imap_username),
            is_active = COALESCE(p_is_active, is_active),
            persona_description = COALESCE(p_persona_description, persona_description),
            signature_html = COALESCE(p_signature_html, signature_html),
            updated_at = now()
        WHERE id = p_id
        RETURNING id INTO v_mailbox_id;

        IF v_mailbox_id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'error', 'Mailbox not found');
        END IF;
    ELSE
        -- Create new
        INSERT INTO mailboxes (email, name, type, imap_host, imap_port, imap_username, is_active, persona_description, signature_html)
        VALUES (p_email, p_name, p_type, p_imap_host, p_imap_port, p_imap_username, p_is_active, p_persona_description, p_signature_html)
        RETURNING id INTO v_mailbox_id;
        v_is_new := true;
    END IF;

    -- Store password if provided
    IF p_password IS NOT NULL AND p_password != '' THEN
        PERFORM public.store_mailbox_password(v_mailbox_id, p_password);
    END IF;

    SELECT jsonb_build_object(
        'success', true,
        'action', CASE WHEN v_is_new THEN 'created' ELSE 'updated' END,
        'mailbox', row_to_json(m)::jsonb
    ) INTO v_result
    FROM mailboxes m WHERE m.id = v_mailbox_id;

    RETURN v_result;
END;
$$;


SET default_table_access_method = heap;

--
-- Name: action_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.action_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title character varying(500) NOT NULL,
    description text,
    contact_id uuid NOT NULL,
    email_id uuid,
    workflow_execution_id uuid,
    action_type character varying(50),
    priority character varying(20) DEFAULT 'medium'::character varying,
    status character varying(20) DEFAULT 'open'::character varying,
    due_date timestamp with time zone,
    assigned_to uuid,
    completed_at timestamp with time zone,
    completed_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT action_items_action_type_check CHECK (((action_type)::text = ANY (ARRAY[('follow_up'::character varying)::text, ('call'::character varying)::text, ('meeting'::character varying)::text, ('review'::character varying)::text, ('other'::character varying)::text]))),
    CONSTRAINT action_items_priority_check CHECK (((priority)::text = ANY (ARRAY[('low'::character varying)::text, ('medium'::character varying)::text, ('high'::character varying)::text, ('urgent'::character varying)::text]))),
    CONSTRAINT action_items_status_check CHECK (((status)::text = ANY (ARRAY[('open'::character varying)::text, ('in_progress'::character varying)::text, ('completed'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: ai_enrichment_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_enrichment_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    operation_type character varying NOT NULL,
    model_used character varying NOT NULL,
    items_processed integer NOT NULL,
    tokens_input integer,
    tokens_output integer,
    estimated_cost_usd numeric(10,6),
    processing_time_ms integer,
    success_count integer,
    error_count integer,
    average_confidence numeric(3,2),
    created_at timestamp with time zone DEFAULT now(),
    prompt_text text,
    response_text text,
    error_message text,
    email_ids uuid[],
    contact_ids uuid[]
);


--
-- Name: approval_queue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_queue (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workflow_execution_id uuid NOT NULL,
    action_index integer NOT NULL,
    action_tool character varying(100) NOT NULL,
    action_params_resolved jsonb NOT NULL,
    workflow_name character varying(255) NOT NULL,
    email_subject character varying(500),
    contact_email character varying(255),
    extraction_confidence double precision,
    reason text,
    status character varying(50) DEFAULT 'pending'::character varying,
    decided_by uuid,
    decided_at timestamp with time zone,
    modified_params jsonb,
    rejection_reason text,
    created_at timestamp with time zone DEFAULT now(),
    draft_id uuid,
    langgraph_thread_id character varying,
    CONSTRAINT approval_queue_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('approved'::character varying)::text, ('rejected'::character varying)::text, ('modified'::character varying)::text])))
);


--
-- Name: campaign_contact_summary; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.campaign_contact_summary (
    campaign_id uuid NOT NULL,
    contact_id uuid NOT NULL,
    email text NOT NULL,
    total_score integer DEFAULT 0 NOT NULL,
    opened boolean DEFAULT false NOT NULL,
    clicked boolean DEFAULT false NOT NULL,
    converted boolean DEFAULT false NOT NULL,
    first_event_at timestamp with time zone,
    last_event_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    emails_sent integer DEFAULT 0 NOT NULL,
    emails_delivered integer DEFAULT 0 NOT NULL,
    emails_opened integer DEFAULT 0 NOT NULL,
    emails_clicked integer DEFAULT 0 NOT NULL,
    emails_bounced integer DEFAULT 0 NOT NULL,
    emails_replied integer DEFAULT 0 NOT NULL,
    unique_clicks integer DEFAULT 0 NOT NULL,
    first_opened_at timestamp with time zone,
    first_clicked_at timestamp with time zone,
    first_replied_at timestamp with time zone,
    last_opened_at timestamp with time zone,
    last_clicked_at timestamp with time zone,
    workflow_emails_sent integer DEFAULT 0 NOT NULL,
    workflow_emails_opened integer DEFAULT 0 NOT NULL,
    workflow_emails_clicked integer DEFAULT 0 NOT NULL
);


--
-- Name: campaign_enrollments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.campaign_enrollments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    campaign_sequence_id uuid NOT NULL,
    contact_id uuid NOT NULL,
    current_step integer DEFAULT 1,
    next_send_date timestamp with time zone,
    status character varying(50) DEFAULT 'enrolled'::character varying,
    steps_completed jsonb DEFAULT '[]'::jsonb,
    total_opens integer DEFAULT 0,
    total_clicks integer DEFAULT 0,
    replied boolean DEFAULT false,
    enrolled_at timestamp with time zone DEFAULT now(),
    completed_at timestamp with time zone,
    CONSTRAINT campaign_enrollments_status_check CHECK (((status)::text = ANY (ARRAY[('enrolled'::character varying)::text, ('active'::character varying)::text, ('completed'::character varying)::text, ('unsubscribed'::character varying)::text, ('bounced'::character varying)::text, ('paused'::character varying)::text])))
);


--
-- Name: campaign_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.campaign_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    campaign_id uuid,
    contact_id uuid NOT NULL,
    email text NOT NULL,
    event_type public.event_type NOT NULL,
    event_timestamp timestamp with time zone DEFAULT now() NOT NULL,
    score integer DEFAULT 0 NOT NULL,
    source jsonb DEFAULT '{}'::jsonb NOT NULL,
    external_id text,
    inserted_at timestamp with time zone DEFAULT now() NOT NULL,
    campaign_enrollment_id uuid,
    workflow_execution_id uuid,
    draft_id uuid
);


--
-- Name: campaigns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.campaigns (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    subject text,
    provider text,
    external_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    scheduled_at timestamp with time zone,
    sent_at timestamp with time zone,
    product_id uuid,
    auth_user_id uuid,
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: campaign_performance_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.campaign_performance_summary AS
 SELECT c.id AS campaign_id,
    c.name AS campaign_name,
    c.external_id,
    count(DISTINCT ccs.contact_id) AS contacts_enrolled,
    sum(ccs.emails_sent) AS total_emails_sent,
    sum((ccs.emails_sent - ccs.workflow_emails_sent)) AS campaign_emails_sent,
    sum(ccs.workflow_emails_sent) AS workflow_emails_sent,
    sum(ccs.emails_opened) AS total_opens,
    sum(ccs.emails_clicked) AS total_clicks,
    count(DISTINCT
        CASE
            WHEN ccs.opened THEN ccs.contact_id
            ELSE NULL::uuid
        END) AS contacts_opened,
    count(DISTINCT
        CASE
            WHEN ccs.clicked THEN ccs.contact_id
            ELSE NULL::uuid
        END) AS contacts_clicked,
    count(DISTINCT
        CASE
            WHEN ccs.converted THEN ccs.contact_id
            ELSE NULL::uuid
        END) AS contacts_converted,
    round(((100.0 * (sum(ccs.emails_opened))::numeric) / (NULLIF(sum(ccs.emails_sent), 0))::numeric), 2) AS open_rate,
    round(((100.0 * (sum(ccs.emails_clicked))::numeric) / (NULLIF(sum(ccs.emails_sent), 0))::numeric), 2) AS click_rate,
    round(((100.0 * (count(DISTINCT
        CASE
            WHEN ccs.converted THEN ccs.contact_id
            ELSE NULL::uuid
        END))::numeric) / (NULLIF(count(DISTINCT ccs.contact_id), 0))::numeric), 2) AS conversion_rate,
    c.created_at,
    c.sent_at
   FROM (public.campaigns c
     LEFT JOIN public.campaign_contact_summary ccs ON ((ccs.campaign_id = c.id)))
  GROUP BY c.id, c.name, c.external_id, c.created_at, c.sent_at;


--
-- Name: campaign_sequences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.campaign_sequences (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    target_sql text NOT NULL,
    target_count integer,
    target_preview jsonb,
    steps jsonb NOT NULL,
    from_mailbox_id uuid,
    send_time_preference character varying(50),
    product_id uuid,
    scheduled_at timestamp with time zone,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    status character varying(50) DEFAULT 'draft'::character varying,
    stats jsonb DEFAULT '{}'::jsonb,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT campaign_sequences_status_check CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('scheduled'::character varying)::text, ('running'::character varying)::text, ('completed'::character varying)::text, ('paused'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: contact_product_interests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_product_interests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    contact_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    product_id uuid NOT NULL,
    interest_level character varying(50) DEFAULT 'medium'::character varying,
    status character varying(50) DEFAULT 'prospecting'::character varying,
    source character varying(50) DEFAULT 'excel_import'::character varying,
    campaign_id uuid,
    first_interaction_date date DEFAULT CURRENT_DATE,
    last_interaction_date date DEFAULT CURRENT_DATE,
    quoted_price numeric(12,2),
    quoted_quantity integer,
    quote_date date,
    next_followup_date date,
    expected_close_date date,
    probability_percentage numeric(5,2),
    lead_score_contribution integer DEFAULT 0,
    notes text,
    lost_reason text,
    competitor_chosen character varying(255),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    auth_user_id uuid,
    CONSTRAINT contact_product_interests_interest_level_check CHECK (((interest_level)::text = ANY (ARRAY[('low'::character varying)::text, ('medium'::character varying)::text, ('high'::character varying)::text]))),
    CONSTRAINT contact_product_interests_lead_score_contribution_check CHECK (((lead_score_contribution >= 0) AND (lead_score_contribution <= 50))),
    CONSTRAINT contact_product_interests_status_check CHECK (((status)::text = ANY (ARRAY[('prospecting'::character varying)::text, ('quoted'::character varying)::text, ('negotiating'::character varying)::text, ('won'::character varying)::text, ('lost'::character varying)::text])))
);


--
-- Name: contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contacts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email character varying NOT NULL,
    first_name character varying,
    last_name character varying,
    job_title character varying,
    phone character varying,
    organization_id uuid NOT NULL,
    status character varying DEFAULT 'active'::character varying,
    tags jsonb DEFAULT '[]'::jsonb,
    custom_fields jsonb DEFAULT '{}'::jsonb,
    last_contact_date timestamp with time zone,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    enrichment_status character varying DEFAULT 'pending'::character varying,
    enrichment_last_attempted_at timestamp with time zone,
    role character varying,
    department character varying,
    lead_score integer DEFAULT 0,
    lead_classification character varying DEFAULT 'cold'::character varying,
    engagement_level character varying DEFAULT 'new'::character varying,
    auth_user_id uuid,
    CONSTRAINT contacts_lead_score_check CHECK (((lead_score >= 0) AND (lead_score <= 100))),
    CONSTRAINT contacts_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'inactive'::character varying, 'unsubscribed'::character varying, 'bounced'::character varying, 'ooo'::character varying])::text[])))
);


--
-- Name: conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    thread_id character varying NOT NULL,
    subject character varying,
    mailbox_id uuid NOT NULL,
    organization_id uuid,
    primary_contact_id uuid,
    email_count integer DEFAULT 0,
    first_email_at timestamp with time zone,
    last_email_at timestamp with time zone,
    last_email_direction character varying,
    status character varying DEFAULT 'active'::character varying,
    requires_response boolean DEFAULT false,
    tags jsonb DEFAULT '[]'::jsonb,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    summary text,
    action_items text[],
    last_summarized_at timestamp with time zone,
    email_count_at_last_summary integer DEFAULT 0,
    auth_user_id uuid,
    CONSTRAINT conversations_last_email_direction_check CHECK (((last_email_direction)::text = ANY (ARRAY[('incoming'::character varying)::text, ('outgoing'::character varying)::text]))),
    CONSTRAINT conversations_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('closed'::character varying)::text, ('archived'::character varying)::text])))
);


--
-- Name: email_drafts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_drafts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    source_email_id uuid,
    thread_id character varying,
    conversation_id uuid,
    contact_id uuid,
    to_emails text[] NOT NULL,
    cc_emails text[],
    bcc_emails text[],
    from_mailbox_id uuid NOT NULL,
    subject character varying NOT NULL,
    body_html text,
    body_plain text NOT NULL,
    template_id uuid,
    product_ids uuid[],
    context_data jsonb DEFAULT '{}'::jsonb,
    llm_model character varying,
    generation_confidence numeric(3,2),
    approval_status character varying(20) DEFAULT 'pending'::character varying,
    approved_by uuid,
    approved_at timestamp with time zone,
    rejection_reason text,
    langgraph_thread_id character varying,
    workflow_execution_id uuid,
    campaign_enrollment_id uuid,
    sent_email_id uuid,
    sent_at timestamp with time zone,
    version integer DEFAULT 1,
    previous_draft_id uuid,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    scheduled_send_offset_minutes integer,
    scheduled_send_time timestamp with time zone,
    llm_conversation_history jsonb DEFAULT '[]'::jsonb,
    generation_reasoning text,
    gathered_context jsonb DEFAULT '{}'::jsonb,
    request_params jsonb DEFAULT '{}'::jsonb,
    CONSTRAINT email_drafts_approval_status_check CHECK (((approval_status)::text = ANY (ARRAY[('pending'::character varying)::text, ('approved'::character varying)::text, ('rejected'::character varying)::text, ('auto_approved'::character varying)::text, ('sent'::character varying)::text]))),
    CONSTRAINT email_drafts_generation_confidence_check CHECK (((generation_confidence IS NULL) OR ((generation_confidence >= (0)::numeric) AND (generation_confidence <= (1)::numeric))))
);


--
-- Name: email_import_errors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_import_errors (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    mailbox_id uuid NOT NULL,
    imap_folder character varying NOT NULL,
    imap_uid integer NOT NULL,
    message_id character varying,
    error_message text NOT NULL,
    error_type character varying NOT NULL,
    retry_count integer DEFAULT 0,
    last_attempt_at timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now(),
    resolved_at timestamp with time zone,
    CONSTRAINT email_import_errors_error_type_check CHECK (((error_type)::text = ANY (ARRAY[('parse_error'::character varying)::text, ('db_constraint'::character varying)::text, ('network_error'::character varying)::text, ('imap_error'::character varying)::text, ('validation_error'::character varying)::text, ('timeout_error'::character varying)::text, ('unknown_error'::character varying)::text])))
);


--
-- Name: email_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_templates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    subject_template text NOT NULL,
    body_template text NOT NULL,
    llm_instructions text,
    required_variables jsonb DEFAULT '[]'::jsonb,
    category character varying(100),
    tags jsonb DEFAULT '[]'::jsonb,
    is_active boolean DEFAULT true,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: emails; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.emails (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    message_id character varying NOT NULL,
    thread_id character varying NOT NULL,
    conversation_id uuid,
    in_reply_to character varying,
    email_references text,
    subject character varying,
    from_email character varying NOT NULL,
    from_name character varying,
    to_emails text[] NOT NULL,
    cc_emails text[],
    bcc_emails text[],
    body_html text,
    body_plain text,
    mailbox_id uuid NOT NULL,
    contact_id uuid,
    organization_id uuid,
    direction character varying NOT NULL,
    is_seen boolean DEFAULT false,
    is_flagged boolean DEFAULT false,
    is_answered boolean DEFAULT false,
    is_draft boolean DEFAULT false,
    is_deleted boolean DEFAULT false,
    imap_folder character varying NOT NULL,
    imap_uid integer,
    headers jsonb DEFAULT '{}'::jsonb,
    attachments jsonb DEFAULT '[]'::jsonb,
    sent_at timestamp with time zone,
    received_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    needs_parsing boolean DEFAULT false,
    intent character varying,
    email_category character varying,
    sentiment character varying,
    priority_score integer,
    spam_score numeric(3,2),
    ai_processed_at timestamp with time zone,
    ai_model_version character varying,
    ai_confidence_score numeric(3,2),
    auth_user_id uuid,
    workflow_matched_at timestamp with time zone,
    CONSTRAINT emails_ai_confidence_check CHECK (((ai_confidence_score IS NULL) OR ((ai_confidence_score >= (0)::numeric) AND (ai_confidence_score <= (1)::numeric)))),
    CONSTRAINT emails_direction_check CHECK (((direction)::text = ANY (ARRAY[('incoming'::character varying)::text, ('outgoing'::character varying)::text]))),
    CONSTRAINT emails_priority_score_check CHECK (((priority_score IS NULL) OR ((priority_score >= 0) AND (priority_score <= 100)))),
    CONSTRAINT emails_spam_score_check CHECK (((spam_score IS NULL) OR ((spam_score >= (0)::numeric) AND (spam_score <= (1)::numeric))))
);


--
-- Name: mailboxes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mailboxes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email character varying NOT NULL,
    name character varying NOT NULL,
    type character varying,
    imap_host character varying DEFAULT 'mail.pdmedical.com.au'::character varying,
    imap_port integer DEFAULT 993,
    imap_username character varying,
    is_active boolean DEFAULT true,
    last_synced_at timestamp with time zone,
    last_synced_uid jsonb DEFAULT '{}'::jsonb,
    sync_status jsonb DEFAULT '{}'::jsonb,
    sync_settings jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    persona_description text,
    signature_html text,
    CONSTRAINT mailboxes_type_check CHECK (((type)::text = ANY (ARRAY[('personal'::character varying)::text, ('team'::character varying)::text, ('department'::character varying)::text])))
);


--
-- Name: organization_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    description text,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    domain character varying NOT NULL,
    phone character varying,
    address text,
    industry character varying,
    website character varying,
    status character varying DEFAULT 'active'::character varying,
    tags jsonb DEFAULT '[]'::jsonb,
    custom_fields jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    organization_type_id uuid,
    region character varying,
    hospital_category character varying,
    city character varying,
    state character varying,
    key_hospital character varying,
    street_address character varying,
    suburb character varying,
    facility_type character varying,
    bed_count integer,
    top_150_ranking integer,
    general_info text,
    products_sold text[],
    has_maternity boolean DEFAULT false,
    has_operating_theatre boolean DEFAULT false,
    typical_job_roles text[],
    contact_count integer DEFAULT 0,
    enriched_from_signatures_at timestamp with time zone,
    auth_user_id uuid
);


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    product_code character varying(100) NOT NULL,
    product_name character varying(500) NOT NULL,
    main_category character varying(100) NOT NULL,
    subcategory character varying(200) NOT NULL,
    industry_category character varying(100) NOT NULL,
    unit_price numeric(10,2),
    hsv_price numeric(10,2),
    qty_per_box integer DEFAULT 1,
    moq integer DEFAULT 1,
    currency character varying(10) DEFAULT 'AUD'::character varying,
    sales_priority integer,
    sales_priority_label character varying(50),
    market_potential text,
    background_history text,
    key_contacts_reference text,
    forecast_notes text,
    sales_instructions text,
    sales_timing_notes text,
    sales_status character varying(50) DEFAULT 'active'::character varying,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    auth_user_id uuid NOT NULL,
    full_name text NOT NULL,
    role public.role_type DEFAULT 'sales'::public.role_type NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    profile_id uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: profiles_with_email; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.profiles_with_email AS
 SELECT p.profile_id,
    p.auth_user_id,
    p.full_name,
    p.role,
    p.created_at,
    p.updated_at,
    u.email
   FROM (public.profiles p
     JOIN auth.users u ON ((u.id = p.auth_user_id)));


--
-- Name: role_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_permissions (
    role public.role_type NOT NULL,
    view_users boolean DEFAULT false NOT NULL,
    manage_users boolean DEFAULT false NOT NULL,
    view_contacts boolean DEFAULT false NOT NULL,
    manage_contacts boolean DEFAULT false NOT NULL,
    view_campaigns boolean DEFAULT false NOT NULL,
    manage_campaigns boolean DEFAULT false NOT NULL,
    approve_campaigns boolean DEFAULT false NOT NULL,
    view_analytics boolean DEFAULT false NOT NULL,
    manage_approvals boolean DEFAULT false NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    view_workflows boolean DEFAULT true NOT NULL,
    view_emails boolean DEFAULT true NOT NULL
);


--
-- Name: system_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_config (
    key character varying NOT NULL,
    value jsonb NOT NULL,
    description text,
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: user_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_permissions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    auth_user_id uuid NOT NULL,
    view_users boolean,
    manage_users boolean,
    view_contacts boolean,
    manage_contacts boolean,
    view_campaigns boolean,
    manage_campaigns boolean,
    approve_campaigns boolean,
    view_analytics boolean,
    manage_approvals boolean,
    view_workflows boolean,
    view_emails boolean,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    created_by uuid
);


--
-- Name: v_campaign_enrollments_due; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_campaign_enrollments_due AS
 SELECT ce.id AS enrollment_id,
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


--
-- Name: v_enrichment_config; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_enrichment_config AS
 SELECT 'valid_categories'::text AS config_type,
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


--
-- Name: v_enrichment_stats; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_enrichment_stats AS
 SELECT 'emails'::text AS table_name,
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


--
-- Name: workflow_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflow_executions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workflow_id uuid NOT NULL,
    email_id uuid NOT NULL,
    status character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    extracted_data jsonb,
    extraction_confidence double precision,
    actions_completed jsonb DEFAULT '[]'::jsonb,
    actions_failed jsonb DEFAULT '[]'::jsonb,
    pending_action_index integer,
    started_at timestamp with time zone DEFAULT now(),
    completed_at timestamp with time zone,
    contact_id uuid NOT NULL,
    campaign_enrollment_id uuid,
    CONSTRAINT workflow_executions_extraction_confidence_check CHECK (((extraction_confidence >= (0)::double precision) AND (extraction_confidence <= (1)::double precision))),
    CONSTRAINT workflow_executions_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('extracting'::character varying)::text, ('executing'::character varying)::text, ('awaiting_approval'::character varying)::text, ('completed'::character varying)::text, ('failed'::character varying)::text])))
);


--
-- Name: workflows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflows (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    trigger_condition text NOT NULL,
    priority integer DEFAULT 100,
    extract_fields jsonb DEFAULT '[]'::jsonb NOT NULL,
    actions jsonb DEFAULT '[]'::jsonb NOT NULL,
    lead_score_rules jsonb DEFAULT '[]'::jsonb NOT NULL,
    category_rules jsonb DEFAULT '{"enabled_pattern": "business-*", "disabled_categories": ["business-transactional"]}'::jsonb,
    is_active boolean DEFAULT true,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: workflow_effectiveness_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.workflow_effectiveness_summary AS
 SELECT w.id AS workflow_id,
    w.name AS workflow_name,
    w.trigger_condition,
    w.is_active,
    count(DISTINCT we.id) AS total_executions,
    count(DISTINCT we.id) FILTER (WHERE ((we.status)::text = 'completed'::text)) AS completed_executions,
    count(DISTINCT we.id) FILTER (WHERE ((we.status)::text = 'failed'::text)) AS failed_executions,
    count(DISTINCT ce.id) FILTER (WHERE (ce.event_type = 'sent'::public.event_type)) AS emails_sent,
    count(DISTINCT ce.id) FILTER (WHERE (ce.event_type = 'opened'::public.event_type)) AS emails_opened,
    count(DISTINCT ce.id) FILTER (WHERE (ce.event_type = 'clicked'::public.event_type)) AS emails_clicked,
    count(DISTINCT we.contact_id) AS unique_contacts,
    round(((100.0 * (count(DISTINCT ce.id) FILTER (WHERE (ce.event_type = 'opened'::public.event_type)))::numeric) / (NULLIF(count(DISTINCT ce.id) FILTER (WHERE (ce.event_type = 'sent'::public.event_type)), 0))::numeric), 2) AS open_rate,
    round(((100.0 * (count(DISTINCT ce.id) FILTER (WHERE (ce.event_type = 'clicked'::public.event_type)))::numeric) / (NULLIF(count(DISTINCT ce.id) FILTER (WHERE (ce.event_type = 'sent'::public.event_type)), 0))::numeric), 2) AS click_rate,
    max(we.started_at) AS last_execution_at
   FROM ((public.workflows w
     LEFT JOIN public.workflow_executions we ON ((we.workflow_id = w.id)))
     LEFT JOIN public.campaign_events ce ON ((ce.workflow_execution_id = we.id)))
  GROUP BY w.id, w.name, w.trigger_condition, w.is_active;


--
-- Name: action_items action_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.action_items
    ADD CONSTRAINT action_items_pkey PRIMARY KEY (id);


--
-- Name: ai_enrichment_logs ai_enrichment_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_enrichment_logs
    ADD CONSTRAINT ai_enrichment_logs_pkey PRIMARY KEY (id);


--
-- Name: approval_queue approval_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_queue
    ADD CONSTRAINT approval_queue_pkey PRIMARY KEY (id);


--
-- Name: campaign_contact_summary campaign_contact_summary_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_contact_summary
    ADD CONSTRAINT campaign_contact_summary_pkey PRIMARY KEY (campaign_id, contact_id);


--
-- Name: campaign_enrollments campaign_enrollments_campaign_sequence_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_enrollments
    ADD CONSTRAINT campaign_enrollments_campaign_sequence_id_contact_id_key UNIQUE (campaign_sequence_id, contact_id);


--
-- Name: campaign_enrollments campaign_enrollments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_enrollments
    ADD CONSTRAINT campaign_enrollments_pkey PRIMARY KEY (id);


--
-- Name: campaign_events campaign_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_events
    ADD CONSTRAINT campaign_events_pkey PRIMARY KEY (id);


--
-- Name: campaign_sequences campaign_sequences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_sequences
    ADD CONSTRAINT campaign_sequences_pkey PRIMARY KEY (id);


--
-- Name: campaigns campaigns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaigns
    ADD CONSTRAINT campaigns_pkey PRIMARY KEY (id);


--
-- Name: contact_product_interests contact_product_interests_contact_id_product_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_product_interests
    ADD CONSTRAINT contact_product_interests_contact_id_product_id_key UNIQUE (contact_id, product_id);


--
-- Name: contact_product_interests contact_product_interests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_product_interests
    ADD CONSTRAINT contact_product_interests_pkey PRIMARY KEY (id);


--
-- Name: contacts contacts_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_email_key UNIQUE (email);


--
-- Name: contacts contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_pkey PRIMARY KEY (id);


--
-- Name: conversations conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);


--
-- Name: conversations conversations_thread_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_thread_id_unique UNIQUE (thread_id);


--
-- Name: organizations customer_organizations_domain_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT customer_organizations_domain_key UNIQUE (domain);


--
-- Name: email_drafts email_drafts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_drafts
    ADD CONSTRAINT email_drafts_pkey PRIMARY KEY (id);


--
-- Name: email_import_errors email_import_errors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_import_errors
    ADD CONSTRAINT email_import_errors_pkey PRIMARY KEY (id);


--
-- Name: email_import_errors email_import_errors_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_import_errors
    ADD CONSTRAINT email_import_errors_unique UNIQUE (mailbox_id, imap_folder, imap_uid);


--
-- Name: email_templates email_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_templates
    ADD CONSTRAINT email_templates_pkey PRIMARY KEY (id);


--
-- Name: emails emails_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emails
    ADD CONSTRAINT emails_pkey PRIMARY KEY (id);


--
-- Name: emails emails_unique_imap; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emails
    ADD CONSTRAINT emails_unique_imap UNIQUE (mailbox_id, imap_folder, imap_uid);


--
-- Name: emails emails_unique_message_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emails
    ADD CONSTRAINT emails_unique_message_id UNIQUE (message_id);


--
-- Name: mailboxes mailboxes_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mailboxes
    ADD CONSTRAINT mailboxes_email_key UNIQUE (email);


--
-- Name: mailboxes mailboxes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mailboxes
    ADD CONSTRAINT mailboxes_pkey PRIMARY KEY (id);


--
-- Name: organization_types organization_types_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_types
    ADD CONSTRAINT organization_types_name_key UNIQUE (name);


--
-- Name: organization_types organization_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_types
    ADD CONSTRAINT organization_types_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: products products_product_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_product_code_key UNIQUE (product_code);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (profile_id);


--
-- Name: role_permissions role_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (role);


--
-- Name: system_config system_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_config
    ADD CONSTRAINT system_config_pkey PRIMARY KEY (key);


--
-- Name: user_permissions user_permissions_auth_user_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permissions
    ADD CONSTRAINT user_permissions_auth_user_unique UNIQUE (auth_user_id);


--
-- Name: user_permissions user_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permissions
    ADD CONSTRAINT user_permissions_pkey PRIMARY KEY (id);


--
-- Name: workflow_executions workflow_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_executions
    ADD CONSTRAINT workflow_executions_pkey PRIMARY KEY (id);


--
-- Name: workflows workflows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflows
    ADD CONSTRAINT workflows_pkey PRIMARY KEY (id);


--
-- Name: idx_action_items_assigned; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_action_items_assigned ON public.action_items USING btree (assigned_to, status);


--
-- Name: idx_action_items_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_action_items_contact ON public.action_items USING btree (contact_id, created_at DESC);


--
-- Name: idx_action_items_status_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_action_items_status_due ON public.action_items USING btree (status, due_date) WHERE ((status)::text = ANY (ARRAY[('open'::character varying)::text, ('in_progress'::character varying)::text]));


--
-- Name: idx_action_items_workflow; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_action_items_workflow ON public.action_items USING btree (workflow_execution_id);


--
-- Name: idx_ai_logs_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_logs_date ON public.ai_enrichment_logs USING btree (created_at DESC);


--
-- Name: idx_ai_logs_has_error; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_logs_has_error ON public.ai_enrichment_logs USING btree (created_at DESC) WHERE (error_message IS NOT NULL);


--
-- Name: idx_ai_logs_operation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_logs_operation ON public.ai_enrichment_logs USING btree (operation_type);


--
-- Name: idx_approval_queue_decided_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_queue_decided_by ON public.approval_queue USING btree (decided_by, decided_at DESC);


--
-- Name: idx_approval_queue_draft; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_queue_draft ON public.approval_queue USING btree (draft_id) WHERE (draft_id IS NOT NULL);


--
-- Name: idx_approval_queue_langgraph; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_queue_langgraph ON public.approval_queue USING btree (langgraph_thread_id) WHERE (langgraph_thread_id IS NOT NULL);


--
-- Name: idx_approval_queue_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_queue_pending ON public.approval_queue USING btree (status, created_at DESC) WHERE ((status)::text = 'pending'::text);


--
-- Name: idx_approval_queue_workflow_execution; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_queue_workflow_execution ON public.approval_queue USING btree (workflow_execution_id);


--
-- Name: idx_campaign_contact_summary_campaign_score; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_contact_summary_campaign_score ON public.campaign_contact_summary USING btree (campaign_id, total_score DESC);


--
-- Name: idx_campaign_contact_summary_clicked; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_contact_summary_clicked ON public.campaign_contact_summary USING btree (campaign_id) WHERE (clicked = true);


--
-- Name: idx_campaign_contact_summary_engagement_times; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_contact_summary_engagement_times ON public.campaign_contact_summary USING btree (campaign_id, first_opened_at) WHERE (first_opened_at IS NOT NULL);


--
-- Name: idx_campaign_contact_summary_opened; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_contact_summary_opened ON public.campaign_contact_summary USING btree (campaign_id) WHERE (opened = true);


--
-- Name: idx_campaign_contact_summary_workflow_sent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_contact_summary_workflow_sent ON public.campaign_contact_summary USING btree (campaign_id) WHERE (workflow_emails_sent > 0);


--
-- Name: idx_campaign_enrollments_campaign; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_enrollments_campaign ON public.campaign_enrollments USING btree (campaign_sequence_id, status);


--
-- Name: idx_campaign_enrollments_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_enrollments_contact ON public.campaign_enrollments USING btree (contact_id);


--
-- Name: idx_campaign_enrollments_next_send; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_enrollments_next_send ON public.campaign_enrollments USING btree (next_send_date) WHERE ((status)::text = 'active'::text);


--
-- Name: idx_campaign_enrollments_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_enrollments_status ON public.campaign_enrollments USING btree (status);


--
-- Name: idx_campaign_events_campaign_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_events_campaign_type ON public.campaign_events USING btree (campaign_id, event_type);


--
-- Name: idx_campaign_events_contact_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_events_contact_timestamp ON public.campaign_events USING btree (contact_id, event_timestamp DESC);


--
-- Name: idx_campaign_events_draft; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_events_draft ON public.campaign_events USING btree (draft_id) WHERE (draft_id IS NOT NULL);


--
-- Name: idx_campaign_events_enrollment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_events_enrollment ON public.campaign_events USING btree (campaign_enrollment_id) WHERE (campaign_enrollment_id IS NOT NULL);


--
-- Name: idx_campaign_events_event_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_events_event_timestamp ON public.campaign_events USING btree (event_timestamp DESC);


--
-- Name: idx_campaign_events_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_campaign_events_external_id ON public.campaign_events USING btree (external_id) WHERE (external_id IS NOT NULL);


--
-- Name: idx_campaign_events_workflow; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_events_workflow ON public.campaign_events USING btree (workflow_execution_id) WHERE (workflow_execution_id IS NOT NULL);


--
-- Name: idx_campaign_events_workflow_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_events_workflow_type ON public.campaign_events USING btree (workflow_execution_id, event_type) WHERE (workflow_execution_id IS NOT NULL);


--
-- Name: idx_campaign_sequences_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_sequences_created_by ON public.campaign_sequences USING btree (created_by);


--
-- Name: idx_campaign_sequences_mailbox; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_sequences_mailbox ON public.campaign_sequences USING btree (from_mailbox_id);


--
-- Name: idx_campaign_sequences_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_sequences_product ON public.campaign_sequences USING btree (product_id) WHERE (product_id IS NOT NULL);


--
-- Name: idx_campaign_sequences_scheduled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_sequences_scheduled ON public.campaign_sequences USING btree (scheduled_at) WHERE ((status)::text = 'scheduled'::text);


--
-- Name: idx_campaign_sequences_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaign_sequences_status ON public.campaign_sequences USING btree (status, created_at DESC);


--
-- Name: idx_campaigns_auth_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaigns_auth_user_id ON public.campaigns USING btree (auth_user_id);


--
-- Name: idx_campaigns_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaigns_product_id ON public.campaigns USING btree (product_id) WHERE (product_id IS NOT NULL);


--
-- Name: idx_campaigns_provider; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaigns_provider ON public.campaigns USING btree (provider);


--
-- Name: idx_campaigns_sent_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaigns_sent_at ON public.campaigns USING btree (sent_at DESC);


--
-- Name: idx_contact_interests_campaign; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contact_interests_campaign ON public.contact_product_interests USING btree (campaign_id) WHERE (campaign_id IS NOT NULL);


--
-- Name: idx_contact_interests_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contact_interests_contact ON public.contact_product_interests USING btree (contact_id);


--
-- Name: idx_contact_interests_followup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contact_interests_followup ON public.contact_product_interests USING btree (next_followup_date) WHERE (next_followup_date IS NOT NULL);


--
-- Name: idx_contact_interests_level; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contact_interests_level ON public.contact_product_interests USING btree (interest_level);


--
-- Name: idx_contact_interests_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contact_interests_org ON public.contact_product_interests USING btree (organization_id);


--
-- Name: idx_contact_interests_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contact_interests_product ON public.contact_product_interests USING btree (product_id);


--
-- Name: idx_contact_interests_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contact_interests_status ON public.contact_product_interests USING btree (status);


--
-- Name: idx_contact_product_interests_auth_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contact_product_interests_auth_user_id ON public.contact_product_interests USING btree (auth_user_id);


--
-- Name: idx_contacts_auth_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contacts_auth_user_id ON public.contacts USING btree (auth_user_id);


--
-- Name: idx_contacts_classification; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contacts_classification ON public.contacts USING btree (lead_classification);


--
-- Name: idx_contacts_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contacts_email ON public.contacts USING btree (email);


--
-- Name: idx_contacts_engagement; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contacts_engagement ON public.contacts USING btree (engagement_level);


--
-- Name: idx_contacts_enrichment_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contacts_enrichment_pending ON public.contacts USING btree (enrichment_status) WHERE ((enrichment_status)::text = 'pending'::text);


--
-- Name: idx_contacts_lead_score; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contacts_lead_score ON public.contacts USING btree (lead_score DESC);


--
-- Name: idx_contacts_name_org_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_contacts_name_org_unique ON public.contacts USING btree (lower(TRIM(BOTH FROM first_name)), lower(TRIM(BOTH FROM last_name)), organization_id) WHERE ((first_name IS NOT NULL) AND (last_name IS NOT NULL) AND (organization_id IS NOT NULL));


--
-- Name: idx_contacts_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contacts_organization_id ON public.contacts USING btree (organization_id);


--
-- Name: idx_contacts_placeholder_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contacts_placeholder_email ON public.contacts USING btree (((custom_fields ->> 'placeholder_email'::text))) WHERE ((custom_fields ->> 'placeholder_email'::text) = 'true'::text);


--
-- Name: idx_conversations_auth_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_conversations_auth_user_id ON public.conversations USING btree (auth_user_id);


--
-- Name: idx_conversations_last_email_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_conversations_last_email_at ON public.conversations USING btree (last_email_at DESC);


--
-- Name: idx_conversations_mailbox_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_conversations_mailbox_id ON public.conversations USING btree (mailbox_id);


--
-- Name: idx_conversations_needs_summary; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_conversations_needs_summary ON public.conversations USING btree (last_summarized_at, email_count) WHERE (email_count > COALESCE(email_count_at_last_summary, 0));


--
-- Name: idx_conversations_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_conversations_organization_id ON public.conversations USING btree (organization_id);


--
-- Name: idx_conversations_primary_contact_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_conversations_primary_contact_id ON public.conversations USING btree (primary_contact_id);


--
-- Name: idx_conversations_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_conversations_status ON public.conversations USING btree (status);


--
-- Name: idx_conversations_thread_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_conversations_thread_id ON public.conversations USING btree (thread_id);


--
-- Name: idx_email_drafts_approval_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_drafts_approval_status ON public.email_drafts USING btree (approval_status, created_at DESC);


--
-- Name: idx_email_drafts_campaign; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_drafts_campaign ON public.email_drafts USING btree (campaign_enrollment_id) WHERE (campaign_enrollment_id IS NOT NULL);


--
-- Name: idx_email_drafts_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_drafts_contact ON public.email_drafts USING btree (contact_id) WHERE (contact_id IS NOT NULL);


--
-- Name: idx_email_drafts_langgraph; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_drafts_langgraph ON public.email_drafts USING btree (langgraph_thread_id) WHERE (langgraph_thread_id IS NOT NULL);


--
-- Name: idx_email_drafts_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_drafts_pending ON public.email_drafts USING btree (approval_status) WHERE ((approval_status)::text = 'pending'::text);


--
-- Name: idx_email_drafts_previous_draft; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_drafts_previous_draft ON public.email_drafts USING btree (previous_draft_id) WHERE (previous_draft_id IS NOT NULL);


--
-- Name: idx_email_drafts_thread; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_drafts_thread ON public.email_drafts USING btree (thread_id) WHERE (thread_id IS NOT NULL);


--
-- Name: idx_email_drafts_workflow; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_drafts_workflow ON public.email_drafts USING btree (workflow_execution_id) WHERE (workflow_execution_id IS NOT NULL);


--
-- Name: idx_email_import_errors_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_import_errors_created_at ON public.email_import_errors USING btree (created_at DESC);


--
-- Name: idx_email_import_errors_mailbox_folder; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_import_errors_mailbox_folder ON public.email_import_errors USING btree (mailbox_id, imap_folder);


--
-- Name: idx_email_import_errors_resolved; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_import_errors_resolved ON public.email_import_errors USING btree (resolved_at) WHERE (resolved_at IS NOT NULL);


--
-- Name: idx_email_import_errors_retry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_import_errors_retry ON public.email_import_errors USING btree (retry_count, last_attempt_at) WHERE (resolved_at IS NULL);


--
-- Name: idx_email_templates_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_templates_active ON public.email_templates USING btree (is_active) WHERE (is_active = true);


--
-- Name: idx_email_templates_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_templates_category ON public.email_templates USING btree (category);


--
-- Name: idx_emails_ai_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emails_ai_pending ON public.emails USING btree (ai_processed_at) WHERE (ai_processed_at IS NULL);


--
-- Name: idx_emails_auth_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emails_auth_user_id ON public.emails USING btree (auth_user_id);


--
-- Name: idx_emails_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emails_category ON public.emails USING btree (email_category) WHERE (email_category IS NOT NULL);


--
-- Name: idx_emails_contact_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emails_contact_id ON public.emails USING btree (contact_id);


--
-- Name: idx_emails_conversation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emails_conversation_id ON public.emails USING btree (conversation_id);


--
-- Name: idx_emails_direction; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emails_direction ON public.emails USING btree (direction);


--
-- Name: idx_emails_from_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emails_from_email ON public.emails USING btree (from_email);


--
-- Name: idx_emails_imap_folder; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emails_imap_folder ON public.emails USING btree (imap_folder);


--
-- Name: idx_emails_intent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emails_intent ON public.emails USING btree (intent) WHERE (intent IS NOT NULL);


--
-- Name: idx_emails_mailbox_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emails_mailbox_id ON public.emails USING btree (mailbox_id);


--
-- Name: idx_emails_message_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emails_message_id ON public.emails USING btree (message_id);


--
-- Name: idx_emails_needs_parsing; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emails_needs_parsing ON public.emails USING btree (needs_parsing) WHERE (needs_parsing = true);


--
-- Name: idx_emails_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emails_organization_id ON public.emails USING btree (organization_id);


--
-- Name: idx_emails_priority; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emails_priority ON public.emails USING btree (priority_score DESC) WHERE (priority_score > 70);


--
-- Name: idx_emails_received_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emails_received_at ON public.emails USING btree (received_at DESC);


--
-- Name: idx_emails_thread_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emails_thread_id ON public.emails USING btree (thread_id);


--
-- Name: idx_mailboxes_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mailboxes_email ON public.mailboxes USING btree (email);


--
-- Name: idx_mailboxes_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mailboxes_is_active ON public.mailboxes USING btree (is_active);


--
-- Name: idx_organizations_auth_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_organizations_auth_user_id ON public.organizations USING btree (auth_user_id);


--
-- Name: idx_organizations_city; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_organizations_city ON public.organizations USING btree (city);


--
-- Name: idx_organizations_city_not_null; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_organizations_city_not_null ON public.organizations USING btree (city) WHERE (city IS NOT NULL);


--
-- Name: idx_organizations_contact_count; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_organizations_contact_count ON public.organizations USING btree (contact_count DESC);


--
-- Name: idx_organizations_domain; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_organizations_domain ON public.organizations USING btree (domain);


--
-- Name: idx_organizations_facility_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_organizations_facility_type ON public.organizations USING btree (facility_type);


--
-- Name: idx_organizations_organization_type_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_organizations_organization_type_id ON public.organizations USING btree (organization_type_id);


--
-- Name: idx_organizations_region_not_null; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_organizations_region_not_null ON public.organizations USING btree (region) WHERE (region IS NOT NULL);


--
-- Name: idx_organizations_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_organizations_state ON public.organizations USING btree (state);


--
-- Name: idx_organizations_state_not_null; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_organizations_state_not_null ON public.organizations USING btree (state) WHERE (state IS NOT NULL);


--
-- Name: idx_products_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_active ON public.products USING btree (is_active);


--
-- Name: idx_products_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_code ON public.products USING btree (product_code);


--
-- Name: idx_products_industry_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_industry_category ON public.products USING btree (industry_category);


--
-- Name: idx_products_main_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_main_category ON public.products USING btree (main_category);


--
-- Name: idx_products_priority; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_priority ON public.products USING btree (sales_priority);


--
-- Name: idx_products_subcategory; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_subcategory ON public.products USING btree (subcategory);


--
-- Name: idx_profiles_auth_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profiles_auth_user_id ON public.profiles USING btree (auth_user_id);


--
-- Name: idx_profiles_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profiles_role ON public.profiles USING btree (role);


--
-- Name: idx_role_permissions_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_role_permissions_role ON public.role_permissions USING btree (role);


--
-- Name: idx_system_config_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_system_config_key ON public.system_config USING btree (key);


--
-- Name: idx_user_permissions_auth_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_permissions_auth_user_id ON public.user_permissions USING btree (auth_user_id);


--
-- Name: idx_workflow_executions_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workflow_executions_contact ON public.workflow_executions USING btree (contact_id, started_at DESC);


--
-- Name: idx_workflow_executions_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workflow_executions_email ON public.workflow_executions USING btree (email_id);


--
-- Name: idx_workflow_executions_enrollment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workflow_executions_enrollment ON public.workflow_executions USING btree (campaign_enrollment_id) WHERE (campaign_enrollment_id IS NOT NULL);


--
-- Name: idx_workflow_executions_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workflow_executions_pending ON public.workflow_executions USING btree (status) WHERE ((status)::text = 'awaiting_approval'::text);


--
-- Name: idx_workflow_executions_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workflow_executions_status ON public.workflow_executions USING btree (status, started_at DESC);


--
-- Name: idx_workflow_executions_workflow; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workflow_executions_workflow ON public.workflow_executions USING btree (workflow_id, started_at DESC);


--
-- Name: idx_workflow_executions_workflow_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workflow_executions_workflow_contact ON public.workflow_executions USING btree (workflow_id, contact_id);


--
-- Name: idx_workflows_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workflows_active ON public.workflows USING btree (is_active) WHERE (is_active = true);


--
-- Name: idx_workflows_active_priority; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workflows_active_priority ON public.workflows USING btree (is_active, priority) WHERE (is_active = true);


--
-- Name: idx_workflows_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workflows_created_by ON public.workflows USING btree (created_by);


--
-- Name: campaigns campaigns_log_activity; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER campaigns_log_activity AFTER INSERT OR UPDATE ON public.campaigns FOR EACH ROW EXECUTE FUNCTION public.log_user_activity();


--
-- Name: campaigns campaigns_set_approved_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER campaigns_set_approved_by BEFORE UPDATE ON public.campaigns FOR EACH ROW EXECUTE FUNCTION public.set_approved_by();


--
-- Name: campaigns campaigns_set_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER campaigns_set_created_by BEFORE INSERT ON public.campaigns FOR EACH ROW EXECUTE FUNCTION public.set_created_by();


--
-- Name: email_drafts email_drafts_approval_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER email_drafts_approval_trigger BEFORE UPDATE ON public.email_drafts FOR EACH ROW EXECUTE FUNCTION public.handle_email_drafts_approval();


--
-- Name: mailboxes on_mailbox_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_mailbox_delete BEFORE DELETE ON public.mailboxes FOR EACH ROW EXECUTE FUNCTION public.handle_mailbox_delete();


--
-- Name: profiles prevent_role_change_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER prevent_role_change_trigger BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.prevent_role_change();


--
-- Name: profiles profiles_set_timestamp; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER profiles_set_timestamp BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.handle_profiles_updated_at();


--
-- Name: role_permissions role_permissions_set_timestamp; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER role_permissions_set_timestamp BEFORE UPDATE ON public.role_permissions FOR EACH ROW EXECUTE FUNCTION public.touch_role_permissions_updated_at();


--
-- Name: action_items set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.action_items FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: campaign_contact_summary set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.campaign_contact_summary FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: campaign_sequences set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.campaign_sequences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: campaigns set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.campaigns FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: contact_product_interests set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.contact_product_interests FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: contacts set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: conversations set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.conversations FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: email_drafts set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.email_drafts FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: email_templates set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.email_templates FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: emails set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.emails FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: mailboxes set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.mailboxes FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: organization_types set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.organization_types FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: organizations set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.organizations FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: profiles set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: role_permissions set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.role_permissions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: system_config set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.system_config FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: user_permissions set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.user_permissions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: email_drafts trigger_email_drafts_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_email_drafts_updated_at BEFORE UPDATE ON public.email_drafts FOR EACH ROW EXECUTE FUNCTION public.update_email_drafts_updated_at();


--
-- Name: emails trigger_match_workflows; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_match_workflows BEFORE INSERT OR UPDATE OF email_category ON public.emails FOR EACH ROW WHEN (((new.email_category IS NOT NULL) AND ((new.email_category)::text ~~ 'business-%'::text))) EXECUTE FUNCTION public.trigger_workflow_matching();


--
-- Name: contacts trigger_update_lead_classification; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_lead_classification BEFORE INSERT OR UPDATE OF lead_score ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.update_lead_classification();


--
-- Name: contact_product_interests trigger_update_lead_score_from_interest; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_lead_score_from_interest AFTER INSERT OR UPDATE OF lead_score_contribution ON public.contact_product_interests FOR EACH ROW EXECUTE FUNCTION public.update_contact_lead_score_from_interest();


--
-- Name: action_items update_action_items_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_action_items_updated_at BEFORE UPDATE ON public.action_items FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: campaign_sequences update_campaign_sequences_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_campaign_sequences_updated_at BEFORE UPDATE ON public.campaign_sequences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: email_templates update_email_templates_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_email_templates_updated_at BEFORE UPDATE ON public.email_templates FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: contact_product_interests update_interests_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_interests_updated_at BEFORE UPDATE ON public.contact_product_interests FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: system_config update_system_config_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_system_config_updated_at BEFORE UPDATE ON public.system_config FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: workflows update_workflows_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_workflows_updated_at BEFORE UPDATE ON public.workflows FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: user_permissions user_permissions_set_timestamp; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER user_permissions_set_timestamp BEFORE UPDATE ON public.user_permissions FOR EACH ROW EXECUTE FUNCTION public.handle_user_permissions_updated_at();


--
-- Name: action_items action_items_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.action_items
    ADD CONSTRAINT action_items_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.profiles(profile_id) ON DELETE SET NULL;


--
-- Name: action_items action_items_completed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.action_items
    ADD CONSTRAINT action_items_completed_by_fkey FOREIGN KEY (completed_by) REFERENCES public.profiles(profile_id) ON DELETE SET NULL;


--
-- Name: action_items action_items_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.action_items
    ADD CONSTRAINT action_items_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: action_items action_items_email_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.action_items
    ADD CONSTRAINT action_items_email_id_fkey FOREIGN KEY (email_id) REFERENCES public.emails(id) ON DELETE SET NULL;


--
-- Name: action_items action_items_workflow_execution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.action_items
    ADD CONSTRAINT action_items_workflow_execution_id_fkey FOREIGN KEY (workflow_execution_id) REFERENCES public.workflow_executions(id) ON DELETE SET NULL;


--
-- Name: approval_queue approval_queue_decided_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_queue
    ADD CONSTRAINT approval_queue_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES public.profiles(profile_id);


--
-- Name: approval_queue approval_queue_draft_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_queue
    ADD CONSTRAINT approval_queue_draft_id_fkey FOREIGN KEY (draft_id) REFERENCES public.email_drafts(id);


--
-- Name: approval_queue approval_queue_workflow_execution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_queue
    ADD CONSTRAINT approval_queue_workflow_execution_id_fkey FOREIGN KEY (workflow_execution_id) REFERENCES public.workflow_executions(id) ON DELETE CASCADE;


--
-- Name: campaign_contact_summary campaign_contact_summary_campaign_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_contact_summary
    ADD CONSTRAINT campaign_contact_summary_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id) ON DELETE CASCADE;


--
-- Name: campaign_contact_summary campaign_contact_summary_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_contact_summary
    ADD CONSTRAINT campaign_contact_summary_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: campaign_enrollments campaign_enrollments_campaign_sequence_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_enrollments
    ADD CONSTRAINT campaign_enrollments_campaign_sequence_id_fkey FOREIGN KEY (campaign_sequence_id) REFERENCES public.campaign_sequences(id) ON DELETE CASCADE;


--
-- Name: campaign_enrollments campaign_enrollments_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_enrollments
    ADD CONSTRAINT campaign_enrollments_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: campaign_events campaign_events_campaign_enrollment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_events
    ADD CONSTRAINT campaign_events_campaign_enrollment_id_fkey FOREIGN KEY (campaign_enrollment_id) REFERENCES public.campaign_enrollments(id) ON DELETE SET NULL;


--
-- Name: campaign_events campaign_events_campaign_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_events
    ADD CONSTRAINT campaign_events_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id) ON DELETE SET NULL;


--
-- Name: campaign_events campaign_events_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_events
    ADD CONSTRAINT campaign_events_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: campaign_events campaign_events_draft_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_events
    ADD CONSTRAINT campaign_events_draft_id_fkey FOREIGN KEY (draft_id) REFERENCES public.email_drafts(id) ON DELETE SET NULL;


--
-- Name: campaign_events campaign_events_workflow_execution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_events
    ADD CONSTRAINT campaign_events_workflow_execution_id_fkey FOREIGN KEY (workflow_execution_id) REFERENCES public.workflow_executions(id) ON DELETE SET NULL;


--
-- Name: campaign_sequences campaign_sequences_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_sequences
    ADD CONSTRAINT campaign_sequences_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(profile_id);


--
-- Name: campaign_sequences campaign_sequences_from_mailbox_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_sequences
    ADD CONSTRAINT campaign_sequences_from_mailbox_id_fkey FOREIGN KEY (from_mailbox_id) REFERENCES public.mailboxes(id);


--
-- Name: campaigns campaigns_auth_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaigns
    ADD CONSTRAINT campaigns_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: contact_product_interests contact_product_interests_auth_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_product_interests
    ADD CONSTRAINT contact_product_interests_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: contact_product_interests contact_product_interests_campaign_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_product_interests
    ADD CONSTRAINT contact_product_interests_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id) ON DELETE SET NULL;


--
-- Name: contact_product_interests contact_product_interests_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_product_interests
    ADD CONSTRAINT contact_product_interests_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: contact_product_interests contact_product_interests_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_product_interests
    ADD CONSTRAINT contact_product_interests_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: contacts contacts_auth_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: contacts contacts_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: conversations conversations_auth_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: conversations conversations_mailbox_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_mailbox_id_fkey FOREIGN KEY (mailbox_id) REFERENCES public.mailboxes(id) ON DELETE CASCADE;


--
-- Name: conversations conversations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE SET NULL;


--
-- Name: conversations conversations_primary_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_primary_contact_id_fkey FOREIGN KEY (primary_contact_id) REFERENCES public.contacts(id) ON DELETE SET NULL;


--
-- Name: email_drafts email_drafts_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_drafts
    ADD CONSTRAINT email_drafts_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.profiles(profile_id);


--
-- Name: email_drafts email_drafts_campaign_enrollment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_drafts
    ADD CONSTRAINT email_drafts_campaign_enrollment_id_fkey FOREIGN KEY (campaign_enrollment_id) REFERENCES public.campaign_enrollments(id);


--
-- Name: email_drafts email_drafts_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_drafts
    ADD CONSTRAINT email_drafts_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id);


--
-- Name: email_drafts email_drafts_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_drafts
    ADD CONSTRAINT email_drafts_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id);


--
-- Name: email_drafts email_drafts_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_drafts
    ADD CONSTRAINT email_drafts_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(profile_id);


--
-- Name: email_drafts email_drafts_from_mailbox_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_drafts
    ADD CONSTRAINT email_drafts_from_mailbox_id_fkey FOREIGN KEY (from_mailbox_id) REFERENCES public.mailboxes(id);


--
-- Name: email_drafts email_drafts_previous_draft_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_drafts
    ADD CONSTRAINT email_drafts_previous_draft_id_fkey FOREIGN KEY (previous_draft_id) REFERENCES public.email_drafts(id);


--
-- Name: email_drafts email_drafts_sent_email_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_drafts
    ADD CONSTRAINT email_drafts_sent_email_id_fkey FOREIGN KEY (sent_email_id) REFERENCES public.emails(id);


--
-- Name: email_drafts email_drafts_source_email_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_drafts
    ADD CONSTRAINT email_drafts_source_email_id_fkey FOREIGN KEY (source_email_id) REFERENCES public.emails(id);


--
-- Name: email_drafts email_drafts_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_drafts
    ADD CONSTRAINT email_drafts_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.email_templates(id);


--
-- Name: email_drafts email_drafts_workflow_execution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_drafts
    ADD CONSTRAINT email_drafts_workflow_execution_id_fkey FOREIGN KEY (workflow_execution_id) REFERENCES public.workflow_executions(id);


--
-- Name: email_import_errors email_import_errors_mailbox_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_import_errors
    ADD CONSTRAINT email_import_errors_mailbox_id_fkey FOREIGN KEY (mailbox_id) REFERENCES public.mailboxes(id) ON DELETE CASCADE;


--
-- Name: email_templates email_templates_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_templates
    ADD CONSTRAINT email_templates_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(profile_id);


--
-- Name: emails emails_auth_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emails
    ADD CONSTRAINT emails_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: emails emails_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emails
    ADD CONSTRAINT emails_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE SET NULL;


--
-- Name: emails emails_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emails
    ADD CONSTRAINT emails_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE;


--
-- Name: emails emails_mailbox_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emails
    ADD CONSTRAINT emails_mailbox_id_fkey FOREIGN KEY (mailbox_id) REFERENCES public.mailboxes(id) ON DELETE CASCADE;


--
-- Name: emails emails_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emails
    ADD CONSTRAINT emails_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE SET NULL;


--
-- Name: organizations organizations_auth_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: organizations organizations_organization_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_organization_type_id_fkey FOREIGN KEY (organization_type_id) REFERENCES public.organization_types(id) ON DELETE SET NULL;


--
-- Name: profiles profiles_auth_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: user_permissions user_permissions_auth_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permissions
    ADD CONSTRAINT user_permissions_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: user_permissions user_permissions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permissions
    ADD CONSTRAINT user_permissions_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);


--
-- Name: workflow_executions workflow_executions_campaign_enrollment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_executions
    ADD CONSTRAINT workflow_executions_campaign_enrollment_id_fkey FOREIGN KEY (campaign_enrollment_id) REFERENCES public.campaign_enrollments(id) ON DELETE SET NULL;


--
-- Name: workflow_executions workflow_executions_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_executions
    ADD CONSTRAINT workflow_executions_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: workflow_executions workflow_executions_email_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_executions
    ADD CONSTRAINT workflow_executions_email_id_fkey FOREIGN KEY (email_id) REFERENCES public.emails(id) ON DELETE CASCADE;


--
-- Name: workflow_executions workflow_executions_workflow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_executions
    ADD CONSTRAINT workflow_executions_workflow_id_fkey FOREIGN KEY (workflow_id) REFERENCES public.workflows(id) ON DELETE CASCADE;


--
-- Name: workflows workflows_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflows
    ADD CONSTRAINT workflows_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(profile_id);


--
-- Name: user_permissions Admins can manage user permissions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can manage user permissions" ON public.user_permissions USING (public.has_permission('manage_users'::text));


--
-- Name: workflow_executions Allow delete workflow_executions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow delete workflow_executions" ON public.workflow_executions FOR DELETE USING (true);


--
-- Name: workflows Allow delete workflows; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow delete workflows" ON public.workflows FOR DELETE USING (true);


--
-- Name: workflow_executions Allow insert workflow_executions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow insert workflow_executions" ON public.workflow_executions FOR INSERT WITH CHECK (true);


--
-- Name: workflows Allow insert workflows; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow insert workflows" ON public.workflows FOR INSERT WITH CHECK (true);


--
-- Name: workflow_executions Allow read workflow_executions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow read workflow_executions" ON public.workflow_executions FOR SELECT USING (true);


--
-- Name: workflows Allow read workflows; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow read workflows" ON public.workflows FOR SELECT USING (true);


--
-- Name: workflow_executions Allow update workflow_executions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow update workflow_executions" ON public.workflow_executions FOR UPDATE USING (true);


--
-- Name: workflows Allow update workflows; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow update workflows" ON public.workflows FOR UPDATE USING (true) WITH CHECK (true);


--
-- Name: profiles Profiles: self insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Profiles: self insert" ON public.profiles FOR INSERT WITH CHECK ((auth.uid() = auth_user_id));


--
-- Name: profiles Profiles: self read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Profiles: self read" ON public.profiles FOR SELECT USING ((auth.uid() = auth_user_id));


--
-- Name: profiles Profiles: self update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Profiles: self update" ON public.profiles FOR UPDATE USING ((auth.uid() = auth_user_id)) WITH CHECK ((auth.uid() = auth_user_id));


--
-- Name: profiles Profiles: service insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Profiles: service insert" ON public.profiles FOR INSERT WITH CHECK ((auth.role() = 'service_role'::text));


--
-- Name: role_permissions Role permissions: admin update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Role permissions: admin update" ON public.role_permissions FOR UPDATE USING ((public.current_jwt_role() = 'admin'::text)) WITH CHECK ((public.current_jwt_role() = 'admin'::text));


--
-- Name: role_permissions Role permissions: read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Role permissions: read" ON public.role_permissions FOR SELECT USING (true);


--
-- Name: role_permissions Role permissions: service insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Role permissions: service insert" ON public.role_permissions FOR INSERT WITH CHECK ((auth.role() = 'service_role'::text));


--
-- Name: profiles Service role creates profiles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Service role creates profiles" ON public.profiles FOR INSERT WITH CHECK ((auth.role() = 'service_role'::text));


--
-- Name: email_drafts Users can create email drafts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can create email drafts" ON public.email_drafts FOR INSERT WITH CHECK (true);


--
-- Name: profiles Users can read their own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can read their own profile" ON public.profiles FOR SELECT USING ((auth.uid() = auth_user_id));


--
-- Name: email_drafts Users can update email drafts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update email drafts" ON public.email_drafts FOR UPDATE USING (true);


--
-- Name: profiles Users can update own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE TO authenticated USING ((auth_user_id = auth.uid())) WITH CHECK ((auth_user_id = auth.uid()));


--
-- Name: email_drafts Users can view email drafts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view email drafts" ON public.email_drafts FOR SELECT USING (true);


--
-- Name: user_permissions Users can view own permission overrides; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view own permission overrides" ON public.user_permissions FOR SELECT USING ((auth_user_id = auth.uid()));


--
-- Name: profiles Users can view own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view own profile" ON public.profiles FOR SELECT TO authenticated USING ((auth_user_id = auth.uid()));


--
-- Name: mailboxes admin_delete_mailboxes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_delete_mailboxes ON public.mailboxes FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.auth_user_id = auth.uid()) AND (profiles.role = 'admin'::public.role_type)))));


--
-- Name: mailboxes admin_insert_mailboxes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_insert_mailboxes ON public.mailboxes FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.auth_user_id = auth.uid()) AND (profiles.role = 'admin'::public.role_type)))));


--
-- Name: mailboxes admin_update_mailboxes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_update_mailboxes ON public.mailboxes FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.auth_user_id = auth.uid()) AND (profiles.role = 'admin'::public.role_type)))));


--
-- Name: campaigns; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.campaigns ENABLE ROW LEVEL SECURITY;

--
-- Name: campaigns campaigns_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY campaigns_delete_policy ON public.campaigns FOR DELETE USING (public.has_permission('manage_campaigns'::text));


--
-- Name: campaigns campaigns_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY campaigns_insert_policy ON public.campaigns FOR INSERT WITH CHECK (public.has_permission('manage_campaigns'::text));


--
-- Name: campaigns campaigns_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY campaigns_select_policy ON public.campaigns FOR SELECT USING (public.has_permission('view_campaigns'::text));


--
-- Name: campaigns campaigns_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY campaigns_update_policy ON public.campaigns FOR UPDATE USING ((public.has_permission('manage_campaigns'::text) OR public.has_permission('approve_campaigns'::text)));


--
-- Name: contact_product_interests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contact_product_interests ENABLE ROW LEVEL SECURITY;

--
-- Name: contact_product_interests contact_product_interests_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contact_product_interests_delete_policy ON public.contact_product_interests FOR DELETE USING (public.has_permission('manage_contacts'::text));


--
-- Name: contact_product_interests contact_product_interests_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contact_product_interests_insert_policy ON public.contact_product_interests FOR INSERT WITH CHECK (public.has_permission('manage_contacts'::text));


--
-- Name: contact_product_interests contact_product_interests_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contact_product_interests_select_policy ON public.contact_product_interests FOR SELECT USING (public.has_permission('view_contacts'::text));


--
-- Name: contact_product_interests contact_product_interests_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contact_product_interests_update_policy ON public.contact_product_interests FOR UPDATE USING (public.has_permission('manage_contacts'::text));


--
-- Name: contacts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;

--
-- Name: contacts contacts_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contacts_delete_policy ON public.contacts FOR DELETE USING (public.has_permission('manage_contacts'::text));


--
-- Name: contacts contacts_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contacts_insert_policy ON public.contacts FOR INSERT WITH CHECK (public.has_permission('manage_contacts'::text));


--
-- Name: contacts contacts_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contacts_select_policy ON public.contacts FOR SELECT USING (public.has_permission('view_contacts'::text));


--
-- Name: contacts contacts_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contacts_update_policy ON public.contacts FOR UPDATE USING (public.has_permission('manage_contacts'::text));


--
-- Name: conversations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

--
-- Name: conversations conversations_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY conversations_delete_policy ON public.conversations FOR DELETE USING (public.is_admin());


--
-- Name: conversations conversations_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY conversations_insert_policy ON public.conversations FOR INSERT WITH CHECK (true);


--
-- Name: conversations conversations_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY conversations_select_policy ON public.conversations FOR SELECT USING (public.has_permission('view_emails'::text));


--
-- Name: conversations conversations_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY conversations_update_policy ON public.conversations FOR UPDATE USING (true);


--
-- Name: email_drafts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.email_drafts ENABLE ROW LEVEL SECURITY;

--
-- Name: emails; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.emails ENABLE ROW LEVEL SECURITY;

--
-- Name: emails emails_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY emails_delete_policy ON public.emails FOR DELETE USING (public.is_admin());


--
-- Name: emails emails_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY emails_insert_policy ON public.emails FOR INSERT WITH CHECK (true);


--
-- Name: emails emails_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY emails_select_policy ON public.emails FOR SELECT USING (public.has_permission('view_emails'::text));


--
-- Name: emails emails_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY emails_update_policy ON public.emails FOR UPDATE USING (true);


--
-- Name: mailboxes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.mailboxes ENABLE ROW LEVEL SECURITY;

--
-- Name: organizations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

--
-- Name: organizations organizations_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY organizations_delete_policy ON public.organizations FOR DELETE USING (public.has_permission('manage_contacts'::text));


--
-- Name: organizations organizations_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY organizations_insert_policy ON public.organizations FOR INSERT WITH CHECK (public.has_permission('manage_contacts'::text));


--
-- Name: organizations organizations_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY organizations_select_policy ON public.organizations FOR SELECT USING (public.has_permission('view_contacts'::text));


--
-- Name: organizations organizations_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY organizations_update_policy ON public.organizations FOR UPDATE USING (public.has_permission('manage_contacts'::text));


--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: contacts public_read_contacts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY public_read_contacts ON public.contacts FOR SELECT USING (true);


--
-- Name: conversations public_read_conversations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY public_read_conversations ON public.conversations FOR SELECT USING (true);


--
-- Name: emails public_read_emails; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY public_read_emails ON public.emails FOR SELECT USING (true);


--
-- Name: mailboxes public_read_mailboxes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY public_read_mailboxes ON public.mailboxes FOR SELECT USING (true);


--
-- Name: role_permissions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;

--
-- Name: user_permissions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_permissions ENABLE ROW LEVEL SECURITY;

--
-- Name: workflow_executions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.workflow_executions ENABLE ROW LEVEL SECURITY;

--
-- Name: workflows; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.workflows ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

\unrestrict 1GKsagdZzdzFdDlSHmXeUa31FoKKTuwVjoWk31bGYul4VwcyK9ZvF8j9tDQdhdE

