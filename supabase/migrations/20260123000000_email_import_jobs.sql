-- ============================================================================
-- Email Import Jobs Table
-- Tracks long-running email import jobs with SQS-based batch processing
-- ============================================================================

CREATE TABLE public.email_import_jobs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    mailbox_id uuid NOT NULL REFERENCES mailboxes(id) ON DELETE CASCADE,

    -- Configuration
    config jsonb NOT NULL DEFAULT '{}'::jsonb,
    -- {
    --   "import_since": "2024-01-01",  -- ISO date OR
    --   "days_back": 90,               -- OR
    --   "months_back": 3,
    --   "max_emails": 10000,           -- null = unlimited
    --   "folders": ["INBOX", "INBOX.Sent"],
    --   "skip_existing": true
    -- }

    -- Status: pending | running | paused | completed | failed | cancelled
    status varchar NOT NULL DEFAULT 'pending',

    -- Progress tracking (updated atomically by RPC)
    progress jsonb NOT NULL DEFAULT '{}'::jsonb,
    -- {
    --   "total_estimated": 5000,
    --   "total_batches": 100,
    --   "batches_completed": 0,
    --   "processed": 0,
    --   "imported": 0,
    --   "skipped": 0,
    --   "errors": 0
    -- }

    -- Errors
    last_error text,
    error_count integer DEFAULT 0,

    -- Timestamps
    created_at timestamptz DEFAULT now(),
    started_at timestamptz,
    completed_at timestamptz,
    updated_at timestamptz DEFAULT now(),
    created_by uuid REFERENCES auth.users(id),

    CONSTRAINT status_check CHECK (status IN ('pending', 'running', 'paused', 'completed', 'failed', 'cancelled'))
);

-- Indexes
CREATE INDEX idx_import_jobs_mailbox ON email_import_jobs(mailbox_id);
CREATE INDEX idx_import_jobs_status ON email_import_jobs(status) WHERE status IN ('pending', 'running');
CREATE INDEX idx_import_jobs_created_by ON email_import_jobs(created_by);

-- Updated at trigger
CREATE TRIGGER set_email_import_jobs_updated_at
    BEFORE UPDATE ON email_import_jobs
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- RLS
ALTER TABLE email_import_jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their import jobs"
    ON email_import_jobs FOR SELECT
    USING (auth.uid() = created_by);

CREATE POLICY "Users can create import jobs"
    ON email_import_jobs FOR INSERT
    WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Users can update their import jobs"
    ON email_import_jobs FOR UPDATE
    USING (auth.uid() = created_by);

CREATE POLICY "Service role has full access to import jobs"
    ON email_import_jobs FOR ALL
    USING (auth.role() = 'service_role');

-- View for UI with progress percentage
CREATE VIEW v_email_import_jobs_summary AS
SELECT
    j.*,
    m.email as mailbox_email,
    m.name as mailbox_name,
    CASE
        WHEN COALESCE((j.progress->>'total_estimated')::int, 0) > 0
        THEN ROUND(100.0 * COALESCE((j.progress->>'processed')::int, 0) / (j.progress->>'total_estimated')::int, 1)
        ELSE 0
    END as progress_percent,
    COALESCE((j.progress->>'batches_completed')::int, 0) as batches_completed,
    COALESCE((j.progress->>'total_batches')::int, 0) as total_batches
FROM email_import_jobs j
JOIN mailboxes m ON j.mailbox_id = m.id;

-- ============================================================================
-- Atomic Progress Increment RPC
-- Used by Lambda to safely update progress counters from concurrent batches
-- ============================================================================

CREATE OR REPLACE FUNCTION increment_import_job_progress(
    p_job_id uuid,
    p_processed int DEFAULT 0,
    p_imported int DEFAULT 0,
    p_skipped int DEFAULT 0,
    p_errors int DEFAULT 0
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result json;
    v_new_batches_completed int;
    v_total_batches int;
BEGIN
    -- Calculate new values and check completion
    UPDATE email_import_jobs
    SET
        progress = jsonb_set(
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
        'completed_at', completed_at
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- Grant execute permission to service role
GRANT EXECUTE ON FUNCTION increment_import_job_progress TO service_role;

-- ============================================================================
-- Helper function to update job status
-- ============================================================================

CREATE OR REPLACE FUNCTION update_import_job_status(
    p_job_id uuid,
    p_status varchar,
    p_error text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result json;
BEGIN
    UPDATE email_import_jobs
    SET
        status = p_status,
        last_error = COALESCE(p_error, last_error),
        error_count = CASE WHEN p_error IS NOT NULL THEN error_count + 1 ELSE error_count END,
        started_at = CASE WHEN p_status = 'running' AND started_at IS NULL THEN now() ELSE started_at END,
        completed_at = CASE WHEN p_status IN ('completed', 'failed', 'cancelled') THEN now() ELSE completed_at END,
        updated_at = now()
    WHERE id = p_job_id
    RETURNING json_build_object(
        'id', id,
        'status', status,
        'error_count', error_count
    ) INTO v_result;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION update_import_job_status TO service_role;

-- ============================================================================
-- Initialize job progress (called by import_init mode)
-- ============================================================================

CREATE OR REPLACE FUNCTION initialize_import_job_progress(
    p_job_id uuid,
    p_total_estimated int,
    p_total_batches int
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result json;
BEGIN
    UPDATE email_import_jobs
    SET
        status = 'running',
        started_at = now(),
        progress = jsonb_build_object(
            'total_estimated', p_total_estimated,
            'total_batches', p_total_batches,
            'batches_completed', 0,
            'processed', 0,
            'imported', 0,
            'skipped', 0,
            'errors', 0
        ),
        updated_at = now()
    WHERE id = p_job_id
    RETURNING json_build_object(
        'id', id,
        'status', status,
        'progress', progress
    ) INTO v_result;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION initialize_import_job_progress TO service_role;
