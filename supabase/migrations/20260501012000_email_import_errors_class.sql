-- 20260501012000_email_import_errors_class.sql
ALTER TABLE email_import_errors
  ADD COLUMN IF NOT EXISTS error_class TEXT
    CHECK (error_class IN ('transient', 'persistent', 'unknown'))
    DEFAULT 'unknown';

CREATE INDEX IF NOT EXISTS idx_email_import_errors_class
  ON email_import_errors (error_class)
  WHERE resolved_at IS NULL;

-- Speeds up v_email_activity's latest_error correlated subquery
CREATE INDEX IF NOT EXISTS idx_email_import_errors_message_id
  ON email_import_errors (message_id)
  WHERE resolved_at IS NULL;

COMMENT ON COLUMN email_import_errors.error_class IS
  'Drives UI Retry-button visibility: transient=retryable, persistent=needs dev team.';
