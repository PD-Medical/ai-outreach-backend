-- ============================================================================
-- Train M — organizations.name_source + name_pending_review
-- ============================================================================
-- The K.2 `source` column records how the org row was created (seeded /
-- manual / auto / enriched). It conflates two questions: "who created this
-- row" and "where did the name come from". Train M splits the second one out
-- so the trust-merge can apply a confidence ranking between name sources
-- without breaking the K.2 row-protection guard.
--
-- name_source values:
--   seeded       — bulk-loaded from supabase/seed/org_seed.sql
--   manual       — operator typed it in the UI
--   enriched_ai  — Claude extracted it from an email signature
--   homepage     — homepage <head> scrape (og:site_name, JSON-LD, title)
--   domain_stem  — last-resort fallback: initcap of the domain's first label
--
-- Confidence ranking used by the trust-merge in the lambda:
--   manual = 1.00   (locked, never auto-overwritten)
--   seeded = 0.90   (locked, never auto-overwritten)
--   homepage = 0.85
--   enriched_ai = 0.70
--   domain_stem = 0.30
--
-- name_pending_review flags rows that landed via domain_stem fallback (no
-- real signal found). Surfaced in the UI's "Domains needing review" queue
-- so operators can rename in one click.
-- ============================================================================

BEGIN;

-- 1. name_source column
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS name_source text;

-- Backfill from existing source: enriched rows were AI-named (Train L);
-- legacy 'auto' rows are also best-effort AI-derived. seeded/manual map 1:1.
UPDATE public.organizations
SET name_source = CASE
  WHEN source = 'seeded'   THEN 'seeded'
  WHEN source = 'manual'   THEN 'manual'
  WHEN source = 'enriched' THEN 'enriched_ai'
  WHEN source = 'auto'     THEN 'enriched_ai'  -- legacy, no longer written
  ELSE 'manual'
END
WHERE name_source IS NULL;

ALTER TABLE public.organizations
  ALTER COLUMN name_source SET NOT NULL;

ALTER TABLE public.organizations
  ALTER COLUMN name_source SET DEFAULT 'manual';

ALTER TABLE public.organizations
  DROP CONSTRAINT IF EXISTS organizations_name_source_check;

ALTER TABLE public.organizations
  ADD CONSTRAINT organizations_name_source_check
  CHECK (name_source IN ('seeded', 'manual', 'enriched_ai', 'homepage', 'domain_stem'));

CREATE INDEX IF NOT EXISTS idx_organizations_name_source
  ON public.organizations(name_source);

COMMENT ON COLUMN public.organizations.name_source IS
  'Where the current name came from. seeded/manual are locked against AI '
  'overwrites (K.2 guard). homepage > enriched_ai > domain_stem in trust-merge '
  'rank — a higher-rank source can refine the name; a lower-rank cannot.';

-- 2. name_pending_review flag
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS name_pending_review boolean NOT NULL DEFAULT false;

-- Backfill: any row currently named via domain_stem fallback would be flagged.
-- The L3 routing path that created today's enriched rows used either a real
-- AI extraction or the same domain-stem fallback the new resolver does. We
-- can't distinguish those retrospectively, so leave existing rows alone —
-- the wipe + re-import in M4 will set this correctly going forward.

CREATE INDEX IF NOT EXISTS idx_organizations_name_pending_review
  ON public.organizations(id)
  WHERE name_pending_review;

COMMENT ON COLUMN public.organizations.name_pending_review IS
  'True when the org name came from the domain_stem fallback (no real signal '
  'from AI signature or homepage scrape). Surfaced in the UI review queue '
  'for operator rename. Cleared automatically when name_source advances.';

COMMIT;

-- Smoke tests
DO $smoke$
DECLARE
  v_unmapped int;
BEGIN
  SELECT count(*) INTO v_unmapped
  FROM public.organizations
  WHERE name_source IS NULL;
  IF v_unmapped > 0 THEN
    RAISE EXCEPTION 'Train M smoke: % organizations have NULL name_source after backfill', v_unmapped;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'organizations_name_source_check'
  ) THEN
    RAISE EXCEPTION 'Train M smoke: organizations_name_source_check constraint missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'organizations'
      AND column_name = 'name_pending_review'
      AND is_nullable = 'NO'
  ) THEN
    RAISE EXCEPTION 'Train M smoke: organizations.name_pending_review missing or nullable';
  END IF;
END
$smoke$;
