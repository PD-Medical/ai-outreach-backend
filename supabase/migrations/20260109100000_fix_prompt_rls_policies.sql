-- ============================================================================
-- Fix Prompt RLS Policies
-- Created: 2026-01-09
--
-- The original policies used current_jwt_role() which reads from JWT claims,
-- but the app stores user roles in the profiles table. This migration fixes
-- the policies to use the profiles table pattern (matching mailboxes policies).
-- ============================================================================

-- Fix prompts admin policy - use profiles table pattern
DROP POLICY IF EXISTS "Admins can manage prompts" ON prompts;
CREATE POLICY "Admins can manage prompts" ON prompts FOR ALL
TO authenticated
USING (EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.auth_user_id = auth.uid()
    AND profiles.role = 'admin'::public.role_type
));

-- Fix prompt_versions admin read policy
DROP POLICY IF EXISTS "Admins can read versions" ON prompt_versions;
CREATE POLICY "Admins can read versions" ON prompt_versions FOR SELECT
TO authenticated
USING (EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.auth_user_id = auth.uid()
    AND profiles.role = 'admin'::public.role_type
));

-- Fix prompt_versions admin insert policy
DROP POLICY IF EXISTS "Admins can insert versions" ON prompt_versions;
CREATE POLICY "Admins can insert versions" ON prompt_versions FOR INSERT
TO authenticated
WITH CHECK (EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.auth_user_id = auth.uid()
    AND profiles.role = 'admin'::public.role_type
));
