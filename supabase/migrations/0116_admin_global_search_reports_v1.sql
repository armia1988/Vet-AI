-- Vet AI Admin global search and reporting center.

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
declare
  v_query text := btrim(coalesce(p_query, ''));
  v_limit integer := greatest(1, least(coalesce(p_limit, 80), 200));
begin
  if not public.is_admin_account(null) then raise exception 'Admin access required'; end if;
  if length(v_query) < 2 then return; end if;

  return query
  select s.entity_type, s.entity_id, s.title, s.subtitle, s.farm_id, s.status, s.created_at
  from (
    select 'customer'::text as entity_type, p.id::text as entity_id,
      coalesce(nullif(p.full_name, ''), 'Customer')::text as title,
      concat_ws(' • ', nullif(p.phone, ''), nullif(p.job_title, ''), nullif(p.preferred_language, ''))::text as subtitle,
      null::uuid as farm_id, coalesce(p.account_status, 'active')::text as status, p.created_at
    from public.profiles p
    where coalesce(p.full_name, '') ilike '%' || v_query || '%' or coalesce(p.phone, '') ilike '%' || v_query || '%'
       or coalesce(p.job_title, '') ilike '%' || v_query || '%' or p.id::text ilike '%' || v_query || '%'
    union all
    select 'farm'::text, f.id::text,
      concat_ws(' / ', nullif(f.company_name, ''), nullif(f.farm_name, ''))::text,
      concat_ws(' • ', nullif(f.country, ''), nullif(f.region, ''), nullif(f.subscription_status, ''))::text,
      f.id, coalesce(f.subscription_status, 'unknown')::text, f.created_at
    from public.farms f
    where coalesce(f.company_name, '') ilike '%' || v_query || '%' or coalesce(f.farm_name, '') ilike '%' || v_query || '%'
       or coalesce(f.country, '') ilike '%' || v_query || '%' or coalesce(f.region, '') ilike '%' || v_query || '%'
       or f.id::text ilike '%' || v_query || '%'
    union all
    select 'sensor'::text, sd.id::text, coalesce(nullif(sd.display_name, ''), nullif(sd.device_uid, ''), 'Sensor')::text,
      concat_ws(' • ', nullif(sd.device_uid, ''), nullif(sd.device_type, ''), nullif(sd.section_name, ''), nullif(f.company_name, ''), nullif(f.farm_name, ''))::text,
      sd.farm_id, case when sd.active then 'active' else 'disabled' end::text, sd.created_at
    from public.sensor_devices sd left join public.farms f on f.id=sd.farm_id
    where coalesce(sd.display_name, '') ilike '%' || v_query || '%' or coalesce(sd.device_uid, '') ilike '%' || v_query || '%'
       or coalesce(sd.device_type, '') ilike '%' || v_query || '%' or coalesce(sd.section_name, '') ilike '%' || v_query || '%'
       or coalesce(f.company_name, '') ilike '%' || v_query || '%' or coalesce(f.farm_name, '') ilike '%' || v_query || '%'
       or sd.id::text ilike '%' || v_query || '%'
    union all
    select 'animal'::text, a.id::text, coalesce(nullif(a.name, ''), nullif(a.external_id, ''), 'Animal')::text,
      concat_ws(' • ', nullif(a.external_id, ''), nullif(a.species, ''), nullif(a.breed, ''), nullif(f.company_name, ''), nullif(f.farm_name, ''))::text,
      a.farm_id, case when a.active then 'active' else 'inactive' end::text, a.created_at
    from public.animals a left join public.farms f on f.id=a.farm_id
    where coalesce(a.name, '') ilike '%' || v_query || '%' or coalesce(a.external_id, '') ilike '%' || v_query || '%'
       or coalesce(a.species, '') ilike '%' || v_query || '%' or coalesce(a.breed, '') ilike '%' || v_query || '%'
       or coalesce(f.company_name, '') ilike '%' || v_query || '%' or coalesce(f.farm_name, '') ilike '%' || v_query || '%'
       or a.id::text ilike '%' || v_query || '%'
    union all
    select 'support'::text, st.id::text, coalesce(nullif(st.subject, ''), 'Support thread')::text,
      concat_ws(' • ', nullif(f.company_name, ''), nullif(f.farm_name, ''), nullif(st.priority, ''))::text,
      st.farm_id, coalesce(st.status, 'open')::text, st.created_at
    from public.support_threads st left join public.farms f on f.id=st.farm_id
    where coalesce(st.subject, '') ilike '%' || v_query || '%' or coalesce(st.status, '') ilike '%' || v_query || '%'
       or coalesce(st.priority, '') ilike '%' || v_query || '%' or coalesce(f.company_name, '') ilike '%' || v_query || '%'
       or coalesce(f.farm_name, '') ilike '%' || v_query || '%' or st.id::text ilike '%' || v_query || '%'
    union all
    select 'payment'::text, pay.id::text, coalesce(nullif(pay.invoice_number, ''), 'Payment')::text,
      concat_ws(' • ', (pay.amount::text || ' ' || pay.currency), nullif(pay.provider, ''), nullif(f.company_name, ''), nullif(f.farm_name, ''))::text,
      pay.farm_id, coalesce(pay.status, 'unknown')::text, pay.created_at
    from public.payments pay left join public.farms f on f.id=pay.farm_id
    where coalesce(pay.invoice_number, '') ilike '%' || v_query || '%' or coalesce(pay.provider_payment_id, '') ilike '%' || v_query || '%'
       or coalesce(pay.provider, '') ilike '%' || v_query || '%' or coalesce(pay.description, '') ilike '%' || v_query || '%'
       or coalesce(f.company_name, '') ilike '%' || v_query || '%' or coalesce(f.farm_name, '') ilike '%' || v_query || '%'
       or pay.id::text ilike '%' || v_query || '%'
    union all
    select 'alert'::text, al.id::text, coalesce(nullif(al.title, ''), 'Alert')::text,
      concat_ws(' • ', al.risk::text, nullif(al.metric, ''), nullif(f.company_name, ''), nullif(f.farm_name, ''))::text,
      al.farm_id, coalesce(al.admin_status, case when al.acknowledged_at is null then 'open' else 'acknowledged' end)::text, al.created_at
    from public.alerts al left join public.farms f on f.id=al.farm_id
    where coalesce(al.title, '') ilike '%' || v_query || '%' or coalesce(al.details, '') ilike '%' || v_query || '%'
       or coalesce(al.metric, '') ilike '%' || v_query || '%' or coalesce(f.company_name, '') ilike '%' || v_query || '%'
       or coalesce(f.farm_name, '') ilike '%' || v_query || '%' or al.id::text ilike '%' || v_query || '%'
  ) s
  order by s.created_at desc nulls last limit v_limit;
