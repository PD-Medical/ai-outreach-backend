-- ============================================================================
-- Train B — RPC dedup for at-least-once batch delivery
-- ============================================================================
-- Train B routes UI-triggered bulk imports through a NEW Standard SQS queue
-- (email-import-bulk-${env}) for parallelism — see lambda PR
-- feat/bulk-import-standard-queue. Standard SQS is at-least-once, so the same
-- batch can be delivered twice. The lambda's process_email_from_imap_tools is
-- already idempotent on the email row (emails_unique_imap), but the
-- email_import_jobs.progress counter would double-increment without dedup.
--
-- Add p_batch_index parameter. Track processed batch indices in
-- progress.processed_batches as a JSONB array. Skip the increment if the
-- batch_index is already there. The lambda passes batch_index unconditionally;
-- legacy callers that don't pass it (FIFO cron path) keep the old behavior
-- via NULL default — no dedup, increment normally.
--
-- Forward-compatible: cron-sync flow (non-bulk) doesn't pass p_batch_index, so
-- it falls through to the existing increment logic. Only the new bulk-import
-- flow benefits from the dedup.
-- ============================================================================

BEGIN;

-- Drop the prior 5-arg signature so callers that don't yet pass p_batch_index
-- pick up the new function via NULL default (forward-compatible). Without
-- this DROP, Postgres keeps both signatures and resolves on argument count —
-- legacy callers would silently keep the no-dedup behavior even after
-- redeploy, which is fine but invites confusion.
DROP FUNCTION IF EXISTS increment_import_job_progress(uuid, int, int, int, int);

CREATE OR REPLACE FUNCTION increment_import_job_progress(
    p_job_id uuid,
    p_processed int DEFAULT 0,
    p_imported int DEFAULT 0,
    p_skipped int DEFAULT 0,
    p_errors int DEFAULT 0,
    p_batch_index int DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result json;
    v_already_processed boolean := false;
    v_processed_batches jsonb;
BEGIN
    -- Dedup gate: only when p_batch_index is provided AND the batch is already
    -- in progress.processed_batches. Read-only check; doesn't take a write lock.
    IF p_batch_index IS NOT NULL THEN
        SELECT COALESCE(progress->'processed_batches', '[]'::jsonb)
          INTO v_processed_batches
          FROM email_import_jobs
         WHERE id = p_job_id;

        IF v_processed_batches @> to_jsonb(p_batch_index) THEN
            v_already_processed := true;
        END IF;
    END IF;

    IF v_already_processed THEN
        -- Return current state without applying deltas — caller treats success.
        SELECT json_build_object(
            'id', id,
            'status', status,
            'progress', progress,
            'completed_at', completed_at,
            'duplicate_batch', true
        ) INTO v_result
        FROM email_import_jobs
        WHERE id = p_job_id;
        RETURN v_result;
    END IF;

    -- Apply increments + record the batch index in processed_batches when given.
    -- Single UPDATE so the read-then-write is atomic per row.
    UPDATE email_import_jobs
    SET
        progress = jsonb_set(
            jsonb_set(
                jsonb_set(
                    jsonb_set(
                        jsonb_set(
                            jsonb_set(
                                progress,
                                '{processed}',
                                to_jsonb(COALESCE((progress->>'processed')::int, 0) + p_processed)
                            ),
                            '{imported}',
                            to_jsonb(COALESCE((progress->>'imported')::int, 0) + p_imported)
                        ),
                        '{skipped}',
                        to_jsonb(COALESCE((progress->>'skipped')::int, 0) + p_skipped)
                    ),
                    '{errors}',
                    to_jsonb(COALESCE((progress->>'errors')::int, 0) + p_errors)
                ),
                '{batches_completed}',
                to_jsonb(COALESCE((progress->>'batches_completed')::int, 0) + 1)
            ),
            '{processed_batches}',
            CASE
                WHEN p_batch_index IS NULL THEN COALESCE(progress->'processed_batches', '[]'::jsonb)
                ELSE COALESCE(progress->'processed_batches', '[]'::jsonb) || to_jsonb(p_batch_index)
            END
        ),
        updated_at = now(),
        -- Auto-complete when all batches done
        status = CASE
            WHEN COALESCE((progress->>'batches_completed')::int, 0) + 1 >=
                 COALESCE((progress->>'total_batches')::int, 1)
            THEN 'completed'
            ELSE status
        END,
        completed_at = CASE
            WHEN COALESCE((progress->>'batches_completed')::int, 0) + 1 >=
                 COALESCE((progress->>'total_batches')::int, 1)
            THEN now()
            ELSE completed_at
        END
    WHERE id = p_job_id
    RETURNING json_build_object(
        'id', id,
        'status', status,
        'progress', progress,
        'completed_at', completed_at,
        'duplicate_batch', false
    ) INTO v_result;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION increment_import_job_progress(uuid, int, int, int, int, int)
  TO service_role;

COMMIT;
