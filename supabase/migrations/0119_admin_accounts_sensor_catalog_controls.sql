grant select on table public.sensor_hardware_catalog to authenticated;

alter table public.sensor_hardware_catalog enable row level security;
drop policy if exists sensor_hardware_catalog_admin_select on public.sensor_hardware_catalog;
create policy sensor_hardware_catalog_admin_select
on public.sensor_hardware_catalog
for select
to authenticated
using (public.is_admin_account('sensors'));

alter table public.admin_accounts drop constraint if exists admin_accounts_role_check;
alter table public.admin_accounts add constraint admin_accounts_role_check
check (role = any (array['super_admin'::text,'manager'::text,'assistant_manager'::text,'admin'::text,'support'::text,'billing'::text,'operations'::text]));

create or replace function public.is_admin_account(required_permission text default null::text)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $function$
  select exists (
    select 1
    from public.admin_accounts a
    where a.user_id = auth.uid()
      and a.active = true
      and (
        required_permission is null
        or a.role = 'super_admin'
        or (a.role = 'manager' and required_permission in ('farms','customers','animals','sensors','alerts','notifications','support','billing','audit','reports','global_search','manage_admins'))
        or (a.role = 'assistant_manager' and required_permission in ('farms','customers','animals','sensors','alerts','notifications','support'))
        or (a.role = 'admin' and required_permission in ('farms','customers','animals','sensors','alerts','notifications','support','billing','audit','reports','global_search'))
        or (a.role = 'support' and required_permission in ('support','customers'))
        or (a.role = 'billing' and required_permission in ('billing','customers'))
        or (a.role = 'operations' and required_permission in ('farms','customers','animals','sensors','alerts','notifications','support'))
        or coalesce((a.permissions ->> required_permission)::boolean, false) = true
      )
  );
$function$;

create or replace function public.admin_upsert_staff(p_user_id uuid, p_role text, p_active boolean, p_permissions jsonb default '{}'::jsonb)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_actor_role text;
begin
  select role into v_actor_role from public.admin_accounts where user_id=auth.uid() and active=true;
  if not public.is_admin_account('manage_admins') then raise exception 'Admin staff permission required'; end if;
  if p_role not in ('super_admin','manager','assistant_manager','admin','support','billing','operations') then raise exception 'Invalid role'; end if;
  if p_role='super_admin' and v_actor_role <> 'super_admin' then raise exception 'Only a super admin may assign super_admin'; end if;
  insert into public.admin_accounts(user_id,role,active,permissions)
  values(p_user_id,p_role,p_active,coalesce(p_permissions,'{}'::jsonb))
  on conflict(user_id) do update set role=excluded.role,active=excluded.active,permissions=excluded.permissions,updated_at=now();
end;
$function$;

create or replace function public.admin_auth_directory()
returns table(user_id uuid, email text, email_confirmed_at timestamptz, last_sign_in_at timestamptz, auth_created_at timestamptz)
language plpgsql
stable security definer
set search_path to 'public','auth'
as $function$
begin
  if not public.is_admin_account('manage_admins') then
    raise exception 'Admin account permission required';
  end if;
  return query
  select u.id, u.email::text, u.email_confirmed_at, u.last_sign_in_at, u.created_at
  from auth.users u
  order by u.created_at desc;
end;
$function$;

grant execute on function public.admin_auth_directory() to authenticated;
