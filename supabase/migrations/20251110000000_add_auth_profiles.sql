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
  id uuid not null,
  full_name text,
  role public.role_type not null default 'sales'::public.role_type,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint profiles_pkey primary key (id),
  constraint profiles_id_fkey foreign key (id) references auth.users (id) on delete cascade
) tablespace pg_default;

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

-- Prevent role changes outside service role
create or replace function public.prevent_role_change()
returns trigger
language plpgsql
as $$
begin
  if current_user <> 'service_role' and new.role <> old.role then
    raise exception 'Role changes require service role privileges';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_set_timestamp on public.profiles;
create trigger profiles_set_timestamp
before update on public.profiles
for each row
execute function public.handle_profiles_updated_at();

drop trigger if exists prevent_role_change_trigger on public.profiles;
create trigger prevent_role_change_trigger
before update on public.profiles
for each row
execute function public.prevent_role_change();

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

-- Read-only view with email
create or replace view public.profiles_with_email as
select
  p.id,
  p.full_name,
  p.role,
  p.created_at,
  p.updated_at,
  u.email
from public.profiles p
join auth.users u on u.id = p.id;

grant select on public.profiles_with_email to authenticated;

