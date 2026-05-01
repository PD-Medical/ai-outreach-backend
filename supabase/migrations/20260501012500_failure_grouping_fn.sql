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
  -- Try to find existing unresolved group
  SELECT id INTO v_group_id
  FROM email_import_failure_groups
  WHERE error_signature = p_error_signature
    AND resolved_at IS NULL;

  IF v_group_id IS NULL THEN
    INSERT INTO email_import_failure_groups (error_signature, error_pattern)
    VALUES (p_error_signature, p_error_pattern)
    RETURNING id INTO v_group_id;
  ELSE
    UPDATE email_import_failure_groups
    SET last_seen_at = now(),
        occurrence_count = occurrence_count + 1
    WHERE id = v_group_id;
  END IF;

  RETURN v_group_id;
END;
$$;

GRANT EXECUTE ON FUNCTION match_or_create_failure_group(TEXT, TEXT)
  TO service_role;
