-- Migration: Add get_current_user_profile RPC function
-- Purpose: Frontend sidebar and settings need full_name + role for current user
-- The existing get_current_user_role() only returns role as TEXT

CREATE OR REPLACE FUNCTION public.get_current_user_profile()
RETURNS TABLE(full_name text, role text)
LANGUAGE sql SECURITY DEFINER STABLE
AS $$
  SELECT p.full_name, p.role::text
  FROM public.profiles p
  WHERE p.auth_user_id = auth.uid()
  LIMIT 1;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.get_current_user_profile() TO authenticated;
