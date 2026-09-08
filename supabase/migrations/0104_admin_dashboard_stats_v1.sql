-- Vet AI Admin Dashboard aggregate RPCs

create or replace function public.admin_dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare result jsonb;
begin
  if not public.is_admin_account(null) then raise exception 'admin_required'; end if;
  select jsonb_build_object(
    'customers', (select count(*) from public.profiles),
    'farms', (select count(*) from public.farms),
    'animals', (select count(*) from public.animals where active = true),
    'sensors_total', (select count(*) from public.sensor_devices),
    'sensors_active', (select count(*) from public.sensor_devices where active = true),
    'sensors_online', (select count(*) from public.sensor_devices where active = true and last_seen_at >= now() - interval '10 minutes'),
    'sensors_offline', (select count(*) from public.sensor_devices where active = true and (last_seen_at is null or last_seen_at < now() - interval '10 minutes')),
    'red_alerts_24h', (select count(*) from public.alerts where risk::text = 'red' and created_at >= now() - interval '24 hours'),
    'orange_alerts_24h', (select count(*) from public.alerts where risk::text = 'orange' and created_at >= now() - interval '24 hours'),
    'support_open', (select count(*) from public.support_threads where status <> 'closed'),
    'support_unread', (select coalesce(sum(unread_by_admin),0) from public.support_threads),
    'subscriptions_active', (select count(*) from public.farm_subscriptions where status = 'active'),
    'subscriptions_past_due', (select count(*) from public.farm_subscriptions where status = 'past_due'),
    'payments_pending', (select count(*) from public.payments where status = 'pending'),
    'payments_paid_total', (select coalesce(sum(amount),0) from public.payments where status = 'paid')
  ) into result;
  return result;
end;
$$;
grant execute on function public.admin_dashboard_stats() to authenticated;

create or replace function public.admin_mark_support_read(p_thread_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_account('support') then raise exception 'admin_required'; end if;
  update public.support_threads set unread_by_admin = 0 where id = p_thread_id;
end;
$$;
grant execute on function public.admin_mark_support_read(uuid) to authenticated;
