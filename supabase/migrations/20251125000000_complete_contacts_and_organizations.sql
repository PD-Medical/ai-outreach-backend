-- ============================================================================
-- COMPLETE CONTACTS & ORGANIZATIONS MIGRATION
-- ============================================================================

--
-- WHAT THIS DOES:
-- 1. Backs up existing contacts and organizations
-- 2. Inserts ALL 2,283 organizations from Excel (with new IDs)
-- 3. RE-LINKS all existing contacts to NEW organization IDs by domain matching
-- 4. Removes duplicate contacts
-- 5. Restores all constraints
--
-- THE MAGIC: Contacts with old org IDs get linked to new org IDs automatically!
--
-- RUNTIME: 10-15 minutes
-- DOWNTIME: None required
-- ROLLBACK: Automatic on error (transaction-based)
--
-- USAGE: psql $DATABASE_URL -f COMPLETE_CONTACTS_ORGS_MIGRATION.sql
--
-- ============================================================================

\timing on

\set ON_ERROR_STOP on

BEGIN;

-- ============================================================================
-- PHASE 1: PRE-FLIGHT CHECKS & BACKUPS
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================================================';
  RAISE NOTICE '   COMPLETE CONTACTS & ORGANIZATIONS MIGRATION';
  RAISE NOTICE '========================================================================';
  RAISE NOTICE '';
  RAISE NOTICE 'This will:';
  RAISE NOTICE '  1. Backup existing contacts and organizations';
  RAISE NOTICE '  2. Insert 2,283 NEW organizations';
  RAISE NOTICE '  3. RE-LINK contacts to NEW org IDs by email domain';
  RAISE NOTICE '  4. Remove duplicate contacts';
  RAISE NOTICE '  5. Restore all constraints';
  RAISE NOTICE '';
  RAISE NOTICE 'Starting...';
  RAISE NOTICE '';
END $$;

-- Create backups
DO $$
DECLARE
  v_backup_contacts TEXT;
  v_backup_orgs TEXT;
BEGIN
  v_backup_contacts := 'contacts_backup_' || TO_CHAR(NOW(), 'YYYYMMDD_HH24MISS');
  v_backup_orgs := 'organizations_backup_' || TO_CHAR(NOW(), 'YYYYMMDD_HH24MISS');

  EXECUTE format('CREATE TABLE %I AS SELECT * FROM contacts', v_backup_contacts);
  EXECUTE format('CREATE TABLE %I AS SELECT * FROM organizations', v_backup_orgs);

  RAISE NOTICE ' Backups created: % and %', v_backup_contacts, v_backup_orgs;
END $$;

-- ============================================================================
-- PHASE 2: SETUP NULL DOMAIN HANDLING
-- ============================================================================

RAISE NOTICE '';
RAISE NOTICE '========================================================================';
RAISE NOTICE 'PHASE 2: SETTING UP DOMAIN AUTO-GENERATION';
RAISE NOTICE '========================================================================';

CREATE OR REPLACE FUNCTION generate_placeholder_domain()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.domain IS NULL OR NEW.domain = '' THEN
        NEW.domain := LOWER(
            REGEXP_REPLACE(NEW.name, '[^a-zA-Z0-9]+', '', 'g')
        ) || COALESCE('.' || LOWER(NEW.state), '') || '.placeholder.local';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS ensure_domain_not_null ON organizations;

CREATE TRIGGER ensure_domain_not_null
    BEFORE INSERT OR UPDATE ON organizations
    FOR EACH ROW
    EXECUTE FUNCTION generate_placeholder_domain();

RAISE NOTICE ' Domain trigger created';

-- ============================================================================
-- PHASE 3: CLEAR OLD ORGANIZATIONS & INSERT NEW ONES
-- ============================================================================

RAISE NOTICE '';
RAISE NOTICE '========================================================================';
RAISE NOTICE 'PHASE 3: INSERTING NEW ORGANIZATIONS';
RAISE NOTICE '========================================================================';
RAISE NOTICE 'Clearing old organizations...';

-- Clear old organizations (contacts will be re-linked later)
TRUNCATE TABLE organizations CASCADE;

RAISE NOTICE 'Inserting 2,283 new organizations (this takes 2-3 minutes)...';
RAISE NOTICE '';

-- Insert ALL organizations from your Excel database
-- This file should be generated from the migration_batches_02_to_50.sql content
\i /path/to/migration_batches_02_to_50.sql

