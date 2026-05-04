# Production deployment notes

The migrations in this directory run inside transactions managed by the Supabase
migration runner. This means `CREATE INDEX CONCURRENTLY` is not directly usable
from migration files (it cannot run inside a transaction).

## Indexes added on populated tables

The following indexes were added by the email-sync-job-management work
(`20260501*.sql`). On dev/staging they're fine — tables are small. On a
production database with a populated `emails` or `email_import_errors`,
the non-concurrent `CREATE INDEX` will hold a `SHARE` lock that blocks writes
for the duration of the build.

| Index | Table | Migration |
|-------|-------|-----------|
| `idx_emails_enrichment_pending` | `emails` | `20260502130000_emails_enrichment_status.sql` |
| `idx_emails_mailbox_status` | `emails` | `20260502130000_emails_enrichment_status.sql` |
| `idx_emails_created_at_desc` | `emails` | `20260502130000_emails_enrichment_status.sql` |
| `idx_email_import_errors_class` | `email_import_errors` | `20260502130400_email_import_errors_class.sql` |
| `idx_email_import_errors_message_id` | `email_import_errors` | `20260502130400_email_import_errors_class.sql` |
| `idx_email_import_errors_group` | `email_import_errors` | `20260502130300_email_import_failure_groups.sql` |

## Recommended production deploy procedure

Before merging this work to production, run the index creation manually via
`psql` outside the migration transaction. The `IF NOT EXISTS` clauses in the
migrations will turn the in-migration creates into no-ops if the indexes
already exist.

```sql
-- Run these one at a time in a psql session against the prod database BEFORE
-- the migrations are applied. Each runs in its own implicit transaction (psql
-- autocommit), and CONCURRENTLY allows other writes during the build.

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_emails_enrichment_pending
  ON emails (created_at)
  WHERE enrichment_status = 'pending';

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_emails_mailbox_status
  ON emails (mailbox_id, enrichment_status);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_emails_created_at_desc
  ON emails (created_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_email_import_errors_class
  ON email_import_errors (error_class)
  WHERE resolved_at IS NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_email_import_errors_message_id
  ON email_import_errors (message_id)
  WHERE resolved_at IS NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_email_import_errors_group
  ON email_import_errors (failure_group_id);
```

To check that an index built successfully (CONCURRENTLY can leave behind an
INVALID index if interrupted):

```sql
SELECT relname, indisvalid
FROM pg_class c JOIN pg_index i ON i.indexrelid = c.oid
WHERE relname LIKE 'idx_emails_%' OR relname LIKE 'idx_email_import_errors_%';
```

Drop and re-create any that show `indisvalid = false`.

## Other production considerations for this feature

- The auto-report flow is driven from the email-sync Lambda via an
  EventBridge schedule (`mode: auto_report_failures`, every 15 min) — NOT
  from pg_cron. The Lambda already has `SUPABASE_SERVICE_ROLE_KEY` in its
  environment so no Postgres-level GUC is required. The previous
  `app.settings.supabase_url` / `app.settings.service_role_key` setup is
  obsolete.

- Supabase secrets that must be set before the corresponding edge functions
  work in production (push via `deploy.yml` from GH env secrets):
  - `GITHUB_PAT` (fine-grained PAT with Issues:write on `PD-Medical/ai-outreach-frontend`)
  - `GITHUB_REPO=PD-Medical/ai-outreach-frontend`
  - `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `ENVIRONMENT`
    for `apply-sync-concurrency` (IAM user must have the policy stored in the
    `/ai-outreach/<env>/edge-function-required-policy` SSM parameter).
