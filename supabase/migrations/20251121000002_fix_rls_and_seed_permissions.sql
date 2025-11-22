-- Migration: Sync with cloud schema changes
-- - Fix recursive RLS policies
-- - Seed role_permissions
-- - Add new functions and triggers from cloud

-- ===========================================
-- 1. DROP RECURSIVE RLS POLICIES ON PROFILES
-- ===========================================
-- These policies cause infinite recursion because they query profiles
-- table while being applied to the profiles table

DROP POLICY IF EXISTS "Admins can manage profiles" ON profiles;
DROP POLICY IF EXISTS "Admins can read all profiles" ON profiles;
DROP POLICY IF EXISTS "Admins can update profiles" ON profiles;
DROP POLICY IF EXISTS "Admins can view all profiles" ON profiles;
DROP POLICY IF EXISTS "Profiles: admin read" ON profiles;
DROP POLICY IF EXISTS "Profiles: admin update" ON profiles;

-- ===========================================
-- 2. SEED ROLE_PERMISSIONS TABLE
-- ===========================================
-- Ensure all roles have their default permissions set

INSERT INTO role_permissions (role, view_users, manage_users, view_contacts, manage_contacts, view_campaigns, manage_campaigns, approve_campaigns, view_analytics, manage_approvals, view_workflows, view_emails)
VALUES
  ('admin', true, true, true, true, true, true, true, true, true, true, true),
  ('sales', false, false, true, true, true, true, false, true, false, true, true),
  ('accounts', false, false, true, true, true, false, true, true, true, true, true),
  ('management', false, false, true, false, true, false, true, true, true, true, true)
ON CONFLICT (role) DO UPDATE SET
  view_users = EXCLUDED.view_users,
  manage_users = EXCLUDED.manage_users,
  view_contacts = EXCLUDED.view_contacts,
  manage_contacts = EXCLUDED.manage_contacts,
  view_campaigns = EXCLUDED.view_campaigns,
  manage_campaigns = EXCLUDED.manage_campaigns,
  approve_campaigns = EXCLUDED.approve_campaigns,
  view_analytics = EXCLUDED.view_analytics,
  manage_approvals = EXCLUDED.manage_approvals,
  view_workflows = EXCLUDED.view_workflows,
  view_emails = EXCLUDED.view_emails;

-- ===========================================
-- 3. NEW FUNCTIONS FROM CLOUD
-- ===========================================

-- Function: add_timestamp_trigger
-- Manually adds updated_at trigger to a table
CREATE OR REPLACE FUNCTION public.add_timestamp_trigger(target_table text) RETURNS void
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

-- Function: auto_add_timestamp_trigger
-- Event trigger function to automatically add updated_at triggers to new tables
CREATE OR REPLACE FUNCTION public.auto_add_timestamp_trigger() RETURNS event_trigger
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

-- ===========================================
-- 4. EVENT TRIGGERS FOR AUTO TIMESTAMP
-- ===========================================
-- These automatically add updated_at triggers to new tables

DROP EVENT TRIGGER IF EXISTS auto_timestamp_on_create;
CREATE EVENT TRIGGER auto_timestamp_on_create ON ddl_command_end
    WHEN TAG IN ('CREATE TABLE')
    EXECUTE FUNCTION public.auto_add_timestamp_trigger();

DROP EVENT TRIGGER IF EXISTS auto_timestamp_on_alter;
CREATE EVENT TRIGGER auto_timestamp_on_alter ON ddl_command_end
    WHEN TAG IN ('ALTER TABLE')
    EXECUTE FUNCTION public.auto_add_timestamp_trigger();

-- ===========================================
-- 6. SET_UPDATED_AT TRIGGERS FOR ALL TABLES
-- ===========================================
-- Ensure all tables with updated_at have the trigger

DO $$
DECLARE
    tbl TEXT;
    tables TEXT[] := ARRAY[
        'action_items', 'campaign_contact_summary', 'campaign_sequences',
        'campaigns', 'contact_product_interests', 'contacts', 'conversations',
        'email_drafts', 'email_templates', 'emails', 'mailboxes',
        'organization_types', 'organizations', 'parent_products',
        'product_categories', 'products', 'profiles', 'role_permissions',
        'system_config', 'user_permissions'
    ];
BEGIN
    FOREACH tbl IN ARRAY tables
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS set_updated_at ON public.%I', tbl);
        EXECUTE format(
            'CREATE TRIGGER set_updated_at
             BEFORE UPDATE ON public.%I
             FOR EACH ROW
             EXECUTE FUNCTION public.update_updated_at_column()',
            tbl
        );
    END LOOP;
END;
$$;
