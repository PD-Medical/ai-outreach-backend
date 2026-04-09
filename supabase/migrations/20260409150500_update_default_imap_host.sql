ALTER TABLE public.mailboxes
ALTER COLUMN imap_host SET DEFAULT 'cp-wc01.iad01.ds.network';

CREATE OR REPLACE FUNCTION public.upsert_mailbox(
    p_id uuid DEFAULT NULL::uuid,
    p_email text DEFAULT NULL::text,
    p_name text DEFAULT NULL::text,
    p_type text DEFAULT 'personal'::text,
    p_imap_host text DEFAULT 'cp-wc01.iad01.ds.network'::text,
    p_imap_port integer DEFAULT 993,
    p_imap_username text DEFAULT NULL::text,
    p_password text DEFAULT NULL::text,
    p_is_active boolean DEFAULT true,
    p_persona_description text DEFAULT NULL::text,
    p_signature_html text DEFAULT NULL::text
) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
AS $$
DECLARE
    v_mailbox_id uuid;
    v_is_new boolean := false;
    v_result jsonb;
BEGIN
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

    IF p_id IS NULL AND (p_email IS NULL OR p_name IS NULL) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Email and name are required for new mailbox');
    END IF;

    IF p_email IS NOT NULL AND EXISTS (
        SELECT 1 FROM mailboxes WHERE email = p_email AND (p_id IS NULL OR id != p_id)
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'A mailbox with this email already exists');
    END IF;

    IF p_id IS NOT NULL THEN
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
            updated_at = NOW()
        WHERE id = p_id
        RETURNING id INTO v_mailbox_id;

        IF v_mailbox_id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'error', 'Mailbox not found');
        END IF;
    ELSE
        INSERT INTO mailboxes (email, name, type, imap_host, imap_port, imap_username, is_active, persona_description, signature_html)
        VALUES (p_email, p_name, p_type, p_imap_host, p_imap_port, p_imap_username, p_is_active, p_persona_description, p_signature_html)
        RETURNING id INTO v_mailbox_id;

        v_is_new := true;
    END IF;

    IF p_password IS NOT NULL THEN
        PERFORM set_config(
            format('app.imap_password_%s', replace(v_mailbox_id::text, '-', '_')),
            p_password,
            false
        );
    END IF;

    SELECT jsonb_build_object(
        'success', true,
        'mailbox_id', m.id,
        'is_new', v_is_new,
        'mailbox', jsonb_build_object(
            'id', m.id,
            'email', m.email,
            'name', m.name,
            'type', m.type,
            'imap_host', m.imap_host,
            'imap_port', m.imap_port,
            'imap_username', m.imap_username,
            'is_active', m.is_active,
            'persona_description', m.persona_description,
            'signature_html', m.signature_html,
            'created_at', m.created_at,
            'updated_at', m.updated_at
        )
    ) INTO v_result
    FROM mailboxes m
    WHERE m.id = v_mailbox_id;

    RETURN v_result;
END;
$$;
