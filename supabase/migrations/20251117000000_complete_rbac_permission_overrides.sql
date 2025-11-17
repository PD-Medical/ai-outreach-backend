-- ============================================================================
-- PDMedical Complete RBAC + Permission Override System
-- Simplified for small company - everyone sees all data
-- Production-ready migration
-- Author: Binil
-- Date: 2025-11-17
-- ============================================================================

-- ============================================================================
-- STEP 1: Add auth_user_id columns to all tables
-- ============================================================================

ALTER TABLE contacts 
ADD COLUMN IF NOT EXISTS auth_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE campaigns 
ADD COLUMN IF NOT EXISTS auth_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

ALTER TABLE organizations 
ADD COLUMN IF NOT EXISTS auth_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE conversations 
ADD COLUMN IF NOT EXISTS auth_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE emails 
ADD COLUMN IF NOT EXISTS auth_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE contact_product_interests 
ADD COLUMN IF NOT EXISTS auth_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

-- ============================================================================
-- STEP 2: Create indexes on auth_user_id columns
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_contacts_auth_user_id ON contacts(auth_user_id);
CREATE INDEX IF NOT EXISTS idx_campaigns_auth_user_id ON campaigns(auth_user_id);
CREATE INDEX IF NOT EXISTS idx_emails_auth_user_id ON emails(auth_user_id);
CREATE INDEX IF NOT EXISTS idx_organizations_auth_user_id ON organizations(auth_user_id);
CREATE INDEX IF NOT EXISTS idx_conversations_auth_user_id ON conversations(auth_user_id);
CREATE INDEX IF NOT EXISTS idx_contact_product_interests_auth_user_id ON contact_product_interests(auth_user_id);

-- ============================================================================
-- STEP 3A: Fix existing trigger to handle missing columns
-- ============================================================================

CREATE OR REPLACE FUNCTION set_approved_by()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM set_config('search_path', 'public,pg_temp', true);
  
  BEGIN
    IF TG_OP = 'UPDATE' THEN
      IF NEW.status = 'approved' 
         AND (OLD.status IS NULL OR OLD.status != 'approved') 
         AND NEW.approved_by IS NULL THEN
        NEW.approved_by = auth.uid();
        NEW.approved_at = NOW();
      END IF;
    END IF;
  EXCEPTION
    WHEN undefined_column THEN
      NULL;
  END;
  
  RETURN NEW;
END;
$$;

-- ============================================================================
-- STEP 3: Backfill existing data with admin user
-- ============================================================================

DO $$
DECLARE
  admin_user_id UUID;
BEGIN
  SELECT auth_user_id INTO admin_user_id
  FROM profiles
  WHERE role = 'admin'
  LIMIT 1;
  
  IF admin_user_id IS NULL THEN
    RAISE NOTICE 'No admin user found. Skipping backfill.';
    RETURN;
  END IF;
  
  RAISE NOTICE 'Backfilling with admin user: %', admin_user_id;
  
  UPDATE contacts SET auth_user_id = admin_user_id WHERE auth_user_id IS NULL;
  UPDATE campaigns SET auth_user_id = admin_user_id WHERE auth_user_id IS NULL;
  UPDATE emails SET auth_user_id = admin_user_id WHERE auth_user_id IS NULL;
  UPDATE organizations SET auth_user_id = admin_user_id WHERE auth_user_id IS NULL;
  UPDATE conversations SET auth_user_id = admin_user_id WHERE auth_user_id IS NULL;
  UPDATE contact_product_interests SET auth_user_id = admin_user_id WHERE auth_user_id IS NULL;
  
  RAISE NOTICE 'Backfill complete!';
END $$;

-- ============================================================================
-- STEP 4: Create helper functions
-- ============================================================================

DROP FUNCTION IF EXISTS get_current_user_role();
DROP FUNCTION IF EXISTS is_admin();
DROP FUNCTION IF EXISTS public.is_valid_permission(TEXT);

