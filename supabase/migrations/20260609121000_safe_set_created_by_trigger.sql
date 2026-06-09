-- Some legacy triggers attach set_created_by() to tables such as campaigns that
-- use auth_user_id rather than created_by. Make the shared trigger column-aware
-- so inserts do not fail on tables without created_by.

CREATE OR REPLACE FUNCTION public.set_created_by()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_patch jsonb := '{}'::jsonb;
BEGIN
  IF to_jsonb(NEW) ? 'created_by' THEN
    v_patch := v_patch || jsonb_build_object('created_by', auth.uid());
  END IF;

  IF to_jsonb(NEW) ? 'updated_at' THEN
    v_patch := v_patch || jsonb_build_object('updated_at', now());
  END IF;

  IF v_patch <> '{}'::jsonb THEN
    NEW := jsonb_populate_record(NEW, v_patch);
  END IF;

  RETURN NEW;
END;
$$;
