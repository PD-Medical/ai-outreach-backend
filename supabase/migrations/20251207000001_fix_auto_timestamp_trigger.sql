-- Fix the auto_add_timestamp_trigger function
-- The bug was referencing "auto_add_timestamp_trigger.table_name" instead of just "table_name"
-- table_name is a local variable, not a function parameter, so it shouldn't be qualified

CREATE OR REPLACE FUNCTION public.auto_add_timestamp_trigger() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
    obj RECORD;
    has_updated_at BOOLEAN;
    v_schema_name TEXT;
    v_table_name TEXT;
BEGIN
    -- Loop through all DDL command results
    FOR obj IN SELECT * FROM pg_event_trigger_ddl_commands()
    LOOP
        -- Only process tables in public schema
        IF obj.object_type = 'table' AND obj.schema_name = 'public' THEN

            v_schema_name := obj.schema_name;
            v_table_name := (regexp_match(obj.object_identity, '([^.]+)$'))[1];

            -- Check if this table has updated_at column
            SELECT EXISTS (
                SELECT 1
                FROM information_schema.columns c
                WHERE c.table_schema = v_schema_name
                  AND c.table_name = v_table_name
                  AND c.column_name = 'updated_at'
                  AND c.data_type LIKE 'timestamp%'
            ) INTO has_updated_at;

            -- If table has updated_at, create the trigger
            IF has_updated_at THEN
                -- Drop if exists (for ALTER TABLE case)
                EXECUTE format(
                    'DROP TRIGGER IF EXISTS set_updated_at ON %I.%I',
                    v_schema_name,
                    v_table_name
                );

                -- Create the trigger
                EXECUTE format(
                    'CREATE TRIGGER set_updated_at
                     BEFORE UPDATE ON %I.%I
                     FOR EACH ROW
                     EXECUTE FUNCTION update_updated_at_column()',
                    v_schema_name,
                    v_table_name
                );

                RAISE NOTICE ' Auto-created timestamp trigger for: %.%', v_schema_name, v_table_name;
            END IF;
        END IF;
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN
        -- Log error but don't fail the DDL command
        RAISE WARNING 'Failed to auto-create timestamp trigger: %', SQLERRM;
END;
$_$;

-- Now manually add the timestamp triggers to any tables from the previous migration
-- that may have been missed due to the bug

-- campaign_email_templates table
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'campaign_email_templates'
        AND column_name = 'updated_at'
    ) THEN
        DROP TRIGGER IF EXISTS set_updated_at ON public.campaign_email_templates;
        CREATE TRIGGER set_updated_at
            BEFORE UPDATE ON public.campaign_email_templates
            FOR EACH ROW
            EXECUTE FUNCTION update_updated_at_column();
        RAISE NOTICE 'Added timestamp trigger to campaign_email_templates';
    END IF;
END $$;