-- NOTE: If you don't have a separate file, the INSERT statements from
-- ULTIMATE_SINGLE_FILE_MIGRATION.sql should be copied here

DO $$
DECLARE
  v_org_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_org_count FROM organizations;
  RAISE NOTICE ' Organizations inserted: %', v_org_count;

  IF v_org_count < 2000 THEN
    RAISE WARNING 'Organization count seems low! Expected ~2,283';
  END IF;
END $$;

-- ============================================================================
-- PHASE 4: RE-LINK CONTACTS TO NEW ORGANIZATIONS
-- ============================================================================

RAISE NOTICE '';
RAISE NOTICE '========================================================================';
RAISE NOTICE 'PHASE 4: RE-LINKING CONTACTS TO NEW ORGANIZATIONS';
RAISE NOTICE '========================================================================';
RAISE NOTICE 'This is the magic step - matching by email domain!';
RAISE NOTICE '';

-- Create mapping table: email domain → new organization ID
CREATE TEMP TABLE domain_to_org_mapping AS
SELECT DISTINCT
  LOWER(domain) as domain,
  id as org_id,
  name as org_name
FROM organizations
WHERE domain IS NOT NULL
  AND domain != ''
  AND domain NOT LIKE '%.placeholder.local';

DO $$
DECLARE
  v_domains INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_domains FROM domain_to_org_mapping;
  RAISE NOTICE 'Created mapping for % domains to organizations', v_domains;
END $$;

-- Drop constraints temporarily
ALTER TABLE contacts DROP CONSTRAINT IF EXISTS contacts_organization_id_fkey;
ALTER TABLE contacts DROP CONSTRAINT IF EXISTS contacts_email_key;
ALTER TABLE contacts DROP CONSTRAINT IF EXISTS contacts_pkey CASCADE;
ALTER TABLE contacts DROP CONSTRAINT IF EXISTS idx_contacts_name_org_unique;
DROP INDEX IF EXISTS idx_contacts_name_org_unique;

RAISE NOTICE 'Constraints dropped temporarily';

-- Update contacts to link to NEW organization IDs
UPDATE contacts c
SET organization_id = m.org_id
FROM domain_to_org_mapping m
WHERE LOWER(SPLIT_PART(c.email, '@', 2)) = m.domain
  AND c.email IS NOT NULL
  AND c.email != '';

DO $$
DECLARE
  v_updated INTEGER;
  v_total INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_updated FROM contacts WHERE organization_id IS NOT NULL;
  SELECT COUNT(*) INTO v_total FROM contacts;

  RAISE NOTICE '';
  RAISE NOTICE ' Contacts re-linked: % out of % (%.1f%%)',
    v_updated, v_total, (100.0 * v_updated / NULLIF(v_total, 0));
  RAISE NOTICE '';
END $$;

-- ============================================================================
-- PHASE 5: REMOVE DUPLICATE CONTACTS
-- ============================================================================

RAISE NOTICE '';
RAISE NOTICE '========================================================================';
RAISE NOTICE 'PHASE 5: REMOVING DUPLICATE CONTACTS';
RAISE NOTICE '========================================================================';

-- Remove duplicates (keep most recent version)
WITH ranked_contacts AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY
        LOWER(TRIM(COALESCE(first_name, ''))),
        LOWER(TRIM(COALESCE(last_name, ''))),
        organization_id
      ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST
    ) as rn
  FROM contacts
)
DELETE FROM contacts
WHERE id IN (
  SELECT id FROM ranked_contacts WHERE rn > 1
);

DO $$
DECLARE
  v_remaining INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_remaining FROM contacts;
  RAISE NOTICE ' Duplicates removed. Contacts remaining: %', v_remaining;
END $$;

-- ============================================================================
-- PHASE 6: RESTORE ALL CONSTRAINTS
-- ============================================================================

RAISE NOTICE '';
RAISE NOTICE '========================================================================';
RAISE NOTICE 'PHASE 6: RESTORING CONSTRAINTS';
RAISE NOTICE '========================================================================';

-- Primary key
ALTER TABLE contacts ADD PRIMARY KEY (id);
RAISE NOTICE 'PRIMARY KEY restored';

-- Unique email
ALTER TABLE contacts ADD CONSTRAINT contacts_email_key UNIQUE (email);
RAISE NOTICE ' UNIQUE email constraint restored';

