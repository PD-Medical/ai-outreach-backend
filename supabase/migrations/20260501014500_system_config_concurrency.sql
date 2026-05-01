-- 20260501014500_system_config_concurrency.sql
INSERT INTO system_config (key, value, description)
VALUES (
  'email_sync.max_concurrent_lambdas',
  '25',
  'Cap on concurrent SQS-driven Lambda invocations. Reflected to the SQS event source mapping ScalingConfig.MaximumConcurrency by apply-sync-concurrency edge function.'
)
ON CONFLICT (key) DO NOTHING;
