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

-- Register the model config so it appears in the Control Center UI alongside the
-- other LLM model settings. Editable via /settings/control-center at runtime.
INSERT INTO public.system_config (key, value, description) VALUES
  (
    'persona_learning_model',
    '"deepseek/deepseek-v3.2"'::jsonb,
    'LLM model used to extract writing-voice profiles from a mailbox''s past sent emails. '
    'Editable via the Control Center. Benefits from a strong reasoning model — Claude or '
    'GPT-4o tier recommended for production.'
  )
ON CONFLICT (key) DO NOTHING;
