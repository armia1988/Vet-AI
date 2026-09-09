-- Vet AI admin RBAC hardening for search, reports and UI capability routing.

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
        or (a.role = 'admin' and required_permission in (
          'farms','customers','animals','sensors','alerts','notifications',
          'support','billing','audit','reports','global_search'
        ))
        or (a.role = 'support' and required_permission in ('support','customers'))
        or (a.role = 'billing' and required_permission in ('billing','customers'))
        or (a.role = 'operations' and required_permission in (
          'farms','customers','animals','sensors','alerts','notifications','support'
        ))
        or coalesce((a.permissions ->> required_permission)::boolean, false) = true
      )
  );
$$;
grant execute on function public.is_admin_account(text) to authenticated;

create or replace function public.my_admin_access()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role text;
  v_active boolean;
  v_permissions jsonb;
begin
  select a.role, a.active, coalesce(a.permissions, '{}'::jsonb)
    into v_role, v_active, v_permissions
  from public.admin_accounts a
  where a.user_id = auth.uid();

  if coalesce(v_active, false) = false then
    return jsonb_build_object(
      'active', false,
      'role', null,
      'permissions', '{}'::jsonb,
      'capabilities', '{}'::jsonb
    );
  end if;

  return jsonb_build_object(
    'active', true,
    'role', v_role,
    'permissions', v_permissions,
    'capabilities', jsonb_build_object(
      'overview', public.is_admin_account(null),
      'farms', public.is_admin_account('farms'),
      'customers', public.is_admin_account('customers'),
      'animals', public.is_admin_account('animals'),
      'sensors', public.is_admin_account('sensors'),
      'alerts', public.is_admin_account('alerts'),
      'notifications', public.is_admin_account('notifications'),
      'support', public.is_admin_account('support'),
      'billing', public.is_admin_account('billing'),
      'manage_admins', public.is_admin_account('manage_admins'),
      'audit', public.is_admin_account('audit'),
      'global_search', public.is_admin_account('global_search'),
      'reports', public.is_admin_account('reports'),
      'system', public.is_admin_account('system')
    )
  );
end;
$$;
revoke all on function public.my_admin_access() from public, anon;
grant execute on function public.my_admin_access() to authenticated;

-- Preserve the v1 implementations from migration 0116 behind stricter gates.
do $$
begin
  if to_regprocedure('public.admin_global_search_core_v1(text,integer)') is null
     and to_regprocedure('public.admin_global_search(text,integer)') is not null then
    alter function public.admin_global_search(text, integer)
      rename to admin_global_search_core_v1;
  end if;

  if to_regprocedure('public.admin_reports_snapshot_core_v1(integer)') is null
     and to_regprocedure('public.admin_reports_snapshot(integer)') is not null then
    alter function public.admin_reports_snapshot(integer)
      rename to admin_reports_snapshot_core_v1;
  end if;
end;
$$;

revoke all on function public.admin_global_search_core_v1(text, integer) from public, anon, authenticated;
revoke all on function public.admin_reports_snapshot_core_v1(integer) from public, anon, authenticated;

create or replace function public.admin_global_search(
  p_query text,
  p_limit integer default 80
)
returns table(
  entity_type text,
  entity_id text,
  title text,
  subtitle text,
  farm_id uuid,
  status text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  -- Global cross-entity search is intentionally restricted to full admins.
  if not public.is_admin_account('global_search') then
    raise exception 'Global search permission required';
  end if;

  return query
  select *
  from public.admin_global_search_core_v1(p_query, p_limit);
end;
$$;
revoke all on function public.admin_global_search(text, integer) from public, anon;
grant execute on function public.admin_global_search(text, integer) to authenticated;

create or replace function public.admin_reports_snapshot(p_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin_account('reports') then
    raise exception 'Reports permission required';
  end if;
  return public.admin_reports_snapshot_core_v1(p_days);
end;
$$;
revoke all on function public.admin_reports_snapshot(integer) from public, anon;
grant execute on function public.admin_reports_snapshot(integer) to authenticated;
