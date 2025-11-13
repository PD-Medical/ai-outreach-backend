-- Function to update conversation statistics
-- This is called after each email insert to keep conversation stats accurate

CREATE OR REPLACE FUNCTION public.update_conversation_stats(p_conversation_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_email_count INTEGER;
  v_first_email_at TIMESTAMPTZ;
  v_last_email_at TIMESTAMPTZ;
  v_last_direction TEXT;
BEGIN
  -- Get conversation statistics from emails
  SELECT 
    COUNT(*),
    MIN(received_at),
    MAX(received_at),
    (ARRAY_AGG(direction ORDER BY received_at DESC))[1]
  INTO 
    v_email_count,
    v_first_email_at,
    v_last_email_at,
    v_last_direction
  FROM public.emails
  WHERE conversation_id = p_conversation_id
    AND is_deleted = FALSE;

  -- Update conversation with calculated stats
  UPDATE public.conversations
  SET 
    email_count = COALESCE(v_email_count, 0),
    first_email_at = v_first_email_at,
    last_email_at = v_last_email_at,
    last_email_direction = v_last_direction,
    requires_response = (v_last_direction = 'incoming'),
    updated_at = NOW()
  WHERE id = p_conversation_id;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.update_conversation_stats(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_conversation_stats(UUID) TO service_role;

COMMENT ON FUNCTION public.update_conversation_stats(UUID) IS 
'Updates conversation statistics (email_count, first/last email times, etc.) based on associated emails. Called after email insert/update/delete.';


