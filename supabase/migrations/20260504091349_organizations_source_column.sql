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

ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'auto';

COMMENT ON COLUMN public.organizations.source IS
  'Origin of this row. Values: seeded | manual | auto | enriched. '
  'Lambda enrichment skips name update when source IN (seeded, manual) '
  'so curated org names are not overwritten by LLM signature extraction.';

-- Index for the guard query (small column, frequent read during enrichment)
CREATE INDEX IF NOT EXISTS idx_organizations_source
  ON public.organizations (source);

-- Smoke test: column exists and is non-null
DO $smoke$
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
END;
$smoke$;

COMMIT;
