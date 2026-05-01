-- 20260501010000_emails_enrichment_status.sql
ALTER TABLE emails
  ADD COLUMN IF NOT EXISTS enrichment_status TEXT
    CHECK (enrichment_status IN (
      'pending', 'enriched', 'failed', 'rate_limited', 'skipped'
    ))
    DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS enriched_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_emails_enrichment_pending
  ON emails (created_at)
  WHERE enrichment_status = 'pending';

CREATE INDEX IF NOT EXISTS idx_emails_mailbox_status
  ON emails (mailbox_id, enrichment_status);

COMMENT ON COLUMN emails.enrichment_status IS
  'AI enrichment lifecycle: pending → enriched|failed|rate_limited|skipped. ''skipped'' = enrichment was disabled at import time.';
