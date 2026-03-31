-- ============================================================================
-- SYSTEM CONFIG: Workflow matcher confidence thresholds
-- Controls how many workflow matches are allowed per email (issue #88)
-- ============================================================================

INSERT INTO system_config (key, value, description) VALUES
  ('min_match_confidence', '0.80'::jsonb, 'Minimum confidence score for a workflow match to be accepted. Matches below this are always dropped.'),
  ('high_confidence_threshold', '0.95'::jsonb, 'When the top match exceeds this threshold, gap-based filtering is applied to keep only close competitors.'),
  ('confidence_gap', '0.05'::jsonb, 'In high-confidence mode, matches must be within this gap of the top match to be kept.'),
  ('single_workflow_mode', 'false'::jsonb, 'When true, only the highest-confidence workflow match runs per email. When false, multiple matches are allowed.')
ON CONFLICT (key) DO NOTHING;
