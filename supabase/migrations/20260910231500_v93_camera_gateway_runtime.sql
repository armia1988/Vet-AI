create table if not exists public.camera_gateway_status (
  gateway_device_id uuid primary key references public.sensor_devices(id) on delete cascade,
  farm_id uuid not null references public.farms(id) on delete cascade,
  last_heartbeat_at timestamptz not null default now(),
  agent_version text,
  hostname text,
  platform text,
  cameras_configured integer not null default 0 check (cameras_configured >= 0),
  cameras_online integer not null default 0 check (cameras_online >= 0),
  events_forwarded bigint not null default 0 check (events_forwarded >= 0),
  thermal_samples bigint not null default 0 check (thermal_samples >= 0),
  last_event_at timestamptz,
  last_error text,
  runtime jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists camera_gateway_status_farm_heartbeat_idx
  on public.camera_gateway_status (farm_id, last_heartbeat_at desc);

alter table public.camera_gateway_status enable row level security;

drop policy if exists camera_gateway_status_member_select on public.camera_gateway_status;
create policy camera_gateway_status_member_select
  on public.camera_gateway_status
  for select
  to authenticated
  using (private.is_farm_member(farm_id) or public.is_admin_account('sensors'));

revoke all on public.camera_gateway_status from anon;
revoke insert, update, delete on public.camera_gateway_status from authenticated;
grant select on public.camera_gateway_status to authenticated;