CREATE OR REPLACE FUNCTION public.is_valid_permission(p TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p IN (
    'view_users', 'manage_users', 'view_contacts', 'manage_contacts',
    'view_campaigns', 'manage_campaigns', 'approve_campaigns',
    'view_analytics', 'manage_approvals', 'view_workflows', 'view_emails'
  )
$$;

CREATE OR REPLACE FUNCTION get_current_user_role()
RETURNS TEXT 
LANGUAGE plpgsql
SECURITY DEFINER 
STABLE
AS $$
BEGIN
  PERFORM set_config('search_path', 'public,pg_temp', true);
  
  RETURN (
    SELECT role::text
    FROM profiles 
    WHERE auth_user_id = auth.uid()
    LIMIT 1
  );
END;
$$;

CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN 
LANGUAGE plpgsql
SECURITY DEFINER 
STABLE
AS $$
BEGIN
  PERFORM set_config('search_path', 'public,pg_temp', true);
  
  RETURN COALESCE(
    (SELECT role = 'admin' FROM profiles WHERE auth_user_id = auth.uid() LIMIT 1),
    FALSE
  );
END;
$$;

-- ============================================================================
-- STEP 5: Create user_permissions table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.user_permissions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    auth_user_id UUID NOT NULL,
    
    view_users BOOLEAN,
    manage_users BOOLEAN,
    view_contacts BOOLEAN,
    manage_contacts BOOLEAN,
    view_campaigns BOOLEAN,
    manage_campaigns BOOLEAN,
    approve_campaigns BOOLEAN,
    view_analytics BOOLEAN,
    manage_approvals BOOLEAN,
    view_workflows BOOLEAN,
    view_emails BOOLEAN,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc'::text, NOW()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc'::text, NOW()),
    created_by UUID REFERENCES auth.users(id),
    
    CONSTRAINT user_permissions_auth_user_unique UNIQUE(auth_user_id),
    CONSTRAINT user_permissions_auth_user_id_fkey 
        FOREIGN KEY (auth_user_id) 
        REFERENCES auth.users(id) 
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_user_permissions_auth_user_id 
    ON public.user_permissions USING btree (auth_user_id);

COMMENT ON TABLE public.user_permissions IS 'Stores per-user permission overrides that take precedence over role-based defaults';

-- ============================================================================
-- STEP 6: Create has_permission function with override support
-- ============================================================================

DROP FUNCTION IF EXISTS has_permission(TEXT) CASCADE;

