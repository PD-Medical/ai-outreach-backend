-- 20260501012500_failure_grouping_fn.sql
CREATE OR REPLACE FUNCTION match_or_create_failure_group(
  p_error_signature TEXT,
  p_error_pattern TEXT
) RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_group_id UUID;
BEGIN
  INSERT INTO email_import_failure_groups (error_signature, error_pattern)
  VALUES (p_error_signature, p_error_pattern)
  ON CONFLICT (error_signature) DO UPDATE
    SET last_seen_at = now(),
        occurrence_count = email_import_failure_groups.occurrence_count + 1,
        -- If a previously resolved group recurs, clear resolved_at so it surfaces again
        resolved_at = NULL
  RETURNING id INTO v_group_id;

  RETURN v_group_id;
END;
$$;

GRANT EXECUTE ON FUNCTION match_or_create_failure_group(TEXT, TEXT)
  TO service_role;
