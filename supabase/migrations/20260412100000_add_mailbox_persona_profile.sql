-- Add structured persona profile to mailboxes
-- Populated by the learn-persona Lambda from a mailbox's own sent-email corpus.
-- `persona_description` remains as a manual-override / fallback text field.

ALTER TABLE public.mailboxes
  ADD COLUMN IF NOT EXISTS persona_profile jsonb,
  ADD COLUMN IF NOT EXISTS persona_profile_learned_at timestamptz;

COMMENT ON COLUMN public.mailboxes.persona_profile IS
  'Abstract writing-style profile learned from past sent emails. Structured voice/tone/pattern data, not content. See ai-outreach-lambda/functions/learn-persona for the schema.';

COMMENT ON COLUMN public.mailboxes.persona_profile_learned_at IS
  'Timestamp of the most recent persona learning run. NULL if never learned.';
