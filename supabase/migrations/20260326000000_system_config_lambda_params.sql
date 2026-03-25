-- ============================================================================
-- SYSTEM CONFIG: Lambda runtime parameters
-- Moves operational config from env vars to database for runtime control
-- ============================================================================

-- Email Sync
INSERT INTO system_config (key, value, description) VALUES
  ('email_sync_enabled', 'true'::jsonb, 'Kill switch for email sync Lambda. When false, sync invocations exit immediately.'),
  ('sync_schedule_rate', '"5 minutes"'::jsonb, 'EventBridge schedule rate expression for email sync.'),
  ('sync_batch_size', '50'::jsonb, 'Maximum emails to import per sync run per mailbox folder.'),
  ('sync_time_window_minutes', '60'::jsonb, 'Lookback window in minutes for initial sync when no last_synced_uid exists.'),
  ('retry_max_attempts', '3'::jsonb, 'Maximum retry attempts for failed email imports before giving up.'),
  ('retry_schedule_rate', '"30 minutes"'::jsonb, 'EventBridge schedule rate expression for retry errors.')
ON CONFLICT (key) DO NOTHING;

-- Enrichment
INSERT INTO system_config (key, value, description) VALUES
  ('enrichment_enabled', 'true'::jsonb, 'Toggle AI enrichment of imported emails.'),
  ('enrichment_batch_size', '20'::jsonb, 'Number of emails to enrich per batch during post-import enrichment.')
ON CONFLICT (key) DO NOTHING;

-- LLM Models
INSERT INTO system_config (key, value, description) VALUES
  ('default_llm_model', '"deepseek/deepseek-v3.2"'::jsonb, 'Default LLM model for workflow matching and general use.'),
  ('sql_agent_model', '"deepseek/deepseek-v3.2"'::jsonb, 'LLM model for campaign SQL agent.'),
  ('enrichment_default_model', '"deepseek/deepseek-v3.2"'::jsonb, 'LLM model for email enrichment.'),
  ('enrichment_summary_model', '"deepseek/deepseek-v3.2"'::jsonb, 'LLM model for conversation summary enrichment.'),
  ('training_model', '"deepseek/deepseek-v3.2"'::jsonb, 'LLM model for training self-learning.')
ON CONFLICT (key) DO NOTHING;
