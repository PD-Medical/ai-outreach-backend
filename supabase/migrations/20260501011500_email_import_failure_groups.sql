-- 20260501011500_email_import_failure_groups.sql
CREATE TABLE IF NOT EXISTS email_import_failure_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  error_pattern TEXT NOT NULL,
  error_signature TEXT NOT NULL UNIQUE,
  github_issue_url TEXT,
  github_issue_number INTEGER,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  occurrence_count INTEGER NOT NULL DEFAULT 1,
  resolved_at TIMESTAMPTZ
);

-- NOTE: error_signature already has a btree index via the UNIQUE constraint
-- on the column declaration above; no additional index needed for equality lookups.

ALTER TABLE email_import_errors
  ADD COLUMN IF NOT EXISTS failure_group_id UUID REFERENCES email_import_failure_groups(id);

CREATE INDEX IF NOT EXISTS idx_email_import_errors_group
  ON email_import_errors (failure_group_id);

COMMENT ON TABLE email_import_failure_groups IS
  'De-duplicates recurring import errors by signature. Auto-creates GitHub issue at occurrence_count >= 3.';
