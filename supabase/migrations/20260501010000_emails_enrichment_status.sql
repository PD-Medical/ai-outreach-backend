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

-- Activity log paginates by import time (created_at DESC); v_email_activity
-- joins on emails so an ordered index keeps the LIMIT/OFFSET path cheap.
-- The consolidated schema only indexes received_at, not created_at.
CREATE INDEX IF NOT EXISTS idx_emails_created_at_desc
  ON emails (created_at DESC);

COMMENT ON COLUMN emails.enrichment_status IS
  'AI enrichment lifecycle: pending → enriched|failed|rate_limited|skipped. ''skipped'' = enrichment was disabled at import time.';
