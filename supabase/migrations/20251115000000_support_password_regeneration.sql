-- ============================================================================
-- Support Password Regeneration Functionality
-- ============================================================================
-- This migration ensures the profiles table supports password regeneration
-- functionality via the admin-regenerate-password Edge Function.
--
-- The Edge Function can work with either:
-- 1. profiles.id (which references auth.users.id) - current setup
-- 2. profiles.auth_user_id (optional column for flexibility)
-- ============================================================================

-- Add optional auth_user_id column if it doesn't exist
-- This allows for more flexibility if profiles.id doesn't directly map to auth.users.id
do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'auth_user_id'
  ) then
    alter table public.profiles
    add column auth_user_id uuid;

    -- Add comment
    comment on column public.profiles.auth_user_id is 
      'Optional: Direct reference to auth.users.id. If null, profiles.id is used instead.';
    
    -- Add index for performance
    create index if not exists idx_profiles_auth_user_id 
    on public.profiles(auth_user_id);
  end if;
end
$$;

-- Ensure profiles table has proper structure for password regeneration
-- The admin-regenerate-password function requires:
-- - profiles.id (primary key, references auth.users.id)
-- - profiles.auth_user_id (optional, added above)

-- Add helpful comment to profiles table
comment on table public.profiles is 
  'User profiles linked to auth.users. Used by admin functions for user management including password regeneration.';

