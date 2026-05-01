-- 20260501010500_emails_enrichment_backfill.sql
-- Backfill: emails with non-null classification fields are 'enriched';
-- recent ones without are 'pending'; older ones are 'skipped'.
-- Adjust column references below if your enrichment fields differ.
UPDATE emails
SET enrichment_status = 'enriched',
    enriched_at = COALESCE(updated_at, created_at)
WHERE enrichment_status = 'pending'
  AND classification IS NOT NULL;

UPDATE emails
SET enrichment_status = 'skipped'
WHERE enrichment_status = 'pending'
  AND created_at < now() - interval '30 days';
