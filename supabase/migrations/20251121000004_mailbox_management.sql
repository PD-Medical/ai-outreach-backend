-- ===========================================
-- MAILBOX MANAGEMENT WITH SUPABASE VAULT
-- ===========================================
-- This migration adds:
-- 1. RLS policies for mailbox CRUD operations
-- 2. Functions to store/retrieve passwords using Supabase Vault
-- 3. Helper functions for mailbox management

-- ===========================================
-- 1. MAILBOX RLS POLICIES
-- ===========================================

-- Admin DELETE policy
CREATE POLICY admin_delete_mailboxes ON mailboxes
    FOR DELETE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE profiles.auth_user_id = auth.uid()
            AND profiles.role = 'admin'
        )
    );

-- Admin UPDATE policy
CREATE POLICY admin_update_mailboxes ON mailboxes
    FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE profiles.auth_user_id = auth.uid()
            AND profiles.role = 'admin'
        )
    );

-- Admin INSERT policy
CREATE POLICY admin_insert_mailboxes ON mailboxes
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE profiles.auth_user_id = auth.uid()
            AND profiles.role = 'admin'
        )
    );

-- ===========================================
-- 2. STORE MAILBOX PASSWORD (using Vault)
-- ===========================================

CREATE OR REPLACE FUNCTION public.store_mailbox_password(
    p_mailbox_id uuid,
    p_password text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
DECLARE
    v_secret_name text;
    v_existing_id uuid;
BEGIN
    -- Check if caller has admin role or is service role
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

    -- Verify mailbox exists
    IF NOT EXISTS (SELECT 1 FROM mailboxes WHERE id = p_mailbox_id) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Mailbox not found');
    END IF;

    v_secret_name := 'mailbox_password_' || p_mailbox_id::text;

    -- Check if secret already exists
    SELECT id INTO v_existing_id FROM vault.secrets WHERE name = v_secret_name;

    IF v_existing_id IS NOT NULL THEN
        -- Update existing secret
        PERFORM vault.update_secret(
            v_existing_id,
            p_password,
            v_secret_name,
            'IMAP password for mailbox ' || p_mailbox_id::text
        );
    ELSE
        -- Create new secret
        PERFORM vault.create_secret(
            p_password,
            v_secret_name,
            'IMAP password for mailbox ' || p_mailbox_id::text
        );
    END IF;

    -- Update mailbox to indicate password is configured
    UPDATE mailboxes
    SET sync_settings = COALESCE(sync_settings, '{}'::jsonb) ||
        jsonb_build_object('password_configured', true, 'password_updated_at', now()::text),
        updated_at = now()
    WHERE id = p_mailbox_id;

    RETURN jsonb_build_object(
        'success', true,
        'mailbox_id', p_mailbox_id
    );
END;
$$;

-- ===========================================
-- 3. GET MAILBOX PASSWORD (from Vault)
-- ===========================================

CREATE OR REPLACE FUNCTION public.get_mailbox_password(
    p_mailbox_id uuid
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
DECLARE
    v_secret_name text;
    v_password text;
BEGIN
    -- Only service role can retrieve passwords
    IF auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized: Service role required';
    END IF;

    v_secret_name := 'mailbox_password_' || p_mailbox_id::text;

    -- Get decrypted password from Vault
    SELECT decrypted_secret INTO v_password
    FROM vault.decrypted_secrets
    WHERE name = v_secret_name;

    RETURN v_password;
END;
$$;

-- ===========================================
-- 4. DELETE MAILBOX PASSWORD
-- ===========================================

CREATE OR REPLACE FUNCTION public.delete_mailbox_password(
    p_mailbox_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
DECLARE
    v_secret_name text;
BEGIN
    -- Check if caller has admin role or is service role
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

    v_secret_name := 'mailbox_password_' || p_mailbox_id::text;

    -- Delete from Vault
    DELETE FROM vault.secrets WHERE name = v_secret_name;

    -- Update mailbox
    UPDATE mailboxes
    SET sync_settings = COALESCE(sync_settings, '{}'::jsonb) ||
        jsonb_build_object('password_configured', false),
        updated_at = now()
    WHERE id = p_mailbox_id;

    RETURN jsonb_build_object('success', true, 'mailbox_id', p_mailbox_id);
END;
$$;

-- ===========================================
-- 5. CHECK PASSWORD STATUS
-- ===========================================

CREATE OR REPLACE FUNCTION public.check_mailbox_password_status(
    p_mailbox_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
DECLARE
    v_secret_name text;
    v_has_password boolean;
    v_mailbox record;
BEGIN
    IF auth.role() IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Authentication required');
    END IF;

    v_secret_name := 'mailbox_password_' || p_mailbox_id::text;

    -- Check if secret exists in Vault
    SELECT EXISTS (SELECT 1 FROM vault.secrets WHERE name = v_secret_name) INTO v_has_password;

    -- Get mailbox info
    SELECT id, email, sync_settings->>'password_updated_at' as password_updated_at
    INTO v_mailbox
    FROM mailboxes
    WHERE id = p_mailbox_id;

    IF v_mailbox.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Mailbox not found');
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'mailbox_id', p_mailbox_id,
        'email', v_mailbox.email,
        'has_password', v_has_password,
        'password_updated_at', v_mailbox.password_updated_at
    );
END;
$$;

-- ===========================================
-- 6. UPSERT MAILBOX (with password)
-- ===========================================

CREATE OR REPLACE FUNCTION public.upsert_mailbox(
    p_id uuid DEFAULT NULL,
    p_email text DEFAULT NULL,
    p_name text DEFAULT NULL,
    p_type text DEFAULT 'personal',
    p_imap_host text DEFAULT 'mail.pdmedical.com.au',
    p_imap_port integer DEFAULT 993,
    p_imap_username text DEFAULT NULL,
    p_password text DEFAULT NULL,
    p_is_active boolean DEFAULT true
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
            updated_at = now()
        WHERE id = p_id
        RETURNING id INTO v_mailbox_id;

        IF v_mailbox_id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'error', 'Mailbox not found');
        END IF;
    ELSE
        -- Create new
        INSERT INTO mailboxes (email, name, type, imap_host, imap_port, imap_username, is_active)
        VALUES (p_email, p_name, p_type, p_imap_host, p_imap_port, p_imap_username, p_is_active)
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

-- ===========================================
-- 7. GET MAILBOX CREDENTIALS
-- ===========================================

CREATE OR REPLACE FUNCTION public.get_mailbox_credentials(
    p_mailbox_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

-- ===========================================
-- 8. AUTO-DELETE SECRET ON MAILBOX DELETE
-- ===========================================

CREATE OR REPLACE FUNCTION public.handle_mailbox_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
BEGIN
    -- Delete the associated vault secret
    DELETE FROM vault.secrets
    WHERE name = 'mailbox_password_' || OLD.id::text;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS on_mailbox_delete ON mailboxes;
CREATE TRIGGER on_mailbox_delete
    BEFORE DELETE ON mailboxes
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_mailbox_delete();

-- ===========================================
-- 9. PERMISSIONS
-- ===========================================

GRANT EXECUTE ON FUNCTION public.store_mailbox_password(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_mailbox_password(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_mailbox_password_status(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_mailbox(uuid, text, text, text, text, integer, text, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_mailbox_password(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_mailbox_credentials(uuid) TO service_role;

-- Comments
COMMENT ON FUNCTION public.store_mailbox_password IS 'Store IMAP password in Supabase Vault. Admin only.';
COMMENT ON FUNCTION public.get_mailbox_password IS 'Retrieve IMAP password from Vault. Service role only.';
COMMENT ON FUNCTION public.delete_mailbox_password IS 'Delete IMAP password from Vault. Admin only.';
COMMENT ON FUNCTION public.upsert_mailbox IS 'Create or update mailbox with optional password. Admin only.';
COMMENT ON FUNCTION public.get_mailbox_credentials IS 'Get full mailbox credentials including password. Service role only.';