end;
$$;
revoke all on function public.admin_global_search(text, integer) from public, anon;
grant execute on function public.admin_global_search(text, integer) to authenticated;

create or replace function public.admin_reports_snapshot(p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare
  v_days integer := greatest(7, least(coalesce(p_days, 30), 180));
  v_start_date date;
  v_offline_minutes integer := 10;
  v_daily jsonb; v_revenue jsonb; v_subscriptions jsonb; v_languages jsonb; v_sensor_fleet jsonb; v_top_alert_farms jsonb;
begin
  if not public.is_admin_account(null) then raise exception 'Admin access required'; end if;
  v_start_date := current_date - (v_days - 1);
  select coalesce((select (value #>> '{}')::integer from public.admin_system_settings where key='sensor_offline_minutes'),10) into v_offline_minutes;

  select coalesce(jsonb_agg(jsonb_build_object(
    'date', d.day,
    'new_customers', (select count(*) from public.profiles p where p.created_at::date=d.day),
    'new_farms', (select count(*) from public.farms f where f.created_at::date=d.day),
    'alerts', (select count(*) from public.alerts a where a.created_at::date=d.day),
    'red_alerts', (select count(*) from public.alerts a where a.created_at::date=d.day and a.risk='red'),
    'orange_alerts', (select count(*) from public.alerts a where a.created_at::date=d.day and a.risk='orange'),
    'support_new', (select count(*) from public.support_threads st where st.created_at::date=d.day),
    'payments_paid', (select count(*) from public.payments p where p.status='paid' and p.paid_at::date=d.day),
    'payments_paid_amount', (select coalesce(sum(p.amount),0) from public.payments p where p.status='paid' and p.paid_at::date=d.day)
  ) order by d.day),'[]'::jsonb) into v_daily
  from generate_series(v_start_date,current_date,interval '1 day') g(day_ts)
  cross join lateral (select g.day_ts::date as day) d;

  select coalesce(jsonb_agg(jsonb_build_object('currency',currency,'amount',amount,'count',payment_count) order by currency),'[]'::jsonb) into v_revenue
  from (select p.currency,coalesce(sum(p.amount),0) amount,count(*) payment_count from public.payments p where p.status='paid' and coalesce(p.paid_at,p.created_at)>=v_start_date::timestamptz group by p.currency) x;
  select coalesce(jsonb_agg(jsonb_build_object('status',status,'count',cnt) order by cnt desc),'[]'::jsonb) into v_subscriptions from (select coalesce(status,'unknown') status,count(*) cnt from public.farm_subscriptions group by coalesce(status,'unknown')) x;
  select coalesce(jsonb_agg(jsonb_build_object('language',language,'count',cnt) order by cnt desc),'[]'::jsonb) into v_languages from (select coalesce(nullif(preferred_language,''),'unknown') language,count(*) cnt from public.profiles group by coalesce(nullif(preferred_language,''),'unknown')) x;
  select coalesce(jsonb_agg(jsonb_build_object('device_type',device_type,'total',total,'online',online,'offline',offline,'disabled',disabled) order by total desc),'[]'::jsonb) into v_sensor_fleet
  from (select coalesce(nullif(sd.device_type,''),'unknown') device_type,count(*) total,
    count(*) filter(where sd.active=true and sd.last_seen_at>=now()-make_interval(mins=>v_offline_minutes)) online,
    count(*) filter(where sd.active=true and (sd.last_seen_at is null or sd.last_seen_at<now()-make_interval(mins=>v_offline_minutes))) offline,
    count(*) filter(where sd.active=false) disabled from public.sensor_devices sd group by coalesce(nullif(sd.device_type,''),'unknown')) x;
  select coalesce(jsonb_agg(jsonb_build_object('farm_id',farm_id,'company',company_name,'farm',farm_name,'alerts',alerts) order by alerts desc),'[]'::jsonb) into v_top_alert_farms
  from (select f.id farm_id,f.company_name,f.farm_name,count(a.id) alerts from public.farms f join public.alerts a on a.farm_id=f.id and a.created_at>=v_start_date::timestamptz group by f.id,f.company_name,f.farm_name order by count(a.id) desc limit 10) x;

  return jsonb_build_object(
    'generated_at',now(),'days',v_days,'start_date',v_start_date,
    'summary',jsonb_build_object(
      'new_customers',(select count(*) from public.profiles where created_at>=v_start_date::timestamptz),
      'new_farms',(select count(*) from public.farms where created_at>=v_start_date::timestamptz),
      'new_animals',(select count(*) from public.animals where created_at>=v_start_date::timestamptz),
      'alerts_total',(select count(*) from public.alerts where created_at>=v_start_date::timestamptz),
      'red_alerts',(select count(*) from public.alerts where created_at>=v_start_date::timestamptz and risk='red'),
      'orange_alerts',(select count(*) from public.alerts where created_at>=v_start_date::timestamptz and risk='orange'),
      'support_new',(select count(*) from public.support_threads where created_at>=v_start_date::timestamptz),
      'support_open_now',(select count(*) from public.support_threads where status<>'closed'),
      'payments_paid_count',(select count(*) from public.payments where status='paid' and coalesce(paid_at,created_at)>=v_start_date::timestamptz),
      'payments_failed_count',(select count(*) from public.payments where status='failed' and created_at>=v_start_date::timestamptz),
      'active_subscriptions',(select count(*) from public.farm_subscriptions where status='active'),
      'past_due_subscriptions',(select count(*) from public.farm_subscriptions where status='past_due'),
      'sensors_online_now',(select count(*) from public.sensor_devices where active=true and last_seen_at>=now()-make_interval(mins=>v_offline_minutes)),
      'sensors_offline_now',(select count(*) from public.sensor_devices where active=true and (last_seen_at is null or last_seen_at<now()-make_interval(mins=>v_offline_minutes)))
    ),
    'daily',v_daily,'revenue_by_currency',v_revenue,'subscription_statuses',v_subscriptions,'customer_languages',v_languages,'sensor_fleet',v_sensor_fleet,'top_alert_farms',v_top_alert_farms
  );
end;
$$;
revoke all on function public.admin_reports_snapshot(integer) from public, anon;
grant execute on function public.admin_reports_snapshot(integer) to authenticated;
