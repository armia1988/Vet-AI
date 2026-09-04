-- Vet AI V20 reliability fix.
-- 1) Sensor-alert rules need explicit authenticated CRUD grants; without them
--    RLS policies exist but the REST query can still fail at the privilege layer.
-- 2) Alerts use Supabase Postgres Changes, so the alerts table must be part of
--    the supabase_realtime publication.

grant select, insert, update, delete on table public.sensor_alert_rules to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'alerts'
  ) then
    alter publication supabase_realtime add table public.alerts;
  end if;
end
$$;