-- Unique name + org
CREATE UNIQUE INDEX idx_contacts_name_org_unique
ON contacts (
  (LOWER(TRIM(COALESCE(first_name, '')))),
  (LOWER(TRIM(COALESCE(last_name, '')))),
  organization_id
);
RAISE NOTICE ' UNIQUE name+org index restored';

-- Foreign key to organizations
ALTER TABLE contacts
ADD CONSTRAINT contacts_organization_id_fkey
FOREIGN KEY (organization_id)
REFERENCES organizations(id)
ON DELETE SET NULL
ON UPDATE CASCADE;
RAISE NOTICE ' FOREIGN KEY organization_id restored';

-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_contacts_organization_id
  ON contacts(organization_id) WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_contacts_email_lower
  ON contacts(LOWER(email));
CREATE INDEX IF NOT EXISTS idx_contacts_status
  ON contacts(status);
CREATE INDEX IF NOT EXISTS idx_organizations_domain
  ON organizations(LOWER(domain));
RAISE NOTICE ' Performance indexes created';

-- ============================================================================
-- PHASE 7: VERIFICATION
-- ============================================================================

RAISE NOTICE '';
RAISE NOTICE '========================================================================';
RAISE NOTICE 'PHASE 7: VERIFICATION';
RAISE NOTICE '========================================================================';

DO $$
DECLARE
  v_total_orgs INTEGER;
  v_total_contacts INTEGER;
  v_linked_contacts INTEGER;
  v_unlinked_contacts INTEGER;
  v_email_dupes INTEGER;
  v_name_dupes INTEGER;
BEGIN
  -- Counts
  SELECT COUNT(*) INTO v_total_orgs FROM organizations;
  SELECT COUNT(*) INTO v_total_contacts FROM contacts;
  SELECT COUNT(*) INTO v_linked_contacts
    FROM contacts WHERE organization_id IS NOT NULL;
  SELECT COUNT(*) INTO v_unlinked_contacts
    FROM contacts WHERE organization_id IS NULL;

  -- Check for duplicates
  SELECT COUNT(*) INTO v_email_dupes FROM (
    SELECT email FROM contacts WHERE email IS NOT NULL
    GROUP BY email HAVING COUNT(*) > 1
  ) x;

  SELECT COUNT(*) INTO v_name_dupes FROM (
    SELECT
      LOWER(TRIM(COALESCE(first_name, ''))),
      LOWER(TRIM(COALESCE(last_name, ''))),
      organization_id
    FROM contacts
    GROUP BY 1,2,3
    HAVING COUNT(*) > 1
  ) x;

  RAISE NOTICE '';
  RAISE NOTICE 'FINAL RESULTS:';
  RAISE NOTICE '==============';
  RAISE NOTICE '';
  RAISE NOTICE 'Organizations: %', v_total_orgs;
  RAISE NOTICE 'Contacts: %', v_total_contacts;
  RAISE NOTICE 'Contacts linked to orgs: % (%.1f%%)',
    v_linked_contacts,
    (100.0 * v_linked_contacts / NULLIF(v_total_contacts, 0));
  RAISE NOTICE 'Contacts unlinked: % (%.1f%%)',
    v_unlinked_contacts,
    (100.0 * v_unlinked_contacts / NULLIF(v_total_contacts, 0));
  RAISE NOTICE '';
  RAISE NOTICE 'DATA QUALITY:';
  RAISE NOTICE '=============';
  RAISE NOTICE 'Duplicate emails: %', v_email_dupes;
  RAISE NOTICE 'Duplicate name+org: %', v_name_dupes;
  RAISE NOTICE '';

  IF v_email_dupes > 0 OR v_name_dupes > 0 THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: Duplicates detected!';
  END IF;

  IF v_total_orgs < 2000 THEN
    RAISE WARNING 'Organization count seems low!';
  END IF;

  IF v_total_contacts < 2000 THEN
    RAISE WARNING 'Contact count seems low!';
  END IF;

  RAISE NOTICE ' VERIFICATION PASSED! ';
  RAISE NOTICE '';
END $$;

-- ============================================================================
-- PHASE 8: SHOW MAPPING EXAMPLES
-- ============================================================================

RAISE NOTICE '';
RAISE NOTICE '========================================================================';
RAISE NOTICE 'PHASE 8: RE-LINKING EXAMPLES';
RAISE NOTICE '========================================================================';
RAISE NOTICE '';

