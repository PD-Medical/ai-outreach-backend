-- 20260502130800_v_email_activity.sql
-- Joined view used by the Activity log in the UI.
-- Adjust column selection if your `emails` table has different fields.
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
  -- Latest workflow execution against this email, if any
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
  -- Latest unresolved import error, if any
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
LEFT JOIN mailboxes m ON m.id = e.mailbox_id;

GRANT SELECT ON v_email_activity TO service_role;
