-- 20260501010500_emails_enrichment_backfill.sql
-- Backfill: emails with non-null ai_processed_at are 'enriched';
-- recent ones without are 'pending'; older ones are 'skipped'.
-- Adjust column references below if your enrichment fields differ.
UPDATE emails
SET enrichment_status = 'enriched',
    enriched_at = COALESCE(ai_processed_at, updated_at, created_at)
WHERE enrichment_status = 'pending'
  AND ai_processed_at IS NOT NULL;

UPDATE emails
SET enrichment_status = 'skipped'
WHERE enrichment_status = 'pending'
  AND created_at < now() - interval '30 days';
