BEGIN;

-- Step 1: Add new profile_id column
ALTER TABLE public.profiles 
  ADD COLUMN profile_id UUID DEFAULT gen_random_uuid();

-- Step 2: Rename 'id' to 'auth_user_id' for clarity
ALTER TABLE public.profiles 
  RENAME COLUMN id TO auth_user_id;

-- Step 3: Drop the old primary key constraint
ALTER TABLE public.profiles 
  DROP CONSTRAINT profiles_pkey;

-- Step 4: Drop the old foreign key constraint
ALTER TABLE public.profiles 
  DROP CONSTRAINT profiles_id_fkey;

-- Step 5: Make profile_id the new primary key
ALTER TABLE public.profiles 
  ADD CONSTRAINT profiles_pkey PRIMARY KEY (profile_id);

-- Step 6: Add foreign key constraint to auth_user_id
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_auth_user_id_fkey 
  FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Step 7: Create index for faster lookups
CREATE INDEX idx_profiles_auth_user_id ON public.profiles(auth_user_id);

-- Step 8: Update existing NULL full_name values before making it NOT NULL
-- Set a default value for any NULL full_name entries
UPDATE public.profiles 
SET full_name = 'Unknown' 
WHERE full_name IS NULL;

-- Step 9: Make sure full_name is NOT NULL (for data integrity)
ALTER TABLE public.profiles 
  ALTER COLUMN full_name SET NOT NULL;

-- Step 10: Update RLS policies to use auth_user_id instead of id
DROP POLICY IF EXISTS "Users can read their own profile" ON public.profiles;
CREATE POLICY "Users can read their own profile"
  ON public.profiles
  FOR SELECT
  USING (auth.uid() = auth_user_id);

DROP POLICY IF EXISTS "Admins can read all profiles" ON public.profiles;
CREATE POLICY "Admins can read all profiles"
  ON public.profiles
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.profiles AS me
      WHERE me.auth_user_id = auth.uid()
        AND me.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "Admins can manage profiles" ON public.profiles;
CREATE POLICY "Admins can manage profiles"
  ON public.profiles
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.profiles AS me
      WHERE me.auth_user_id = auth.uid()
        AND me.role = 'admin'
    )
  )
  WITH CHECK (true);

-- Step 11: Update the profiles_with_email view to use auth_user_id
CREATE OR REPLACE VIEW public.profiles_with_email AS
SELECT
  p.profile_id,
  p.auth_user_id,
  p.full_name,
  p.role,
  p.created_at,
  p.updated_at,
  u.email
FROM public.profiles p
JOIN auth.users u ON u.id = p.auth_user_id;

COMMIT;

