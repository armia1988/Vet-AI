-- Vet AI Admin role-based access control v2.

create or replace function public.is_admin_account(required_permission text default null)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.admin_accounts a
    where a.user_id = auth.uid()
      and a.active = true
      and (
        required_permission is null
        or a.role = 'super_admin'
        or (a.role = 'admin' and required_permission in ('farms','customers','animals','sensors','alerts','notifications','support','billing','audit'))
        or (a.role = 'support' and required_permission in ('support','customers'))
        or (a.role = 'billing' and required_permission in ('billing','customers'))
        or (a.role = 'operations' and required_permission in ('farms','customers','animals','sensors','alerts','notifications','support'))
        or coalesce((a.permissions ->> required_permission)::boolean, false) = true
      )
  );
$$;
grant execute on function public.is_admin_account(text) to authenticated;

create or replace function public.admin_upsert_staff(
  p_user_id uuid,
  p_role text,
  p_active boolean,
  p_permissions jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_actor_role text;
begin
  select role into v_actor_role from public.admin_accounts where user_id=auth.uid() and active=true;
  if not public.is_admin_account('manage_admins') then raise exception 'Admin staff permission required'; end if;
  if p_role not in ('super_admin','admin','support','billing','operations') then raise exception 'Invalid role'; end if;
  if p_role='super_admin' and v_actor_role <> 'super_admin' then raise exception 'Only a super admin may assign super_admin'; end if;
  insert into public.admin_accounts(user_id,role,active,permissions)
  values(p_user_id,p_role,p_active,coalesce(p_permissions,'{}'::jsonb))
  on conflict(user_id) do update set role=excluded.role,active=excluded.active,permissions=excluded.permissions,updated_at=now();
end; $$;
revoke all on function public.admin_upsert_staff(uuid,text,boolean,jsonb) from public,anon;
grant execute on function public.admin_upsert_staff(uuid,text,boolean,jsonb) to authenticated;

create or replace function public.admin_remove_staff(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_actor_role text; v_target_role text;
begin
  select role into v_actor_role from public.admin_accounts where user_id=auth.uid() and active=true;
  if not public.is_admin_account('manage_admins') then raise exception 'Admin staff permission required'; end if;
  select role into v_target_role from public.admin_accounts where user_id=p_user_id;
  if v_target_role='super_admin' and v_actor_role <> 'super_admin' then raise exception 'Only a super admin may remove a super admin'; end if;
  if p_user_id=auth.uid() then raise exception 'You cannot remove your own admin access here'; end if;
  delete from public.admin_accounts where user_id=p_user_id;
end; $$;
revoke all on function public.admin_remove_staff(uuid) from public,anon;
grant execute on function public.admin_remove_staff(uuid) to authenticated;