CREATE OR REPLACE FUNCTION has_permission(permission_name TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    user_role public.role_type;
    role_perm BOOLEAN;
    user_override BOOLEAN;
BEGIN
    PERFORM set_config('search_path', 'public,pg_temp', true);
    
    IF NOT public.is_valid_permission(permission_name) THEN
        RAISE WARNING 'Invalid permission name: %', permission_name;
        RETURN FALSE;
    END IF;
    
    SELECT p.role INTO user_role
    FROM public.profiles p
    WHERE p.auth_user_id = auth.uid()
    LIMIT 1;
    
    IF user_role IS NULL THEN
        RETURN FALSE;
    END IF;
    
    EXECUTE format(
        'SELECT %I FROM public.user_permissions WHERE auth_user_id = $1',
        permission_name
    ) INTO user_override USING auth.uid();
    
    IF user_override IS NOT NULL THEN
        RETURN user_override;
    END IF;
    
    EXECUTE format(
        'SELECT %I FROM public.role_permissions WHERE role = $1',
        permission_name
    ) INTO role_perm USING user_role;
    
    RETURN COALESCE(role_perm, FALSE);
END;
$$;

COMMENT ON FUNCTION has_permission(TEXT) IS 'Check if current user has a specific permission. Checks user overrides first, then falls back to role permissions.';

-- Recreate profiles policies
DROP POLICY IF EXISTS "Admins can view all profiles" ON profiles;
CREATE POLICY "Admins can view all profiles" ON profiles
  FOR SELECT
  USING (has_permission('view_users'));

DROP POLICY IF EXISTS "Admins can update profiles" ON profiles;
CREATE POLICY "Admins can update profiles" ON profiles
  FOR UPDATE
  USING (has_permission('manage_users'));

-- ============================================================================
-- STEP 7: Create permission management functions
-- ============================================================================

DROP FUNCTION IF EXISTS get_user_effective_permissions(UUID);

CREATE OR REPLACE FUNCTION get_user_effective_permissions(target_user_id UUID)
RETURNS TABLE(
    view_users BOOLEAN,
    manage_users BOOLEAN,
    view_contacts BOOLEAN,
    manage_contacts BOOLEAN,
    view_campaigns BOOLEAN,
    manage_campaigns BOOLEAN,
    approve_campaigns BOOLEAN,
    view_analytics BOOLEAN,
    manage_approvals BOOLEAN,
    view_workflows BOOLEAN,
    view_emails BOOLEAN,
    has_overrides BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    user_role public.role_type;
    role_perms RECORD;
    user_overrides RECORD;
BEGIN
    PERFORM set_config('search_path', 'public,pg_temp', true);
    
    IF NOT (
        public.has_permission('manage_users') 
        OR auth.uid() = target_user_id
    ) THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;
    
    SELECT p.role INTO user_role
    FROM public.profiles p
    WHERE p.auth_user_id = target_user_id
    LIMIT 1;
    
    IF user_role IS NULL THEN
        RETURN QUERY SELECT 
            false, false, false, false, false, 
            false, false, false, false, false, 
            false, false;
        RETURN;
    END IF;
    
    SELECT * INTO role_perms
    FROM public.role_permissions rp
    WHERE rp.role = user_role
    LIMIT 1;
    
    SELECT * INTO user_overrides
    FROM public.user_permissions up
    WHERE up.auth_user_id = target_user_id
    LIMIT 1;
    
    RETURN QUERY SELECT
        COALESCE(user_overrides.view_users, role_perms.view_users),
        COALESCE(user_overrides.manage_users, role_perms.manage_users),
        COALESCE(user_overrides.view_contacts, role_perms.view_contacts),
        COALESCE(user_overrides.manage_contacts, role_perms.manage_contacts),
        COALESCE(user_overrides.view_campaigns, role_perms.view_campaigns),
        COALESCE(user_overrides.manage_campaigns, role_perms.manage_campaigns),
        COALESCE(user_overrides.approve_campaigns, role_perms.approve_campaigns),
        COALESCE(user_overrides.view_analytics, role_perms.view_analytics),
        COALESCE(user_overrides.manage_approvals, role_perms.manage_approvals),
        COALESCE(user_overrides.view_workflows, role_perms.view_workflows),
        COALESCE(user_overrides.view_emails, role_perms.view_emails),
        (user_overrides.id IS NOT NULL);
END;
$$;

DROP FUNCTION IF EXISTS set_user_permission_override(UUID, JSONB);

CREATE OR REPLACE FUNCTION set_user_permission_override(
    target_user_id UUID,
    permission_updates JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    k TEXT;
    v TEXT;
BEGIN
    PERFORM set_config('search_path', 'public,pg_temp', true);
    
    IF NOT public.has_permission('manage_users') THEN
        RAISE EXCEPTION 'Unauthorized: manage_users permission required';
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE auth_user_id = target_user_id
    ) THEN
        RAISE EXCEPTION 'User not found: %', target_user_id;
    END IF;
    
    INSERT INTO public.user_permissions (auth_user_id, created_by)
    VALUES (target_user_id, auth.uid())
    ON CONFLICT (auth_user_id) DO NOTHING;
    
    FOR k, v IN SELECT key, value FROM jsonb_each_text(permission_updates)
    LOOP
        IF NOT public.is_valid_permission(k) THEN
            RAISE WARNING 'Skipping invalid permission key: %', k;
            CONTINUE;
        END IF;
        
        EXECUTE format(
            'UPDATE public.user_permissions 
             SET %I = $1::boolean, updated_at = NOW() 
             WHERE auth_user_id = $2',
            k
        ) USING v, target_user_id;
    END LOOP;
END;
$$;

DROP FUNCTION IF EXISTS clear_user_permission_override(UUID, TEXT);

CREATE OR REPLACE FUNCTION clear_user_permission_override(
    target_user_id UUID,
    permission_key TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM set_config('search_path', 'public,pg_temp', true);
    
    IF NOT public.has_permission('manage_users') THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;
    
    IF NOT public.is_valid_permission(permission_key) THEN
        RAISE EXCEPTION 'Invalid permission key: %', permission_key;
    END IF;
    
    EXECUTE format(
        'UPDATE public.user_permissions 
         SET %I = NULL, updated_at = NOW() 
         WHERE auth_user_id = $1',
        permission_key
    ) USING target_user_id;
    
    DELETE FROM public.user_permissions
    WHERE auth_user_id = target_user_id
    AND view_users IS NULL
    AND manage_users IS NULL
    AND view_contacts IS NULL
    AND manage_contacts IS NULL
    AND view_campaigns IS NULL
    AND manage_campaigns IS NULL
    AND approve_campaigns IS NULL
    AND view_analytics IS NULL
    AND manage_approvals IS NULL
    AND view_workflows IS NULL
    AND view_emails IS NULL;
END;
$$;

DROP FUNCTION IF EXISTS remove_user_permission_overrides(UUID);

CREATE OR REPLACE FUNCTION remove_user_permission_overrides(target_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM set_config('search_path', 'public,pg_temp', true);
    
    IF NOT public.has_permission('manage_users') THEN
        RAISE EXCEPTION 'Unauthorized: manage_users permission required';
    END IF;
    
    DELETE FROM public.user_permissions
    WHERE auth_user_id = target_user_id;
    
    RAISE NOTICE 'Removed all permission overrides for user %', target_user_id;
END;
$$;

-- ============================================================================
-- STEP 8: Create auto-tracking trigger
-- ============================================================================

CREATE OR REPLACE FUNCTION set_auth_user_tracking()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM set_config('search_path', 'public,pg_temp', true);
  
  IF TG_OP = 'INSERT' AND NEW.auth_user_id IS NULL THEN
    NEW.auth_user_id = auth.uid();
  END IF;
  
  IF TG_OP = 'INSERT' THEN
    IF TG_TABLE_NAME IN ('contacts', 'campaigns', 'emails', 'organizations', 'conversations', 'contact_product_interests') THEN
      IF NEW.created_at IS NULL THEN
        NEW.created_at = NOW();
      END IF;
    END IF;
  END IF;
  
  IF TG_OP = 'UPDATE' THEN
    IF TG_TABLE_NAME IN ('contacts', 'campaigns', 'emails', 'organizations', 'conversations', 'contact_product_interests') THEN
      NEW.updated_at = NOW();
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_contacts_auth_tracking ON contacts;
CREATE TRIGGER trigger_contacts_auth_tracking
  BEFORE INSERT OR UPDATE ON contacts
  FOR EACH ROW
  EXECUTE FUNCTION set_auth_user_tracking();

DROP TRIGGER IF EXISTS trigger_campaigns_auth_tracking ON campaigns;
CREATE TRIGGER trigger_campaigns_auth_tracking
  BEFORE INSERT OR UPDATE ON campaigns
  FOR EACH ROW
  EXECUTE FUNCTION set_auth_user_tracking();

DROP TRIGGER IF EXISTS trigger_emails_auth_tracking ON emails;
CREATE TRIGGER trigger_emails_auth_tracking
  BEFORE INSERT OR UPDATE ON emails
  FOR EACH ROW
  EXECUTE FUNCTION set_auth_user_tracking();

DROP TRIGGER IF EXISTS trigger_organizations_auth_tracking ON organizations;
CREATE TRIGGER trigger_organizations_auth_tracking
  BEFORE INSERT OR UPDATE ON organizations
  FOR EACH ROW
  EXECUTE FUNCTION set_auth_user_tracking();

DROP TRIGGER IF EXISTS trigger_conversations_auth_tracking ON conversations;
CREATE TRIGGER trigger_conversations_auth_tracking
  BEFORE INSERT OR UPDATE ON conversations
  FOR EACH ROW
  EXECUTE FUNCTION set_auth_user_tracking();

DROP TRIGGER IF EXISTS trigger_contact_product_interests_auth_tracking ON contact_product_interests;
CREATE TRIGGER trigger_contact_product_interests_auth_tracking
  BEFORE INSERT OR UPDATE ON contact_product_interests
  FOR EACH ROW
  EXECUTE FUNCTION set_auth_user_tracking();

-- ============================================================================
-- STEP 9: Create RLS policies for data tables
-- ============================================================================

-- user_permissions policies
DROP POLICY IF EXISTS "Admins can manage user permissions" ON public.user_permissions;
CREATE POLICY "Admins can manage user permissions"
    ON public.user_permissions
    FOR ALL
    USING (public.has_permission('manage_users'));

DROP POLICY IF EXISTS "Users can view own permission overrides" ON public.user_permissions;
CREATE POLICY "Users can view own permission overrides"
    ON public.user_permissions
    FOR SELECT
    USING (auth_user_id = auth.uid());

-- Contacts policies
DROP POLICY IF EXISTS "contacts_select_policy" ON contacts;
CREATE POLICY "contacts_select_policy" ON contacts
  FOR SELECT
  USING (has_permission('view_contacts'));

DROP POLICY IF EXISTS "contacts_insert_policy" ON contacts;
CREATE POLICY "contacts_insert_policy" ON contacts
  FOR INSERT
  WITH CHECK (has_permission('manage_contacts'));

DROP POLICY IF EXISTS "contacts_update_policy" ON contacts;
CREATE POLICY "contacts_update_policy" ON contacts
  FOR UPDATE
  USING (has_permission('manage_contacts'));

DROP POLICY IF EXISTS "contacts_delete_policy" ON contacts;
CREATE POLICY "contacts_delete_policy" ON contacts
  FOR DELETE
  USING (has_permission('manage_contacts'));

-- Campaigns policies
DROP POLICY IF EXISTS "campaigns_select_policy" ON campaigns;
CREATE POLICY "campaigns_select_policy" ON campaigns
  FOR SELECT
  USING (has_permission('view_campaigns'));

DROP POLICY IF EXISTS "campaigns_insert_policy" ON campaigns;
CREATE POLICY "campaigns_insert_policy" ON campaigns
  FOR INSERT
  WITH CHECK (has_permission('manage_campaigns'));

DROP POLICY IF EXISTS "campaigns_update_policy" ON campaigns;
CREATE POLICY "campaigns_update_policy" ON campaigns
  FOR UPDATE
  USING (
    has_permission('manage_campaigns')
    OR
    has_permission('approve_campaigns')
  );

DROP POLICY IF EXISTS "campaigns_delete_policy" ON campaigns;
CREATE POLICY "campaigns_delete_policy" ON campaigns
  FOR DELETE
  USING (has_permission('manage_campaigns'));

-- Emails policies
DROP POLICY IF EXISTS "emails_select_policy" ON emails;
CREATE POLICY "emails_select_policy" ON emails
  FOR SELECT
  USING (has_permission('view_emails'));

DROP POLICY IF EXISTS "emails_insert_policy" ON emails;
CREATE POLICY "emails_insert_policy" ON emails
  FOR INSERT
  WITH CHECK (true);

DROP POLICY IF EXISTS "emails_update_policy" ON emails;
CREATE POLICY "emails_update_policy" ON emails
  FOR UPDATE
  USING (true);

DROP POLICY IF EXISTS "emails_delete_policy" ON emails;
CREATE POLICY "emails_delete_policy" ON emails
  FOR DELETE
  USING (is_admin());

-- Organizations policies
DROP POLICY IF EXISTS "organizations_select_policy" ON organizations;
CREATE POLICY "organizations_select_policy" ON organizations
  FOR SELECT
  USING (has_permission('view_contacts'));

DROP POLICY IF EXISTS "organizations_insert_policy" ON organizations;
CREATE POLICY "organizations_insert_policy" ON organizations
  FOR INSERT
  WITH CHECK (has_permission('manage_contacts'));

DROP POLICY IF EXISTS "organizations_update_policy" ON organizations;
CREATE POLICY "organizations_update_policy" ON organizations
  FOR UPDATE
  USING (has_permission('manage_contacts'));

DROP POLICY IF EXISTS "organizations_delete_policy" ON organizations;
CREATE POLICY "organizations_delete_policy" ON organizations
  FOR DELETE
  USING (has_permission('manage_contacts'));

-- Conversations policies
DROP POLICY IF EXISTS "conversations_select_policy" ON conversations;
CREATE POLICY "conversations_select_policy" ON conversations
  FOR SELECT
  USING (has_permission('view_emails'));

DROP POLICY IF EXISTS "conversations_insert_policy" ON conversations;
CREATE POLICY "conversations_insert_policy" ON conversations
  FOR INSERT
  WITH CHECK (true);

DROP POLICY IF EXISTS "conversations_update_policy" ON conversations;
CREATE POLICY "conversations_update_policy" ON conversations
  FOR UPDATE
  USING (true);

DROP POLICY IF EXISTS "conversations_delete_policy" ON conversations;
CREATE POLICY "conversations_delete_policy" ON conversations
  FOR DELETE
  USING (is_admin());

-- Contact Product Interests policies
DROP POLICY IF EXISTS "contact_product_interests_select_policy" ON contact_product_interests;
CREATE POLICY "contact_product_interests_select_policy" ON contact_product_interests
  FOR SELECT
  USING (has_permission('view_contacts'));

DROP POLICY IF EXISTS "contact_product_interests_insert_policy" ON contact_product_interests;
CREATE POLICY "contact_product_interests_insert_policy" ON contact_product_interests
  FOR INSERT
  WITH CHECK (has_permission('manage_contacts'));

DROP POLICY IF EXISTS "contact_product_interests_update_policy" ON contact_product_interests;
CREATE POLICY "contact_product_interests_update_policy" ON contact_product_interests
  FOR UPDATE
  USING (has_permission('manage_contacts'));

DROP POLICY IF EXISTS "contact_product_interests_delete_policy" ON contact_product_interests;
CREATE POLICY "contact_product_interests_delete_policy" ON contact_product_interests
  FOR DELETE
  USING (has_permission('manage_contacts'));

-- ============================================================================
-- STEP 10: Enable RLS on all tables
-- ============================================================================

ALTER TABLE public.user_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE emails ENABLE ROW LEVEL SECURITY;
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE contact_product_interests ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- STEP 11: Set function ownership and grants
-- ============================================================================

ALTER FUNCTION public.is_valid_permission(TEXT) OWNER TO postgres;
ALTER FUNCTION public.get_current_user_role() OWNER TO postgres;
ALTER FUNCTION public.is_admin() OWNER TO postgres;
ALTER FUNCTION public.has_permission(TEXT) OWNER TO postgres;
ALTER FUNCTION public.get_user_effective_permissions(UUID) OWNER TO postgres;
ALTER FUNCTION public.set_user_permission_override(UUID, JSONB) OWNER TO postgres;
ALTER FUNCTION public.clear_user_permission_override(UUID, TEXT) OWNER TO postgres;
ALTER FUNCTION public.remove_user_permission_overrides(UUID) OWNER TO postgres;
ALTER FUNCTION public.set_auth_user_tracking() OWNER TO postgres;

REVOKE ALL ON FUNCTION public.is_valid_permission(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_current_user_role() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.has_permission(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_user_effective_permissions(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_user_permission_override(UUID, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.clear_user_permission_override(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.remove_user_permission_overrides(UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.is_valid_permission(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_current_user_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_permission(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_effective_permissions(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_user_permission_override(UUID, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.clear_user_permission_override(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_user_permission_overrides(UUID) TO authenticated;

-- ============================================================================
-- COMPLETION
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '============================================';
    RAISE NOTICE '✅ MIGRATION COMPLETE!';
    RAISE NOTICE '============================================';
    RAISE NOTICE 'RBAC System with Permission Overrides installed';
    RAISE NOTICE '- Everyone sees ALL data (small company mode)';
    RAISE NOTICE '- Permissions control actions, not visibility';
    RAISE NOTICE '- auth_user_id tracks who created what';
    RAISE NOTICE '- Individual permission overrides available';
    RAISE NOTICE '============================================';
END $$;

