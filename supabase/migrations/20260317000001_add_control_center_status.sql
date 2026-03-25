-- Migration: Add get_control_center_status RPC function
-- Purpose: Control Center page needs live counts instead of hardcoded values

CREATE OR REPLACE FUNCTION public.get_control_center_status()
RETURNS JSON
LANGUAGE sql SECURITY DEFINER STABLE
AS $$
  SELECT json_build_object(
    'active_workflows', (SELECT count(*) FROM public.workflows WHERE is_active = true),
    'active_campaigns', (SELECT count(*) FROM public.campaign_sequences WHERE status = 'active'),
    'pending_approvals', (SELECT count(*) FROM public.email_drafts WHERE approval_status = 'pending'),
    'notifications_enabled', true
  );
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.get_control_center_status() TO authenticated;
