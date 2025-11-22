-- ===========================================
-- FIX get_profile_by_auth_user_id FUNCTION
-- ===========================================
-- The function was referencing p.id but the column is actually profile_id

CREATE OR REPLACE FUNCTION "public"."get_profile_by_auth_user_id"("user_id" "uuid")
RETURNS TABLE(
    "id" "uuid",
    "auth_user_id" "uuid",
    "full_name" "text",
    "role" "public"."role_type",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
)
LANGUAGE "plpgsql" STABLE SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.profile_id as id,
        p.auth_user_id,
        p.full_name,
        p.role,
        p.created_at,
        p.updated_at
    FROM profiles p
    WHERE p.auth_user_id = user_id;
END;
$$;

COMMENT ON FUNCTION public.get_profile_by_auth_user_id IS 'Get profile by auth user ID. Returns profile_id as id for backward compatibility.';

-- ===========================================
-- FIX admin_update_user_role FUNCTION
-- ===========================================
-- The function was referencing profiles.id but the column is actually profile_id

DROP FUNCTION IF EXISTS public.admin_update_user_role(uuid, role_type);
CREATE OR REPLACE FUNCTION public.admin_update_user_role(p_profile_id uuid, new_role role_type)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Check if admin
    IF NOT has_permission('manage_users') THEN
        RETURN json_build_object('success', false, 'error', 'Unauthorized');
    END IF;

    -- Update role
    UPDATE profiles
    SET role = new_role, updated_at = NOW()
    WHERE profile_id = p_profile_id;

    RETURN json_build_object('success', true);
END;
$$;
