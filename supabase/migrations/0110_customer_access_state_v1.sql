-- Vet AI customer access state used by the app shell and signup flow.

create or replace function public.customer_access_state()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_status text := 'active';
  v_maintenance boolean := false;
begin
  if auth.uid() is not null then
    select coalesce(account_status,'active') into v_status
    from public.profiles where id=auth.uid();
    v_status := coalesce(v_status,'active');
  end if;
  select coalesce((select value::text::boolean from public.admin_system_settings where key='maintenance_mode'),false)
    into v_maintenance;
  return jsonb_build_object('account_status',v_status,'maintenance_mode',v_maintenance);
end; $$;
revoke all on function public.customer_access_state() from public,anon;
grant execute on function public.customer_access_state() to authenticated;

create or replace function public.public_signup_state()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_signup boolean := true;
  v_maintenance boolean := false;
begin
  select coalesce((select value::text::boolean from public.admin_system_settings where key='customer_signup_enabled'),true) into v_signup;
  select coalesce((select value::text::boolean from public.admin_system_settings where key='maintenance_mode'),false) into v_maintenance;
  return jsonb_build_object('signup_enabled',v_signup,'maintenance_mode',v_maintenance);
end; $$;
revoke all on function public.public_signup_state() from public;
grant execute on function public.public_signup_state() to anon,authenticated;
