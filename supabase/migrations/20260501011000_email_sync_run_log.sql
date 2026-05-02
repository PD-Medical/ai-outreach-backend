-- 20260501011000_email_sync_run_log.sql
CREATE TABLE IF NOT EXISTS email_sync_run_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  process TEXT NOT NULL CHECK (process IN ('sync', 'retry_errors', 'enrich_pending', 'watchdog', 'legacy', 'auto_report_failures')),
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  outcome TEXT,
  emails_processed INTEGER DEFAULT 0,
  emails_succeeded INTEGER DEFAULT 0,
  emails_failed INTEGER DEFAULT 0,
  details JSONB
);

CREATE INDEX IF NOT EXISTS idx_run_log_process_time
  ON email_sync_run_log (process, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_run_log_started
  ON email_sync_run_log (started_at DESC);

COMMENT ON TABLE email_sync_run_log IS
  'One row per scheduled-process invocation. Drives the Background Processes UI section.';
