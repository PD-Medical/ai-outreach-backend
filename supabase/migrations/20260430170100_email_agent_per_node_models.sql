-- ============================================================================
-- system_config — per-node model config for the email-agent LangGraph
-- ============================================================================
-- The plan→draft→review state machine lets each node use a different LLM.
-- Configurable via system_config; falls back to default_llm_model if a
-- per-node key is absent.
--
-- Lambda code (functions/email-agent/nodes.py) reads these keys via the
-- existing system_config helper. Default values mirror the current
-- DEFAULT_LLM_MODEL (deepseek/deepseek-v3.2) so behavior is unchanged
-- until the team explicitly tunes per node.
-- ============================================================================

INSERT INTO public.system_config (key, value, description) VALUES
    ('email_agent_plan_model', '"deepseek/deepseek-v3.2"'::jsonb,
     'LLM model for the email-agent plan node (judges skip / draft / info_insufficient and produces sequenced steps + compliance checklist).'),
    ('email_agent_draft_model', '"deepseek/deepseek-v3.2"'::jsonb,
     'LLM model for the email-agent draft node (writes prose per plan step + persona).'),
    ('email_agent_review_model', '"deepseek/deepseek-v3.2"'::jsonb,
     'LLM model for the email-agent review node (judges approve / revise / reject against the plan compliance checklist + step coverage).')
ON CONFLICT (key) DO NOTHING;

COMMENT ON COLUMN public.system_config.key IS
    'System config key. email_agent_{plan,draft,review}_model entries control per-node model selection in the email-agent LangGraph; absence falls back to default_llm_model.';
