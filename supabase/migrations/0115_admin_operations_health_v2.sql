-- Vet AI live admin operations health and server-enforced maintenance gate.

create or replace function public.admin_operations_health()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_offline_minutes integer := 10;
  v_settings jsonb := '{}'::jsonb;
  v_result jsonb;
begin
  if not public.is_admin_account(null) then raise exception 'Admin access required'; end if;

  select coalesce((select (value #>> '{}')::integer from public.admin_system_settings where key='sensor_offline_minutes'),10)
    into v_offline_minutes;
  select coalesce(jsonb_object_agg(key,value),'{}'::jsonb)
    into v_settings
  from public.admin_system_settings;

  select jsonb_build_object(
    'generated_at', now(),
    'system_settings', v_settings,
    'customers_total', (select count(*) from public.profiles),
    'customers_suspended', (select count(*) from public.profiles where account_status='suspended'),
    'customers_closed', (select count(*) from public.profiles where account_status='closed'),
    'farms_total', (select count(*) from public.farms),
    'animals_active', (select count(*) from public.animals where active=true),
    'sensors_total', (select count(*) from public.sensor_devices),
    'sensors_active', (select count(*) from public.sensor_devices where active=true),
    'sensors_offline', (select count(*) from public.sensor_devices where active=true and (last_seen_at is null or last_seen_at < now() - make_interval(mins => v_offline_minutes))),
    'sensors_disabled', (select count(*) from public.sensor_devices where active=false),
    'alerts_open', (select count(*) from public.alerts where coalesce(admin_status,'open')='open'),
    'alerts_red_open', (select count(*) from public.alerts where risk='red' and coalesce(admin_status,'open')='open'),
    'alerts_orange_open', (select count(*) from public.alerts where risk='orange' and coalesce(admin_status,'open')='open'),
    'support_open', (select count(*) from public.support_threads where status <> 'closed'),
    'support_urgent', (select count(*) from public.support_threads where status <> 'closed' and priority='urgent'),
    'subscriptions_active', (select count(*) from public.farm_subscriptions where status='active'),
    'subscriptions_past_due', (select count(*) from public.farm_subscriptions where status='past_due'),
    'payments_pending', (select count(*) from public.payments where status='pending'),
    'payments_failed', (select count(*) from public.payments where status='failed'),
    'customer_push_devices_enabled', (select count(*) from public.push_devices where enabled=true),
    'customer_push_failures_24h', (select count(*) from public.push_deliveries where status='failed' and created_at >= now()-interval '24 hours'),
    'admin_push_devices_enabled', (select count(*) from public.admin_push_devices where enabled=true),
    'audit_events_24h', (select count(*) from public.admin_audit_log where created_at >= now()-interval '24 hours')
  ) into v_result;
  return v_result;
end;
$$;
revoke all on function public.admin_operations_health() from public,anon;
grant execute on function public.admin_operations_health() to authenticated;

create or replace function private.is_farm_member(target_farm uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    (
      public.is_admin_account(null)
      or (
        coalesce((select p.account_status = 'active' from public.profiles p where p.id = auth.uid()), true)
        and not coalesce((select (s.value #>> '{}')::boolean from public.admin_system_settings s where s.key='maintenance_mode'),false)
        and (
          exists (select 1 from public.farms f where f.id = target_farm and f.owner_id = auth.uid())
          or exists (select 1 from public.farm_members fm where fm.farm_id = target_farm and fm.user_id = auth.uid())
        )
      )
    );
$$;
