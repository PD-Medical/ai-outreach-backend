-- ============================================================================
-- Add Email Import Errors Table for Retry Logic
-- ============================================================================
-- This migration adds a table to track failed email imports for later retry.
-- This addresses the issue where failed emails are permanently skipped.
-- ============================================================================

-- Create email import errors table
CREATE TABLE IF NOT EXISTS public.email_import_errors (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  mailbox_id uuid NOT NULL,
  imap_folder character varying NOT NULL,
  imap_uid integer NOT NULL,
  message_id character varying,
  error_message text NOT NULL,
  error_type character varying NOT NULL
    CHECK (error_type::text = ANY (ARRAY[
      'parse_error'::character varying,
      'db_constraint'::character varying,
      'network_error'::character varying,
      'imap_error'::character varying,
      'validation_error'::character varying,
      'timeout_error'::character varying,
      'unknown_error'::character varying
    ]::text[])),
  retry_count integer DEFAULT 0,
  last_attempt_at timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  resolved_at timestamp with time zone,

  CONSTRAINT email_import_errors_pkey PRIMARY KEY (id),
  CONSTRAINT email_import_errors_mailbox_id_fkey
    FOREIGN KEY (mailbox_id)
    REFERENCES public.mailboxes(id) ON DELETE CASCADE,

  -- Prevent duplicate error records for same email
  CONSTRAINT email_import_errors_unique UNIQUE (mailbox_id, imap_folder, imap_uid)
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_email_import_errors_mailbox_folder
ON public.email_import_errors(mailbox_id, imap_folder);

CREATE INDEX IF NOT EXISTS idx_email_import_errors_retry
ON public.email_import_errors(retry_count, last_attempt_at)
WHERE resolved_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_email_import_errors_created_at
ON public.email_import_errors(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_email_import_errors_resolved
ON public.email_import_errors(resolved_at)
WHERE resolved_at IS NOT NULL;

-- Add RLS policies if needed (assuming RLS is enabled)
-- ALTER TABLE public.email_import_errors ENABLE ROW LEVEL SECURITY;

-- Grant permissions
GRANT ALL ON public.email_import_errors TO authenticated;
GRANT ALL ON public.email_import_errors TO service_role;

-- Add comments
COMMENT ON TABLE public.email_import_errors IS 'Tracks failed email imports for retry logic';
COMMENT ON COLUMN public.email_import_errors.mailbox_id IS 'Reference to the mailbox where import failed';
COMMENT ON COLUMN public.email_import_errors.imap_folder IS 'IMAP folder where the email resides';
COMMENT ON COLUMN public.email_import_errors.imap_uid IS 'IMAP UID of the failed email';
COMMENT ON COLUMN public.email_import_errors.message_id IS 'Email Message-ID header (if available)';
COMMENT ON COLUMN public.email_import_errors.error_message IS 'Detailed error message from the failed import';
COMMENT ON COLUMN public.email_import_errors.error_type IS 'Categorized error type for filtering and reporting';
COMMENT ON COLUMN public.email_import_errors.retry_count IS 'Number of retry attempts made';
COMMENT ON COLUMN public.email_import_errors.last_attempt_at IS 'Timestamp of the last retry attempt';
COMMENT ON COLUMN public.email_import_errors.resolved_at IS 'Timestamp when the error was resolved (email successfully imported)';
COMMENT ON CONSTRAINT email_import_errors_unique ON public.email_import_errors IS 'Ensures only one error record per email UID';
