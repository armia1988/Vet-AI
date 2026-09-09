create or replace function public.admin_reports_snapshot(p_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_days integer := greatest(7, least(coalesce(p_days, 30), 180));
  v_start_date date;
  v_offline_minutes integer := 10;
  v_daily jsonb;
  v_revenue jsonb;
  v_subscriptions jsonb;
  v_languages jsonb;
  v_sensor_fleet jsonb;
  v_top_alert_farms jsonb;
  v_sensor_live jsonb;
  v_farm_health jsonb;
  v_ai_models jsonb;
  v_assessment_risk jsonb;
  v_metric_quality jsonb;
begin
  if not public.is_admin_account('reports') then
    raise exception 'Reports permission required';
  end if;

  v_start_date := current_date - (v_days - 1);
  select coalesce((select (value #>> '{}')::integer from public.admin_system_settings where key='sensor_offline_minutes'),10)
    into v_offline_minutes;

  select coalesce(jsonb_agg(jsonb_build_object(
    'date', d.day_value,
    'new_customers', (select count(*) from public.profiles p where p.created_at::date = d.day_value),
    'new_farms', (select count(*) from public.farms f where f.created_at::date = d.day_value),
    'alerts', (select count(*) from public.alerts a where a.created_at::date = d.day_value),
    'red_alerts', (select count(*) from public.alerts a where a.created_at::date = d.day_value and a.risk='red'),
    'orange_alerts', (select count(*) from public.alerts a where a.created_at::date = d.day_value and a.risk='orange'),
    'support_new', (select count(*) from public.support_threads st where st.created_at::date = d.day_value),
    'assessments', (select count(*) from public.assessments a where a.created_at::date = d.day_value),
    'ai_assessments', (select count(*) from public.assessments a where a.created_at::date = d.day_value and a.ai_generated_at is not null),
    'sensor_readings', (select count(*) from public.sensor_readings sr where sr.recorded_at::date = d.day_value),
    'payments_paid', (select count(*) from public.payments p where p.status='paid' and p.paid_at::date = d.day_value),
    'payments_paid_amount', (select coalesce(sum(p.amount),0) from public.payments p where p.status='paid' and p.paid_at::date = d.day_value)
  ) order by d.day_value), '[]'::jsonb)
  into v_daily
  from generate_series(v_start_date, current_date, interval '1 day') g(day_ts)
  cross join lateral (select g.day_ts::date as day_value) d;

  select coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount, 'count', payment_count) order by currency), '[]'::jsonb)
  into v_revenue
  from (
    select p.currency, coalesce(sum(p.amount),0) as amount, count(*) as payment_count
    from public.payments p
    where p.status='paid' and coalesce(p.paid_at,p.created_at) >= v_start_date::timestamptz
    group by p.currency
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object('status', status, 'count', cnt) order by cnt desc), '[]'::jsonb)
  into v_subscriptions
  from (select coalesce(status,'unknown') as status, count(*) as cnt from public.farm_subscriptions group by coalesce(status,'unknown')) x;

  select coalesce(jsonb_agg(jsonb_build_object('language', language, 'count', cnt) order by cnt desc), '[]'::jsonb)
  into v_languages
  from (select coalesce(nullif(preferred_language,''),'unknown') as language, count(*) as cnt from public.profiles group by coalesce(nullif(preferred_language,''),'unknown')) x;

  select coalesce(jsonb_agg(jsonb_build_object('device_type', device_type, 'total', total, 'online', online, 'offline', offline, 'disabled', disabled) order by total desc), '[]'::jsonb)
  into v_sensor_fleet
  from (
    select coalesce(nullif(sd.device_type,''),'unknown') as device_type,
      count(*) as total,
      count(*) filter (where sd.active=true and sd.last_seen_at >= now()-make_interval(mins=>v_offline_minutes)) as online,
      count(*) filter (where sd.active=true and (sd.last_seen_at is null or sd.last_seen_at < now()-make_interval(mins=>v_offline_minutes))) as offline,
      count(*) filter (where sd.active=false) as disabled
    from public.sensor_devices sd
    group by coalesce(nullif(sd.device_type,''),'unknown')
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object('farm_id', farm_id, 'company', company_name, 'farm', farm_name, 'alerts', alerts, 'red', red, 'orange', orange) order by alerts desc), '[]'::jsonb)
  into v_top_alert_farms
  from (
    select f.id as farm_id, f.company_name, f.farm_name,
      count(a.id) as alerts,
      count(a.id) filter (where a.risk='red') as red,
      count(a.id) filter (where a.risk='orange') as orange
    from public.farms f
    join public.alerts a on a.farm_id=f.id and a.created_at >= v_start_date::timestamptz
    group by f.id,f.company_name,f.farm_name
    order by count(a.id) desc
    limit 15
  ) x;

  with latest as (
    select distinct on (sr.device_id)
      sr.id, sr.device_id, sr.farm_id, sr.recorded_at,
      sr.body_temperature_c, sr.ambient_temperature_c, sr.humidity_percent,
      sr.activity_index, sr.steps, sr.distance_from_herd_m,
      sr.lying_minutes, sr.feeding_minutes, sr.rumination_minutes,
      sr.oxygen_percent, sr.battery_voltage_v, sr.battery_percent, sr.charging
    from public.sensor_readings sr
    order by sr.device_id, sr.recorded_at desc
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'device_id', sd.id,
    'device_uid', sd.device_uid,
    'display_name', coalesce(nullif(sd.display_name,''), sd.device_uid),
    'device_type', sd.device_type,
    'section', sd.section_name,
    'farm_id', sd.farm_id,
    'company', f.company_name,
    'farm', f.farm_name,
    'active', sd.active,
    'online', (sd.active and sd.last_seen_at is not null and sd.last_seen_at >= now()-make_interval(mins=>v_offline_minutes)),
    'last_seen_at', sd.last_seen_at,
    'recorded_at', lr.recorded_at,
    'age_seconds', case when lr.recorded_at is null then null else greatest(0, extract(epoch from (now()-lr.recorded_at))::bigint) end,
    'body_temperature_c', lr.body_temperature_c,
    'ambient_temperature_c', lr.ambient_temperature_c,
    'humidity_percent', lr.humidity_percent,
    'activity_index', lr.activity_index,
    'steps', lr.steps,
    'distance_from_herd_m', lr.distance_from_herd_m,
    'lying_minutes', lr.lying_minutes,
    'feeding_minutes', lr.feeding_minutes,
    'rumination_minutes', lr.rumination_minutes,
    'oxygen_percent', lr.oxygen_percent,
    'battery_voltage_v', lr.battery_voltage_v,
    'battery_percent', lr.battery_percent,
    'charging', lr.charging,
    'telemetry_quality_percent', case when lr.id is null then 0 else round(100.0 * (
      (lr.body_temperature_c is not null)::int +
      (lr.ambient_temperature_c is not null)::int +
      (lr.humidity_percent is not null)::int +
      (lr.activity_index is not null)::int +
      (lr.battery_percent is not null)::int +
      (lr.oxygen_percent is not null)::int +
      (lr.rumination_minutes is not null)::int +
      (lr.distance_from_herd_m is not null)::int
    ) / 8.0, 1) end,
    'recent_risk', (
      select a.risk::text
      from public.alerts a
      join public.sensor_readings rr on rr.id=a.sensor_reading_id
      where rr.device_id=sd.id and a.created_at >= v_start_date::timestamptz
      order by a.created_at desc limit 1
    )
  ) order by f.company_name, f.farm_name, coalesce(sd.display_name,sd.device_uid)), '[]'::jsonb)
  into v_sensor_live
  from public.sensor_devices sd
  join public.farms f on f.id=sd.farm_id
  left join latest lr on lr.device_id=sd.id;

  with latest as (
    select distinct on (sr.device_id) sr.*
    from public.sensor_readings sr
    order by sr.device_id, sr.recorded_at desc
  ), sensor_agg as (
    select sd.farm_id,
      count(*) as sensors_total,
      count(*) filter (where sd.active=true and sd.last_seen_at >= now()-make_interval(mins=>v_offline_minutes)) as sensors_online,
      count(*) filter (where sd.active=true and (sd.last_seen_at is null or sd.last_seen_at < now()-make_interval(mins=>v_offline_minutes))) as sensors_offline,
      count(lr.id) as sensors_with_telemetry,
      round(avg(lr.body_temperature_c),2) as avg_body_temperature_c,
      round(avg(lr.ambient_temperature_c),2) as avg_ambient_temperature_c,
      round(avg(lr.humidity_percent),2) as avg_humidity_percent,
      round(avg(lr.battery_percent),1) as avg_battery_percent
    from public.sensor_devices sd
    left join latest lr on lr.device_id=sd.id
    group by sd.farm_id
  ), alert_agg as (
    select farm_id,
      count(*) as alerts,
      count(*) filter (where risk='red') as red,
      count(*) filter (where risk='orange') as orange
    from public.alerts
    where created_at >= v_start_date::timestamptz
    group by farm_id
  ), assessment_agg as (
    select farm_id,
      count(*) as assessments,
      count(*) filter (where ai_generated_at is not null) as ai_assessments,
      count(*) filter (where urgent_vet_review=true) as urgent_vet_review,
      count(*) filter (where lab_confirmation_required=true) as lab_confirmation_required
    from public.assessments
    where created_at >= v_start_date::timestamptz
    group by farm_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'farm_id', f.id,
    'company', f.company_name,
    'farm', f.farm_name,
    'sensors_total', coalesce(sa.sensors_total,0),
    'sensors_online', coalesce(sa.sensors_online,0),
    'sensors_offline', coalesce(sa.sensors_offline,0),
    'sensors_with_telemetry', coalesce(sa.sensors_with_telemetry,0),
    'avg_body_temperature_c', sa.avg_body_temperature_c,
    'avg_ambient_temperature_c', sa.avg_ambient_temperature_c,
    'avg_humidity_percent', sa.avg_humidity_percent,
    'avg_battery_percent', sa.avg_battery_percent,
    'alerts', coalesce(aa.alerts,0),
    'red_alerts', coalesce(aa.red,0),
    'orange_alerts', coalesce(aa.orange,0),
    'assessments', coalesce(asa.assessments,0),
    'ai_assessments', coalesce(asa.ai_assessments,0),
    'urgent_vet_review', coalesce(asa.urgent_vet_review,0),
    'lab_confirmation_required', coalesce(asa.lab_confirmation_required,0)
  ) order by coalesce(aa.red,0) desc, coalesce(aa.alerts,0) desc, f.company_name), '[]'::jsonb)
  into v_farm_health
  from public.farms f
  left join sensor_agg sa on sa.farm_id=f.id
  left join alert_agg aa on aa.farm_id=f.id
  left join assessment_agg asa on asa.farm_id=f.id;

  select coalesce(jsonb_agg(jsonb_build_object('model', model, 'count', cnt) order by cnt desc), '[]'::jsonb)
  into v_ai_models
  from (
    select coalesce(nullif(ai_model,''),'unknown') model, count(*) cnt
    from public.assessments
    where ai_generated_at is not null and created_at >= v_start_date::timestamptz
    group by coalesce(nullif(ai_model,''),'unknown')
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object('risk', risk, 'count', cnt) order by cnt desc), '[]'::jsonb)
  into v_assessment_risk
  from (
    select risk::text risk, count(*) cnt
    from public.assessments
    where created_at >= v_start_date::timestamptz
    group by risk
  ) x;

  with metric_rows as (
    select 'body_temperature_c' metric, count(body_temperature_c)::bigint samples, avg(body_temperature_c) avg_value, min(body_temperature_c) min_value, max(body_temperature_c) max_value from public.sensor_readings where recorded_at >= v_start_date::timestamptz
    union all
    select 'ambient_temperature_c', count(ambient_temperature_c), avg(ambient_temperature_c), min(ambient_temperature_c), max(ambient_temperature_c) from public.sensor_readings where recorded_at >= v_start_date::timestamptz
    union all
    select 'humidity_percent', count(humidity_percent), avg(humidity_percent), min(humidity_percent), max(humidity_percent) from public.sensor_readings where recorded_at >= v_start_date::timestamptz
    union all
    select 'activity_index', count(activity_index), avg(activity_index), min(activity_index), max(activity_index) from public.sensor_readings where recorded_at >= v_start_date::timestamptz
    union all
    select 'battery_percent', count(battery_percent), avg(battery_percent), min(battery_percent), max(battery_percent) from public.sensor_readings where recorded_at >= v_start_date::timestamptz
    union all
    select 'oxygen_percent', count(oxygen_percent), avg(oxygen_percent), min(oxygen_percent), max(oxygen_percent) from public.sensor_readings where recorded_at >= v_start_date::timestamptz
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'metric', metric,
    'samples', samples,
    'avg', case when avg_value is null then null else round(avg_value,2) end,
    'min', case when min_value is null then null else round(min_value,2) end,
    'max', case when max_value is null then null else round(max_value,2) end
  )), '[]'::jsonb)
  into v_metric_quality
  from metric_rows;

  return jsonb_build_object(
    'generated_at', now(),
    'days', v_days,
    'start_date', v_start_date,
    'offline_minutes', v_offline_minutes,
    'summary', jsonb_build_object(
      'new_customers', (select count(*) from public.profiles where created_at >= v_start_date::timestamptz),
      'new_farms', (select count(*) from public.farms where created_at >= v_start_date::timestamptz),
      'new_animals', (select count(*) from public.animals where created_at >= v_start_date::timestamptz),
      'alerts_total', (select count(*) from public.alerts where created_at >= v_start_date::timestamptz),
      'red_alerts', (select count(*) from public.alerts where created_at >= v_start_date::timestamptz and risk='red'),
      'orange_alerts', (select count(*) from public.alerts where created_at >= v_start_date::timestamptz and risk='orange'),
      'support_new', (select count(*) from public.support_threads where created_at >= v_start_date::timestamptz),
      'support_open_now', (select count(*) from public.support_threads where status <> 'closed'),
      'payments_paid_count', (select count(*) from public.payments where status='paid' and coalesce(paid_at,created_at) >= v_start_date::timestamptz),
      'payments_failed_count', (select count(*) from public.payments where status='failed' and created_at >= v_start_date::timestamptz),
      'active_subscriptions', (select count(*) from public.farm_subscriptions where status='active'),
      'past_due_subscriptions', (select count(*) from public.farm_subscriptions where status='past_due'),
      'sensors_total', (select count(*) from public.sensor_devices),
      'sensors_active', (select count(*) from public.sensor_devices where active=true),
      'sensors_online_now', (select count(*) from public.sensor_devices where active=true and last_seen_at >= now()-make_interval(mins=>v_offline_minutes)),
      'sensors_offline_now', (select count(*) from public.sensor_devices where active=true and (last_seen_at is null or last_seen_at < now()-make_interval(mins=>v_offline_minutes))),
      'sensor_readings', (select count(*) from public.sensor_readings where recorded_at >= v_start_date::timestamptz),
      'sensors_with_recent_telemetry', (select count(distinct device_id) from public.sensor_readings where recorded_at >= now()-interval '15 minutes'),
      'low_battery_readings', (select count(*) from public.sensor_readings where recorded_at >= v_start_date::timestamptz and battery_percent is not null and battery_percent < 20),
      'avg_body_temperature_c', (select round(avg(body_temperature_c),2) from public.sensor_readings where recorded_at >= v_start_date::timestamptz and body_temperature_c is not null),
      'avg_ambient_temperature_c', (select round(avg(ambient_temperature_c),2) from public.sensor_readings where recorded_at >= v_start_date::timestamptz and ambient_temperature_c is not null),
      'avg_humidity_percent', (select round(avg(humidity_percent),2) from public.sensor_readings where recorded_at >= v_start_date::timestamptz and humidity_percent is not null),
      'assessments_total', (select count(*) from public.assessments where created_at >= v_start_date::timestamptz),
      'ai_assessments', (select count(*) from public.assessments where created_at >= v_start_date::timestamptz and ai_generated_at is not null),
      'urgent_vet_review', (select count(*) from public.assessments where created_at >= v_start_date::timestamptz and urgent_vet_review=true),
      'isolation_recommended', (select count(*) from public.assessments where created_at >= v_start_date::timestamptz and isolation_recommended=true),
      'lab_confirmation_required', (select count(*) from public.assessments where created_at >= v_start_date::timestamptz and lab_confirmation_required=true)
    ),
    'daily', v_daily,
    'revenue_by_currency', v_revenue,
    'subscription_statuses', v_subscriptions,
    'customer_languages', v_languages,
    'sensor_fleet', v_sensor_fleet,
    'top_alert_farms', v_top_alert_farms,
    'latest_sensor_telemetry', v_sensor_live,
    'farm_health', v_farm_health,
    'ai_models', v_ai_models,
    'assessment_risk', v_assessment_risk,
    'metric_quality', v_metric_quality
  );
end;
$function$;

grant execute on function public.admin_reports_snapshot(integer) to authenticated;
