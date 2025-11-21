-- ================================================================================
-- UNIFIED AUTOMATIC TIMESTAMP TRIGGER SYSTEM
-- ================================================================================
-- Purpose: 
--   1. Replace 8 individual timestamp triggers with one unified system
--   2. Automatically create triggers for any new table with updated_at column
--   3. Clean, maintainable, future-proof
--
-- What this does:
--   - Removes all old timestamp triggers (8 separate triggers)
--   - Creates ONE reusable function
--   - Sets up automatic trigger creation for future tables
--   - Applies unified triggers to all existing tables
-- ================================================================================

-- ============================================================
-- STEP 1: Create the shared timestamp function
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION update_updated_at_column() IS 
'Shared trigger function: Automatically updates updated_at column to current timestamp.
Used across all tables with updated_at column via unified trigger system.';

-- ============================================================
-- STEP 2: Create automatic trigger creation function
-- ============================================================
CREATE OR REPLACE FUNCTION auto_add_timestamp_trigger()
RETURNS event_trigger
LANGUAGE plpgsql
AS $$
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
$$;

COMMENT ON FUNCTION auto_add_timestamp_trigger() IS 
'Event trigger function: Automatically creates timestamp triggers for any table with updated_at column.
Fires on CREATE TABLE and ALTER TABLE commands.';

-- ============================================================
-- STEP 3: Create event triggers for automatic behavior
-- ============================================================

-- Event trigger for CREATE TABLE
DROP EVENT TRIGGER IF EXISTS auto_timestamp_on_create;
CREATE EVENT TRIGGER auto_timestamp_on_create
    ON ddl_command_end
    WHEN TAG IN ('CREATE TABLE')
    EXECUTE FUNCTION auto_add_timestamp_trigger();

COMMENT ON EVENT TRIGGER auto_timestamp_on_create IS 
'Automatically creates timestamp trigger when new table with updated_at is created.';

-- Event trigger for ALTER TABLE (when adding updated_at column)
DROP EVENT TRIGGER IF EXISTS auto_timestamp_on_alter;
CREATE EVENT TRIGGER auto_timestamp_on_alter
    ON ddl_command_end
    WHEN TAG IN ('ALTER TABLE')
    EXECUTE FUNCTION auto_add_timestamp_trigger();

COMMENT ON EVENT TRIGGER auto_timestamp_on_alter IS 
'Automatically creates timestamp trigger when updated_at column is added to existing table.';

-- ============================================================
-- STEP 4: Create helper function for manual use
-- ============================================================
CREATE OR REPLACE FUNCTION add_timestamp_trigger(target_table TEXT)
RETURNS void
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

COMMENT ON FUNCTION add_timestamp_trigger(TEXT) IS 
'Helper function: Manually add timestamp trigger to a specific table.
Usage: SELECT add_timestamp_trigger(''my_table'');
Useful for existing tables or if event triggers are disabled.';

-- ============================================================
-- STEP 5: Remove all old timestamp triggers
-- ============================================================
DO $$
DECLARE
    trigger_record RECORD;
BEGIN
    RAISE NOTICE 'Removing old timestamp triggers...';
    
    -- Drop all old timestamp-related triggers
    FOR trigger_record IN
        SELECT trigger_name, event_object_table
        FROM information_schema.triggers
        WHERE trigger_schema = 'public'
          AND (
              trigger_name LIKE '%updated_at%' 
              OR trigger_name LIKE 'update_%'
          )
          AND trigger_name != 'set_updated_at'  -- Don't drop the new ones
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I',
            trigger_record.trigger_name,
            trigger_record.event_object_table
        );
        
        RAISE NOTICE '   Removed old trigger: % on %', 
            trigger_record.trigger_name, 
            trigger_record.event_object_table;
    END LOOP;
    
    RAISE NOTICE ' Old triggers removed successfully';
END $$;

-- ============================================================
-- STEP 6: Apply unified triggers to all existing tables
-- ============================================================
-- ============================================================
-- STEP 6: Apply unified triggers to all existing tables
-- ============================================================
DO $$
DECLARE
    table_record RECORD;
    trigger_count INTEGER := 0;
BEGIN
    RAISE NOTICE 'Creating unified timestamp triggers for existing tables...';
    
    -- Find all TABLES (not views) with updated_at column
    FOR table_record IN
        SELECT DISTINCT c.table_name
        FROM information_schema.columns c
        INNER JOIN information_schema.tables t 
            ON t.table_schema = c.table_schema 
            AND t.table_name = c.table_name
        WHERE c.table_schema = 'public'
          AND c.column_name = 'updated_at'
          AND c.data_type LIKE 'timestamp%'
          AND t.table_type = 'BASE TABLE'  -- ✅ Only real tables, not views!
        ORDER BY c.table_name
    LOOP
        -- Use the helper function to create trigger
        PERFORM add_timestamp_trigger(table_record.table_name);
        trigger_count := trigger_count + 1;
    END LOOP;
    
    RAISE NOTICE '✅ Created % unified timestamp triggers', trigger_count;
END $$;

-- ============================================================
-- STEP 7: Verification query
-- ============================================================
DO $$
DECLARE
    trigger_count INTEGER;
    table_count INTEGER;
BEGIN
    -- Count tables with updated_at
    SELECT COUNT(DISTINCT table_name) INTO table_count
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND column_name = 'updated_at';
    
    -- Count set_updated_at triggers
    SELECT COUNT(*) INTO trigger_count
    FROM information_schema.triggers
    WHERE trigger_schema = 'public'
      AND trigger_name = 'set_updated_at';
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'UNIFIED TIMESTAMP SYSTEM - VERIFICATION';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Tables with updated_at column: %', table_count;
    RAISE NOTICE 'Unified triggers created: %', trigger_count;
    RAISE NOTICE 'Event triggers active: 2 (CREATE TABLE, ALTER TABLE)';
    RAISE NOTICE '';
    
    IF trigger_count = table_count THEN
        RAISE NOTICE ' SUCCESS: All tables have unified timestamp triggers';
    ELSE
        RAISE WARNING '  Mismatch: % tables but % triggers', table_count, trigger_count;
    END IF;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
END $$;

-- ============================================================
-- DOCUMENTATION
-- ============================================================

COMMENT ON SCHEMA public IS 
'Unified Timestamp System Active:
- Automatic trigger creation for tables with updated_at column
- Event triggers: auto_timestamp_on_create, auto_timestamp_on_alter
- Manual helper: add_timestamp_trigger(table_name)
- All triggers named: set_updated_at
Last updated: 2025-11-21';

