-- 20260501010500_emails_enrichment_backfill.sql
-- Backfill: emails with non-null ai_processed_at are 'enriched';
-- recent ones without are 'pending'; older ones are 'skipped'.
-- Adjust column references below if your enrichment fields differ.
UPDATE emails
SET enrichment_status = 'enriched',
    enriched_at = COALESCE(ai_processed_at, updated_at, created_at)
WHERE enrichment_status = 'pending'
  AND ai_processed_at IS NOT NULL;

-- Old emails (>30 days) are marked 'skipped' rather than 'pending' to avoid
-- creating a massive enrichment backlog at deploy time. Operators can flip
-- specific rows back to 'pending' if they want them enriched. The 30-day
-- window is a deployment cutover heuristic, not a long-term retention policy.
-- NOTE: this UPDATE runs in a single transaction; on tables with millions of
-- rows it may hold locks for several minutes. Consider running out-of-band
-- (psql session) on production-scale data instead of via migration.
UPDATE emails
SET enrichment_status = 'skipped'
WHERE enrichment_status = 'pending'
  AND created_at < now() - interval '30 days';
