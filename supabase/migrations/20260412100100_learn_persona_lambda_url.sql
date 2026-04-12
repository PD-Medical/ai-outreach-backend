-- Register a placeholder for the learn-persona Lambda URL in system_config.
-- The actual URL must be populated manually after the first SAM deploy of
-- ai-outreach-lambda (the deploy workflow does not currently write Lambda
-- Function URLs back into system_config — same flow as `email_agent_url`).
--
-- To populate after deploy:
--   UPDATE system_config
--   SET value = '"https://<learn-persona-lambda-function-url>/"'::jsonb
--   WHERE key = 'learn_persona_url';

INSERT INTO public.system_config (key, value, description) VALUES
  (
    'learn_persona_url',
    'null'::jsonb,
    'Lambda Function URL for learn-persona. Populated manually after SAM deploy.'
  )
ON CONFLICT (key) DO NOTHING;
