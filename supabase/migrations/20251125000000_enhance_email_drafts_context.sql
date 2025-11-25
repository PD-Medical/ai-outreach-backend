-- Migration: Enhance email_drafts for database-driven HITL
-- Stores full context for redraft support without LangGraph checkpointing

-- Store full LLM conversation history for debugging and redraft context
ALTER TABLE email_drafts
ADD COLUMN IF NOT EXISTS llm_conversation_history jsonb DEFAULT '[]';

COMMENT ON COLUMN email_drafts.llm_conversation_history IS
'Full LLM conversation history including tool calls and responses for context retention across redrafts';

-- Store LLM reasoning explanation for why this draft was created
ALTER TABLE email_drafts
ADD COLUMN IF NOT EXISTS generation_reasoning text;

COMMENT ON COLUMN email_drafts.generation_reasoning IS
'LLM reasoning/explanation for draft content decisions';

-- Store tool call results (contact info, products, thread) gathered during generation
ALTER TABLE email_drafts
ADD COLUMN IF NOT EXISTS gathered_context jsonb DEFAULT '{}';

COMMENT ON COLUMN email_drafts.gathered_context IS
'Results from tool calls (contact info, product info, thread history) gathered during draft generation';

-- Store original request parameters for redraft capability
ALTER TABLE email_drafts
ADD COLUMN IF NOT EXISTS request_params jsonb DEFAULT '{}';

COMMENT ON COLUMN email_drafts.request_params IS
'Original parameters from workflow-executor invocation, used for redraft';

-- Index for version chain queries (find all drafts in a redraft chain)
CREATE INDEX IF NOT EXISTS idx_email_drafts_previous_draft
ON email_drafts(previous_draft_id) WHERE previous_draft_id IS NOT NULL;
