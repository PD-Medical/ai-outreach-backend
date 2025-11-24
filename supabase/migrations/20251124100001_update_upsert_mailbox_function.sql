-- Update upsert_mailbox function to include persona_description and signature_html

-- Drop existing function (all overloads)
DROP FUNCTION IF EXISTS public.upsert_mailbox(uuid, text, text, text, text, integer, text, text, boolean);

CREATE OR REPLACE FUNCTION public.upsert_mailbox(
    p_id uuid DEFAULT NULL,
    p_email text DEFAULT NULL,
    p_name text DEFAULT NULL,
    p_type text DEFAULT 'personal',
    p_imap_host text DEFAULT 'mail.pdmedical.com.au',
    p_imap_port integer DEFAULT 993,
    p_imap_username text DEFAULT NULL,
    p_password text DEFAULT NULL,
    p_is_active boolean DEFAULT true,
    p_persona_description text DEFAULT NULL,
    p_signature_html text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_mailbox_id uuid;
    v_is_new boolean := false;
    v_result jsonb;
BEGIN
    -- Check admin permission
    IF NOT (
        auth.role() = 'service_role' OR
        EXISTS (
            SELECT 1 FROM profiles
            WHERE auth_user_id = auth.uid()
            AND role = 'admin'
        )
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Admin access required');
    END IF;

    -- Validate required fields for new mailbox
    IF p_id IS NULL AND (p_email IS NULL OR p_name IS NULL) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Email and name are required for new mailbox');
    END IF;

    -- Check for duplicate email
    IF p_email IS NOT NULL AND EXISTS (
        SELECT 1 FROM mailboxes WHERE email = p_email AND (p_id IS NULL OR id != p_id)
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'A mailbox with this email already exists');
    END IF;

    IF p_id IS NOT NULL THEN
        -- Update existing
        UPDATE mailboxes SET
            email = COALESCE(p_email, email),
            name = COALESCE(p_name, name),
            type = COALESCE(p_type, type),
            imap_host = COALESCE(p_imap_host, imap_host),
            imap_port = COALESCE(p_imap_port, imap_port),
            imap_username = COALESCE(p_imap_username, imap_username),
            is_active = COALESCE(p_is_active, is_active),
            persona_description = COALESCE(p_persona_description, persona_description),
            signature_html = COALESCE(p_signature_html, signature_html),
            updated_at = now()
        WHERE id = p_id
        RETURNING id INTO v_mailbox_id;

        IF v_mailbox_id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'error', 'Mailbox not found');
        END IF;
    ELSE
        -- Create new
        INSERT INTO mailboxes (email, name, type, imap_host, imap_port, imap_username, is_active, persona_description, signature_html)
        VALUES (p_email, p_name, p_type, p_imap_host, p_imap_port, p_imap_username, p_is_active, p_persona_description, p_signature_html)
        RETURNING id INTO v_mailbox_id;
        v_is_new := true;
    END IF;

    -- Store password if provided
    IF p_password IS NOT NULL AND p_password != '' THEN
        PERFORM public.store_mailbox_password(v_mailbox_id, p_password);
    END IF;

    SELECT jsonb_build_object(
        'success', true,
        'action', CASE WHEN v_is_new THEN 'created' ELSE 'updated' END,
        'mailbox', row_to_json(m)::jsonb
    ) INTO v_result
    FROM mailboxes m WHERE m.id = v_mailbox_id;

    RETURN v_result;
END;
$$;

-- Update permissions to include new parameters
GRANT EXECUTE ON FUNCTION public.upsert_mailbox(uuid, text, text, text, text, integer, text, text, boolean, text, text) TO authenticated;

-- Update comment
COMMENT ON FUNCTION public.upsert_mailbox IS 'Create or update mailbox with optional password, persona description, and signature HTML. Admin only.';
