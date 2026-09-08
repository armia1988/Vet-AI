grant select on public.alerts to service_role;
grant all on public.push_devices to service_role;
grant all on public.push_deliveries to service_role;
grant usage, select on sequence public.push_deliveries_id_seq to service_role;
