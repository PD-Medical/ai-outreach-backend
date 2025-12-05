-- ============================================================================
-- FIX PRODUCT PERMISSIONS MIGRATION
-- ============================================================================
-- Fixes:
-- 1. Update is_valid_permission() to include view_products, manage_products
-- 2. Add view_products, manage_products columns to user_permissions table
-- 3. Update get_user_effective_permissions() to return new permission columns
-- ============================================================================

-- 1. Replace is_valid_permission function with updated list
CREATE OR REPLACE FUNCTION public.is_valid_permission(p text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT p IN (
    'view_users', 'manage_users', 'view_contacts', 'manage_contacts',
    'view_campaigns', 'manage_campaigns', 'approve_campaigns',
    'view_analytics', 'manage_approvals', 'view_workflows', 'view_emails',
    'view_products', 'manage_products'
  )
$$;

-- 2. Add permission columns to user_permissions table (for overrides)
ALTER TABLE public.user_permissions
    ADD COLUMN IF NOT EXISTS view_products BOOLEAN,
    ADD COLUMN IF NOT EXISTS manage_products BOOLEAN;

-- 3. Update get_user_effective_permissions to include product permissions
-- Replace existing get_user_effective_permissions with product-aware version
DROP FUNCTION IF EXISTS public.get_user_effective_permissions(uuid);

CREATE FUNCTION public.get_user_effective_permissions(target_user_id uuid)
RETURNS TABLE(
    view_users boolean,
    manage_users boolean,
    view_contacts boolean,
    manage_contacts boolean,
    view_campaigns boolean,
    manage_campaigns boolean,
    approve_campaigns boolean,
    view_analytics boolean,
    manage_approvals boolean,
    view_workflows boolean,
    view_emails boolean,
    view_products boolean,
    manage_products boolean,
    has_overrides boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
DECLARE
    user_role public.role_type;
    role_perms RECORD;
    user_overrides RECORD;
BEGIN
    PERFORM set_config('search_path', 'public,pg_temp', true);
    
    -- Check caller has permission or is viewing their own
    IF NOT (
        public.has_permission('manage_users')
        OR auth.uid() = target_user_id
    ) THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;
    
    -- Get user's role
    SELECT p.role INTO user_role
    FROM public.profiles p
    WHERE p.auth_user_id = target_user_id
    LIMIT 1;
    
    -- If user doesn't exist, return all false
    IF user_role IS NULL THEN
        RETURN QUERY SELECT
            false, false, false, false, false,
            false, false, false, false, false,
            false, false, false, false;
        RETURN;
    END IF;
    
    -- Get role permissions
    SELECT * INTO role_perms
    FROM public.role_permissions rp
    WHERE rp.role = user_role
    LIMIT 1;
    
    -- Get user overrides (if any)
    SELECT * INTO user_overrides
    FROM public.user_permissions up
    WHERE up.auth_user_id = target_user_id
    LIMIT 1;
    
    -- Return merged permissions (role defaults + overrides)
    RETURN QUERY SELECT
        COALESCE(user_overrides.view_users,        role_perms.view_users),
        COALESCE(user_overrides.manage_users,      role_perms.manage_users),
        COALESCE(user_overrides.view_contacts,     role_perms.view_contacts),
        COALESCE(user_overrides.manage_contacts,   role_perms.manage_contacts),
        COALESCE(user_overrides.view_campaigns,    role_perms.view_campaigns),
        COALESCE(user_overrides.manage_campaigns,  role_perms.manage_campaigns),
        COALESCE(user_overrides.approve_campaigns, role_perms.approve_campaigns),
        COALESCE(user_overrides.view_analytics,    role_perms.view_analytics),
        COALESCE(user_overrides.manage_approvals,  role_perms.manage_approvals),
        COALESCE(user_overrides.view_workflows,    role_perms.view_workflows),
        COALESCE(user_overrides.view_emails,       role_perms.view_emails),
        COALESCE(user_overrides.view_products,     role_perms.view_products),
        COALESCE(user_overrides.manage_products,   role_perms.manage_products),
        (user_overrides.id IS NOT NULL);
END;
$$;