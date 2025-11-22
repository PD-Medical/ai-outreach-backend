-- Add LLM input/output and error tracking to ai_enrichment_logs
-- This provides visibility into what prompts are sent and responses received

-- Add new columns for detailed logging
ALTER TABLE ai_enrichment_logs
ADD COLUMN IF NOT EXISTS prompt_text TEXT,
ADD COLUMN IF NOT EXISTS response_text TEXT,
ADD COLUMN IF NOT EXISTS error_message TEXT,
ADD COLUMN IF NOT EXISTS email_ids UUID[],
ADD COLUMN IF NOT EXISTS contact_ids UUID[];

-- Add index for error lookup
CREATE INDEX IF NOT EXISTS idx_ai_logs_has_error
ON ai_enrichment_logs (created_at DESC)
WHERE error_message IS NOT NULL;

-- Comment on columns
COMMENT ON COLUMN ai_enrichment_logs.prompt_text IS 'The full prompt sent to the LLM';
COMMENT ON COLUMN ai_enrichment_logs.response_text IS 'The raw LLM response (before parsing)';
COMMENT ON COLUMN ai_enrichment_logs.error_message IS 'Error message if enrichment failed';
COMMENT ON COLUMN ai_enrichment_logs.email_ids IS 'Array of email UUIDs processed in this batch';
COMMENT ON COLUMN ai_enrichment_logs.contact_ids IS 'Array of contact UUIDs updated in this batch';
