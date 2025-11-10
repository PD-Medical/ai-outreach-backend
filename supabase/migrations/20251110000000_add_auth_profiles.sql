-- Create role enum once
do $$
begin
  if not exists (select 1 from pg_type where typname = 'role_type') then
    create type public.role_type as enum ('admin', 'sales', 'accounts', 'management');
  end if;
end
$$;

-- Profiles table linked to auth.users
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role public.role_type not null default 'sales',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

-- Keep updated_at current
create or replace function public.handle_profiles_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists profiles_set_timestamp on public.profiles;
create trigger profiles_set_timestamp
before update on public.profiles
for each row
execute function public.handle_profiles_updated_at();

-- Enable RLS and policies
alter table public.profiles enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'Users can read their own profile'
  ) then
    execute $policy$
      create policy "Users can read their own profile"
      on public.profiles
      for select
      using (auth.uid() = id);
    $policy$;
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'Admins can read all profiles'
  ) then
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

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'Admins can manage profiles'
  ) then
    execute $policy$
      create policy "Admins can manage profiles"
      on public.profiles
      for update
      using (
        exists (
          select 1
          from public.profiles as me
          where me.id = auth.uid()
            and me.role = 'admin'
        )
      )
      with check (true);
    $policy$;
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'Service role creates profiles'
  ) then
    execute $policy$
      create policy "Service role creates profiles"
      on public.profiles
      for insert
      with check (auth.role() = 'service_role');
    $policy$;
  end if;
end
$$;

