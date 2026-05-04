-- ============================================================================
-- Train C — Decoupled enrichment queue: config knobs
-- ============================================================================
-- Train C moves enrichment off the import critical path. Import lambda
-- enqueues 1 SQS message per inserted email; a separate event source mapping
-- with BatchSize=5 + MaximumConcurrency=25 drains the queue, calling
-- enrich_emails_batch with 5 emails per LLM call.
--
-- Two knobs:
--
-- 1. email_sync.enrichment_via_queue (kill-switch)
--    When 'true', import lambda enqueues to email-enrichment-${env}.
--    When 'false', falls back to inline enrichment (pre-Train-C behavior).
--    The lambda code reads this with a default of 'false' when the row is
--    missing — safe-by-default if this migration ships before the lambda PR.
--
-- 2. email_sync.enrichment_batch_size
--    Max emails per LLM enrichment call. Drives both the queue's BatchSize
--    event-source attribute (read at deploy via SAM/template, not from DB)
--    and the LLM prompt batching inside enrich_emails_batch. Five emails per
--    call is the Goldilocks point: cheaper than 1-per (current inline path)
--    and higher per-email classification quality than 20-per (current cron
--    path).
--
-- No schema changes; just system_config inserts. ON CONFLICT DO NOTHING so
-- the migration is idempotent and re-applies cleanly.
-- ============================================================================

INSERT INTO public.system_config (key, value, description)
VALUES
  (
    'email_sync.enrichment_via_queue',
    'true'::jsonb,
    'Train C kill-switch. When true, import lambda enqueues each email to '
    'the email-enrichment SQS queue for async batched enrichment. When false, '
    'import lambda falls back to inline per-email enrichment. Flip to false '
    'to disable queue path without redeploy.'
  ),
  (
    'email_sync.enrichment_batch_size',
    '5'::jsonb,
    'Max emails per LLM enrichment call in the queue path. Five emails per '
    'call balances cost (vs 1-per inline) against per-email classification '
    'quality (vs 20-per cron). Should match the EventSourceMapping BatchSize '
    'in template.yaml; mismatch is harmless (smaller of the two wins).'
  )
ON CONFLICT (key) DO NOTHING;
