-- ============================================================================
-- Train K.2: Add `source` column to organizations
--
-- WHY:
--   The enrichment LLM was overwriting curated org names with strings
--   extracted from email signatures (e.g. signature "Joondalup Health
--   Campus" → renamed parent "Ramsay Health Care"; sa.gov.au senders'
--   emails containing peter@'s quoted signature → renamed "SA Government"
--   to "PD Medical"). Five seeded orgs were silently corrupted on the
--   2026-05-04 sales@ import.
--
-- WHAT THIS MIGRATION DOES:
--   Pure structure — adds a `source` column (text NOT NULL DEFAULT 'auto')
--   so the lambda guard can distinguish:
--     - 'seeded'   — from supabase/seed/org_seed.sql, NEVER overwrite name
--     - 'manual'   — operator created via UI, NEVER overwrite name
--     - 'auto'     — auto-created during import (Train I removed this path,
--                    legacy default kept for safety)
--     - 'enriched' — created/named by LLM signature parsing
--
--   No data writes, no smoke test on names — operators do TRUNCATE +
--   re-seed afterward to populate `source='seeded'` cleanly.
-- ============================================================================

BEGIN;

-- Add column with safe default. Pre-existing rows are presumed `seeded`
-- (the only way they got into the org table is via the seed file or via
-- operator action — both should be treated as protected). New rows
-- written by the import path use `auto`, by the LLM path use `enriched`,
-- by operator UI use `manual`. The CHECK constraint locks the contract.
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'seeded';

ALTER TABLE public.organizations
  DROP CONSTRAINT IF EXISTS organizations_source_check;
ALTER TABLE public.organizations
  ADD CONSTRAINT organizations_source_check
  CHECK (source IN ('seeded', 'manual', 'auto', 'enriched'));

COMMENT ON COLUMN public.organizations.source IS
  'Origin of this row. Values: seeded | manual | auto | enriched. '
  'Lambda enrichment skips name update when source IN (seeded, manual) '
  'so curated org names are not overwritten by LLM signature extraction. '
  'Default seeded — pre-existing rows are protected by default; new '
  'auto/enriched rows must opt in by setting source explicitly.';

-- Index for the guard query (small column, frequent read during enrichment)
CREATE INDEX IF NOT EXISTS idx_organizations_source
  ON public.organizations (source);

-- Smoke tests: column + constraint
DO $smoke$
DECLARE
  v_constraint_exists boolean;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'organizations'
      AND column_name = 'source'
      AND is_nullable = 'NO'
  ) THEN
    RAISE EXCEPTION 'K.2 smoke test failed: organizations.source column missing or nullable';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'organizations_source_check'
      AND conrelid = 'public.organizations'::regclass
  ) INTO v_constraint_exists;
  IF NOT v_constraint_exists THEN
    RAISE EXCEPTION 'K.2 smoke test failed: organizations_source_check constraint missing';
  END IF;
END;
$smoke$;

COMMIT;
