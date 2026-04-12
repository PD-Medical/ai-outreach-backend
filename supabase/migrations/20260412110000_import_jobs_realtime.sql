-- Enable Supabase Realtime for email_import_jobs so the frontend gets
-- live progress updates via postgres_changes subscription.
-- Without this, the import dialog stays stuck at 0% because no change
-- events are emitted when the Lambda updates job progress.

ALTER PUBLICATION supabase_realtime ADD TABLE email_import_jobs;

-- REPLICA IDENTITY FULL is required so the Realtime system can broadcast
-- all column values (including progress JSONB) on UPDATE events.
ALTER TABLE email_import_jobs REPLICA IDENTITY FULL;
