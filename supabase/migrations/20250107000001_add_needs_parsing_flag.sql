-- ============================================================================
-- Add needs_parsing Flag for Large Emails
-- ============================================================================
-- This migration adds a flag to track emails that need parsing.
-- Large emails (>100KB) are stored with raw body to avoid CPU timeout during sync.
-- They can be parsed on-demand when viewed in the UI.
-- ============================================================================

-- Add flag to track emails that need parsing
ALTER TABLE public.emails 
ADD COLUMN needs_parsing boolean DEFAULT false;

-- Add index for efficient querying of emails that need parsing
CREATE INDEX idx_emails_needs_parsing 
ON public.emails(needs_parsing) 
WHERE needs_parsing = true;

-- Add comment
COMMENT ON COLUMN public.emails.needs_parsing IS 
'True if email body is stored raw and needs parsing (for large emails >100KB)';

