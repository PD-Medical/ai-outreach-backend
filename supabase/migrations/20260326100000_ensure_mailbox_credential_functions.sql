-- ============================================================================
-- ENSURE MAILBOX CREDENTIAL FUNCTIONS EXIST
-- These were in the consolidated schema but may be missing on some environments
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_mailbox_password(p_mailbox_id uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'vault'
    AS $$
DECLARE
    v_secret_name text;
    v_password text;
BEGIN
    IF auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized: Service role required';
    END IF;

    v_secret_name := 'mailbox_password_' || p_mailbox_id::text;

    SELECT decrypted_secret INTO v_password
    FROM vault.decrypted_secrets
    WHERE name = v_secret_name;

    RETURN v_password;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_mailbox_credentials(p_mailbox_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_mailbox record;
    v_password text;
BEGIN
    IF auth.role() != 'service_role' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Service role required');
    END IF;

    SELECT * INTO v_mailbox FROM mailboxes WHERE id = p_mailbox_id;

    IF v_mailbox.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Mailbox not found');
    END IF;

    v_password := public.get_mailbox_password(p_mailbox_id);

    RETURN jsonb_build_object(
        'success', true,
        'mailbox_id', v_mailbox.id,
        'email', v_mailbox.email,
        'imap_host', v_mailbox.imap_host,
        'imap_port', v_mailbox.imap_port,
        'imap_username', COALESCE(v_mailbox.imap_username, v_mailbox.email),
        'password', v_password
    );
END;
$$;
