-- 20260511030000_v_email_activity_union_import_errors.sql
-- Unify the Activity log so the UI's "Failed" tab can show both
--   (a) emails that DID land but failed enrichment (enrichment_status='failed'), and
--   (b) emails that NEVER landed because the import itself errored
--       (rows in email_import_errors with no matching emails row).
--
-- Previously (b) was invisible in v_email_activity because the view
-- joined FROM emails only. We add a UNION ALL leg over unresolved
-- email_import_errors rows with no successor email, exposing them with
-- a synthetic enrichment_status = 'import_failed'. The edge function
-- maps the UI's 'failed' tab to enrichment_status IN ('failed','import_failed').

CREATE OR REPLACE VIEW v_email_activity
WITH (security_invoker = true) AS
SELECT
  e.id,
  e.mailbox_id,
  m.email AS mailbox_email,
  m.name AS mailbox_name,
  e.from_email AS from_address,
  e.from_name,
  e.subject,
  e.imap_folder,
  e.imap_uid,
  e.received_at,
  e.created_at AS imported_at,
  e.enrichment_status,
  e.enriched_at,
  (
    SELECT json_build_object(
      'workflow_id', we.workflow_id,
      'workflow_name', w.name,
      'status', we.status,
      'matched_at', we.started_at
    )
    FROM workflow_executions we
    LEFT JOIN workflows w ON w.id = we.workflow_id
    WHERE we.email_id = e.id
    ORDER BY we.started_at DESC
    LIMIT 1
  ) AS latest_workflow,
  (
    SELECT json_build_object(
      'error_id', err.id,
      'error_class', err.error_class,
      'error_message', err.error_message,
      'failure_group_id', err.failure_group_id
    )
    FROM email_import_errors err
    WHERE err.message_id = e.message_id
      AND err.resolved_at IS NULL
    ORDER BY err.created_at DESC
    LIMIT 1
  ) AS latest_error
FROM emails e
LEFT JOIN mailboxes m ON m.id = e.mailbox_id

UNION ALL

-- Import errors that never produced an email row. We synthesise an
-- activity row from the error itself so the UI Failed tab sees them.
SELECT
  err.id,
  err.mailbox_id,
  m.email AS mailbox_email,
  m.name AS mailbox_name,
  NULL::text AS from_address,
  NULL::text AS from_name,
  NULL::text AS subject,
  err.imap_folder,
  err.imap_uid,
  NULL::timestamptz AS received_at,
  err.created_at AS imported_at,
  'import_failed'::text AS enrichment_status,
  NULL::timestamptz AS enriched_at,
  NULL::json AS latest_workflow,
  json_build_object(
    'error_id', err.id,
    'error_class', err.error_class,
    'error_message', err.error_message,
    'failure_group_id', err.failure_group_id
  ) AS latest_error
FROM email_import_errors err
LEFT JOIN mailboxes m ON m.id = err.mailbox_id
WHERE err.resolved_at IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM emails e2
    WHERE e2.message_id = err.message_id
      AND err.message_id IS NOT NULL
  );

GRANT SELECT ON v_email_activity TO service_role;

COMMENT ON VIEW v_email_activity IS
  'Activity log: emails (left) UNION ALL unresolved import errors that never produced an email (right, status=import_failed). Powers the UI Activity page filter tabs.';
