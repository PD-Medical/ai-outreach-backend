-- ============================================================================
-- TRAINING ANALYTICS: Aggregate confidence scores on sessions
-- ============================================================================

-- Add aggregate confidence columns to training sessions
ALTER TABLE public.email_training_sessions
  ADD COLUMN IF NOT EXISTS avg_revised_confidence NUMERIC(3,2),
  ADD COLUMN IF NOT EXISTS avg_generation_confidence NUMERIC(3,2);

-- View for confidence trend chart (only completed sessions)
CREATE OR REPLACE VIEW public.v_training_confidence_trend AS
SELECT
  id,
  mode,
  status,
  batch_size,
  completed_count,
  avg_generation_confidence,
  avg_revised_confidence,
  created_at,
  learning_completed_at
FROM public.email_training_sessions
WHERE status = 'learning_complete'
ORDER BY created_at;