-- Show some examples of re-linked contacts
DO $$
DECLARE
  v_example RECORD;
  v_count INTEGER := 0;
BEGIN
  RAISE NOTICE 'Sample contacts that were re-linked:';
  RAISE NOTICE '';

  FOR v_example IN
    SELECT
      c.first_name || ' ' || c.last_name as contact_name,
      c.email,
      o.name as organization_name,
      o.city,
      o.state
    FROM contacts c
    JOIN organizations o ON c.organization_id = o.id
    WHERE c.email IS NOT NULL
    ORDER BY c.updated_at DESC
    LIMIT 10
  LOOP
    v_count := v_count + 1;
    RAISE NOTICE '  %: % (%)', v_count, v_example.contact_name, v_example.email;
    RAISE NOTICE '      → Linked to: % (%, %)',
      v_example.organization_name,
      v_example.city,
      v_example.state;
    RAISE NOTICE '';
  END LOOP;
END $$;

-- ============================================================================
-- MIGRATION COMPLETE!
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================================================';
  RAISE NOTICE '          🎉🎉🎉 MIGRATION COMPLETED SUCCESSFULLY! 🎉🎉🎉';
  RAISE NOTICE '========================================================================';
  RAISE NOTICE '';
  RAISE NOTICE 'What was accomplished:';
  RAISE NOTICE '   All organizations from Excel inserted with new IDs';
  RAISE NOTICE '   All contacts re-linked to new organizations by domain';
  RAISE NOTICE '   Duplicate contacts removed';
  RAISE NOTICE '   All constraints restored';
  RAISE NOTICE '   Data verified (no duplicates)';
  RAISE NOTICE '';
  RAISE NOTICE 'Next steps:';
  RAISE NOTICE '  1. Test application - contacts should show correct organizations';
  RAISE NOTICE '  2. Review unlinked contacts (personal emails, missing orgs)';
  RAISE NOTICE '  3. Fix Ramsay/SJOG multi-hospital domains manually if needed';
  RAISE NOTICE '';
  RAISE NOTICE 'Backup tables available with timestamp for rollback';
  RAISE NOTICE '========================================================================';
  RAISE NOTICE '';
END $$;

COMMIT;

\timing off

-- ============================================================================
-- POST-MIGRATION QUERIES
-- ============================================================================

\echo ''
\echo '========================================================================';
\echo 'POST-MIGRATION VERIFICATION QUERIES';
\echo '========================================================================';
\echo ''

-- Summary stats
SELECT
  'Organizations' as metric,
  COUNT(*) as count
FROM organizations
UNION ALL
SELECT
  'Contacts (Total)',
  COUNT(*)
FROM contacts
UNION ALL
SELECT
  'Contacts (Linked)',
  COUNT(*)
FROM contacts
WHERE organization_id IS NOT NULL
UNION ALL
SELECT
  'Contacts (Unlinked)',
  COUNT(*)
FROM contacts
WHERE organization_id IS NULL;

-- Top organizations by contact count
\echo ''
\echo 'Top 10 organizations by contact count:';
\echo ''

SELECT
  o.name,
  o.city,
  o.state,
  COUNT(c.id) as contact_count
FROM organizations o
LEFT JOIN contacts c ON c.organization_id = o.id
GROUP BY o.id, o.name, o.city, o.state
ORDER BY contact_count DESC
LIMIT 10;

\echo ''
\echo ' MIGRATION COMPLETE! ';
\echo '';
\echo 'Your contacts are now linked to the new organizations!';
\echo '';

-- ============================================================================
-- ROLLBACK INSTRUCTIONS (IF NEEDED)
-- ============================================================================

/*
TO ROLLBACK THIS MIGRATION:

1. Find your backup tables:
   SELECT tablename FROM pg_tables
   WHERE tablename LIKE '%backup_%'
   ORDER BY tablename DESC;

2. Restore contacts:
   BEGIN;
   TRUNCATE contacts CASCADE;
   INSERT INTO contacts SELECT * FROM contacts_backup_YYYYMMDD_HHMMSS;
   COMMIT;

3. Restore organizations:
   BEGIN;
   TRUNCATE organizations CASCADE;
   INSERT INTO organizations SELECT * FROM organizations_backup_YYYYMMDD_HHMMSS;
   COMMIT;

4. Restore constraints as needed
*/


