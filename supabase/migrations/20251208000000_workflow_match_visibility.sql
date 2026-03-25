-- Migration: Add workflow match visibility columns
-- Purpose: Store match_confidence and match_reasoning from workflow-matcher Lambda
-- This enables users to see WHY a workflow matched an email

-- Add match visibility columns to workflow_executions
ALTER TABLE workflow_executions
ADD COLUMN IF NOT EXISTS match_confidence DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS match_reasoning TEXT;

-- Add comments for documentation
COMMENT ON COLUMN workflow_executions.match_confidence IS 'AI confidence score (0-1) for why this workflow matched the email';
COMMENT ON COLUMN workflow_executions.match_reasoning IS 'AI explanation of why this workflow matched the email';

-- Create index for filtering by match confidence (useful for debugging low-confidence matches)
CREATE INDEX IF NOT EXISTS idx_workflow_executions_match_confidence
ON workflow_executions(match_confidence)
WHERE match_confidence IS NOT NULL;
