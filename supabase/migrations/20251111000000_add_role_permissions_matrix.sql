-- Permission matrix for roles
create table if not exists public.role_permissions (
  role public.role_type primary key,
  view_users boolean not null default false,
  manage_users boolean not null default false,
  view_contacts boolean not null default false,
  manage_contacts boolean not null default false,
  view_campaigns boolean not null default false,
  manage_campaigns boolean not null default false,
  approve_campaigns boolean not null default false,
  view_analytics boolean not null default false,
  manage_approvals boolean not null default false,
  updated_at timestamptz not null default timezone('utc', now())
);

insert into public.role_permissions (
  role,
  view_users,
  manage_users,
  view_contacts,
  manage_contacts,
  view_campaigns,
  manage_campaigns,
  approve_campaigns,
  view_analytics,
  manage_approvals
) values
  ('admin', true, true, true, true, true, true, true, true, true),
  ('sales', false, false, true, true, true, true, false, true, false),
  ('accounts', false, false, true, true, true, false, true, true, true),
  ('management', false, false, true, false, true, false, true, true, true)
on conflict (role) do nothing;

alter table public.role_permissions enable row level security;

create or replace function public.touch_role_permissions_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists role_permissions_set_timestamp on public.role_permissions;
create trigger role_permissions_set_timestamp
before update on public.role_permissions
for each row
execute function public.touch_role_permissions_updated_at();

do $policies$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'role_permissions'
      and policyname = 'Role permissions: read'
  ) then
    execute $policy$
      create policy "Role permissions: read"
      on public.role_permissions
      for select
      using (true);
    $policy$;
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'role_permissions'
      and policyname = 'Role permissions: admin update'
  ) then
    execute $policy$
      create policy "Role permissions: admin update"
      on public.role_permissions
      for update
      using (public.current_jwt_role() = 'admin')
      with check (public.current_jwt_role() = 'admin');
    $policy$;
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'role_permissions'
      and policyname = 'Role permissions: service insert'
  ) then
    execute $policy$
      create policy "Role permissions: service insert"
      on public.role_permissions
      for insert
      with check (auth.role() = 'service_role');
    $policy$;
  end if;
end
$policies$;

