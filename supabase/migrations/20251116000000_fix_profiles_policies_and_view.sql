-- Ensure profiles RLS policies and view work when schema uses profile_id instead of id
do $$
declare
  has_profile_id_col boolean := exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'profile_id'
  );
begin
  -- Recreate read policies to account for either id or profile_id
  if exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'Users can read their own profile'
  ) then
    execute 'drop policy "Users can read their own profile" on public.profiles';
  end if;

  if has_profile_id_col then
    execute $policy$
      create policy "Users can read their own profile"
      on public.profiles
      for select
      using (auth.uid() = coalesce((profiles).id, (profiles).profile_id));
    $policy$;
  else
    execute $policy$
      create policy "Users can read their own profile"
      on public.profiles
      for select
      using (auth.uid() = id);
    $policy$;
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'Admins can read all profiles'
  ) then
    execute 'drop policy "Admins can read all profiles" on public.profiles';
  end if;

  if has_profile_id_col then
    execute $policy$
      create policy "Admins can read all profiles"
      on public.profiles
      for select
      using (
        exists (
          select 1
          from public.profiles as me
          where (me.id = auth.uid() or me.profile_id = auth.uid())
            and me.role = 'admin'
        )
      );
    $policy$;
  else
    execute $policy$
      create policy "Admins can read all profiles"
      on public.profiles
      for select
      using (
        exists (
          select 1
          from public.profiles as me
          where me.id = auth.uid()
            and me.role = 'admin'
        )
      );
    $policy$;
  end if;
end
$$;

create or replace view public.profiles_with_email as
select
  p.id as id,
  p.full_name,
  p.role,
  p.created_at,
  p.updated_at,
  u.email
from public.profiles p
join auth.users u on u.id = p.id;

grant select on public.profiles_with_email to authenticated;


